import Foundation
import Observation
import CleanerCore
import Rules
import Safety
import Preferences
import AI
import Cleaning

@MainActor @Observable
public final class ScanViewModel {
    public enum Phase: Equatable, Sendable { case idle, scanning, ready, cleaning, done }

    public private(set) var phase: Phase = .idle
    public private(set) var findings: [Finding] = []
    public var selected: Set<String> = []
    public private(set) var report: CleanReport?
    public private(set) var aiStatus: String?
    public private(set) var aiRunning = false
    /// Son AI isteği başarısızsa nedeni; başarılıysa nil.
    public private(set) var aiError: String?
    public private(set) var isLargeScanning = false
    /// Büyük öğe taraması en az bir kez tamamlandı mı (boş sonuç ile "hiç taranmadı"yı ayırmak için).
    public private(set) var largeScanned = false
    public private(set) var categoryScanning: FindingCategory?
    private(set) var scanTask: Task<Void, Never>?
    private(set) var largeTask: Task<Void, Never>?
    private var categoryTask: Task<Void, Never>?
    /// Çöp Kutusu'na taşınan öğe kimlikleri; süren taramaların bayat sonuçlarını süzmek için.
    private var trashLog: [String] = []
    public var settings: SettingsData

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let engine: RuleEngine
    @ObservationIgnored private let largeEngine: RuleEngine
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let trasher: any Trasher
    @ObservationIgnored private let http: any HTTPClient

    public init(store: SettingsStore, secrets: any SecretStore, engine: RuleEngine = .standard(), largeEngine: RuleEngine = .largeItems(),
                home: URL, trasher: any Trasher = WorkspaceTrasher(),
                http: any HTTPClient = URLSessionHTTPClient()) {
        self.store = store; self.secrets = secrets; self.engine = engine; self.largeEngine = largeEngine
        self.home = home; self.trasher = trasher; self.http = http
        self.settings = store.load(home: home)
    }

    public static func live() -> ScanViewModel {
        ScanViewModel(store: .standard, secrets: KeychainSecretStore(),
                      home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Full Disk Access yoksa Safari klasörü listelenemez (TCC reddi).
    public static func hasFullDiskAccess(home: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Safari").path)
            return true
        } catch {
            let ns = error as NSError
            let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            return !(ns.code == NSFileReadNoPermissionError || posix == Int(EPERM) || posix == Int(EACCES))
        }
    }

    // MARK: Türetilmiş durum

    /// Akıllı tarama (kategoriler) ve büyük öğeler ayrı kapsamlardır; toplamlar, seçim ve temizlik kapsam başınadır.
    public enum Scope: Sendable { case smart, large }

    public var smartFindings: [Finding] { findings.filter { $0.category != .large } }
    public var largeFindings: [Finding] { findings.filter { $0.category == .large } }

    public var grouped: [(category: FindingCategory, items: [Finding])] {
        FindingCategory.allCases.compactMap { c in
            let items = smartFindings.filter { $0.category == c }
            return items.isEmpty ? nil : (category: c, items: items)
        }
    }
    public var selectedFindings: [Finding] { smartFindings.filter { selected.contains($0.id) } }
    public var selectedLargeFindings: [Finding] { largeFindings.filter { selected.contains($0.id) } }
    public var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.size } }
    public var selectedLargeBytes: Int64 { selectedLargeFindings.reduce(0) { $0 + $1.size } }
    public var totalBytes: Int64 { smartFindings.reduce(0) { $0 + $1.size } }
    public var largeBytes: Int64 { largeFindings.reduce(0) { $0 + $1.size } }

    private func scoped(_ scope: Scope) -> [Finding] { scope == .smart ? smartFindings : largeFindings }
    private func selected(in scope: Scope) -> [Finding] { scope == .smart ? selectedFindings : selectedLargeFindings }

    // MARK: Akış

    public func startScan() {
        guard phase != .scanning else { return }
        phase = .scanning
        scanTask = Task { await scan() }
    }

    public func cancelScan() { scanTask?.cancel() }

    public func scan() async {
        let before = phase == .scanning ? Phase.idle : phase
        phase = .scanning
        report = nil
        aiStatus = nil
        let homePath = home.standardizedFileURL.path
        let roots = settings.scanRoots
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .filter { $0.path == homePath || $0.path.hasPrefix(homePath + "/") }
        let ctx = RuleContext(home: home, scanRoots: roots, excludedPaths: Set(settings.excludedPaths),
                              largeThreshold: largeThresholdBytes)
        let mark = trashLog.count
        let raw = await engine.scan(ctx, gate: SafetyGate(home: home))
        if Task.isCancelled { phase = findings.isEmpty ? .idle : before; return }
        let result = withoutTrashed(raw, since: mark)
        let keptLarge = findings.filter { $0.category == .large }
        findings = RuleEngine.reconcileLarge(result + keptLarge, threshold: largeThresholdBytes)
            .sorted { $0.size > $1.size }
        selected = Set(result.filter { $0.confidence == .high && $0.impact.preselectable }.map(\.id))
        phase = .ready
    }

    private func withoutTrashed(_ items: [Finding], since mark: Int) -> [Finding] {
        let gone = Set(trashLog[mark...])
        return gone.isEmpty ? items : items.filter { !gone.contains($0.id) }
    }

    private var largeThresholdBytes: Int64 { Int64(max(100, settings.largeItemThresholdMB)) * 1_048_576 }

    public func startLargeScan() {
        guard !isLargeScanning else { return }
        isLargeScanning = true
        largeTask = Task { await scanLarge() }
    }

    public func startCategoryScan(_ c: FindingCategory) {
        guard categoryScanning == nil else { return }
        if c == .large { startLargeScan(); return }
        categoryScanning = c
        categoryTask = Task { await scanCategory(c) }
    }

    public func cancelCategoryScan() { categoryTask?.cancel() }

    /// Yalnızca bir kategoriyi yeniden tarar; diğer kategorilerin bulguları ve seçimleri korunur.
    public func scanCategory(_ c: FindingCategory) async {
        if c == .large { await scanLarge(); return }
        categoryScanning = c
        defer { categoryScanning = nil }
        let homePath = home.standardizedFileURL.path
        let roots = settings.scanRoots
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .filter { $0.path == homePath || $0.path.hasPrefix(homePath + "/") }
        let ctx = RuleContext(home: home, scanRoots: roots, excludedPaths: Set(settings.excludedPaths),
                              largeThreshold: largeThresholdBytes)
        let mark = trashLog.count
        let raw = await engine.scan(ctx, gate: SafetyGate(home: home), categories: [c])
        if Task.isCancelled { return }
        let result = withoutTrashed(raw, since: mark)
        let old = Set(findings.filter { $0.category == c }.map(\.id))
        let others = findings.filter { $0.category != c }
        findings = RuleEngine.reconcileLarge(others + result, threshold: largeThresholdBytes).sorted { $0.size > $1.size }
        selected.subtract(old)
        selected.formUnion(result.filter { $0.confidence == .high && $0.impact.preselectable }.map(\.id))
        selected.formIntersection(Set(findings.map(\.id)))
        if phase == .idle { phase = .ready }
    }

    public func cancelLargeScan() { largeTask?.cancel() }

    /// Ev dizinindeki büyük öğeler; akıllı taramadan bağımsız, sonuçlar mevcut listeye eklenir.
    public func scanLarge() async {
        isLargeScanning = true
        defer { isLargeScanning = false }
        let ctx = RuleContext(home: home, excludedPaths: Set(settings.excludedPaths), largeThreshold: largeThresholdBytes)
        let mark = trashLog.count
        let raw = await largeEngine.scan(ctx, gate: SafetyGate(home: home))
        if Task.isCancelled { return }
        let result = withoutTrashed(raw, since: mark)
        let others = findings.filter { $0.category != .large }
        findings = RuleEngine.reconcileLarge(others + result.filter { $0.category == .large }, threshold: largeThresholdBytes)
            .sorted { $0.size > $1.size }
        selected.formIntersection(Set(findings.map(\.id)))
        largeScanned = true
    }

    /// AI düğmesinin neden kapalı olduğu; kullanılabilirse nil.
    public var aiUnavailableReason: String? { aiUnavailableReason(single: false) }

    /// `single`: tek öğe sorulurken aday filtresi aranmaz.
    public func aiUnavailableReason(single: Bool, scope: Scope = .smart) -> String? {
        if settings.profiles.isEmpty { return "Tanımlı AI profili yok. Ayarlar → AI bölümünden bir profil ekleyip API key'ini gir." }
        if !settings.aiEnabled { return "AI desteği kapalı. Ayarlar → AI'dan aç ya da bağlantı testini başarıyla çalıştır." }
        if settings.activeProfile == nil { return "Aktif AI profili seçilmemiş. Ayarlar → AI → Aktif profil'den seç." }
        if single { return nil }
        if scoped(scope).isEmpty { return "Önce bir tarama yap; AI taranan öğeleri değerlendirir." }
        if AIScorer.candidates(from: scoped(scope)).isEmpty { return "AI'ın değerlendireceği belirsiz öğe yok; hepsi kural tarafından biliniyor. Tek bir öğe için kartındaki \"AI'a sor\"u kullanabilirsin." }
        return nil
    }

    /// Tek öğe için AI görüşü; öğe zaten yüksek güvenli olsa da sorulabilir.
    public func aiPrompt(for finding: Finding) -> AIPrompt? {
        guard aiUnavailableReason(single: true) == nil else { return nil }
        return AIPrompt(findings: [finding], home: home)
    }

    public func aiPrompt(in scope: Scope = .smart) -> AIPrompt? {
        guard settings.aiEnabled, settings.activeProfile != nil else { return nil }
        let candidates = AIScorer.candidates(from: scoped(scope))
        return candidates.isEmpty ? nil : AIPrompt(findings: candidates, home: home)
    }

    public func runAI(_ prompt: AIPrompt) async {
        guard let profile = settings.activeProfile else { return }
        guard !aiRunning else { aiError = "Başka bir AI isteği sürüyor; bitmesini bekle."; return }
        aiRunning = true
        aiError = nil
        defer { aiRunning = false }
        let provider = ProviderFactory.make(profile: profile, apiKey: secrets.secret(for: profile.id) ?? "", http: http)
        do {
            let text = try await provider.complete(system: prompt.system, prompt: prompt.user)
            findings = AIScorer.apply(try AIScorer.parse(text), to: findings, prompt: prompt)
            selected.subtract(findings.filter { !$0.impact.preselectable }.map(\.id))
            aiStatus = "AI \(prompt.indexedIDs.count) öğeyi değerlendirdi."
        } catch {
            aiError = error.localizedDescription
            aiStatus = "AI kullanılamadı, kural tabanlı sonuçlar gösteriliyor (\(error.localizedDescription))."
        }
    }

    public func dryRun(scope: Scope = .smart) -> DryRun {
        Cleaner(gate: SafetyGate(home: home), trasher: trasher).preview(selected(in: scope))
    }

    public func clean(scope: Scope = .smart) async {
        phase = .cleaning
        let r = await Cleaner(gate: SafetyGate(home: home), trasher: trasher).clean(selected(in: scope))
        report = r
        let gone = Set(r.trashed.map(\.id))
        trashLog += gone
        findings.removeAll { gone.contains($0.id) }
        selected.subtract(gone)
        phase = .done
    }

    // MARK: Ayarlar

    public func saveSettings() { try? store.save(settings) }

    public func apiKey(for id: UUID) -> String { secrets.secret(for: id) ?? "" }

    /// Keychain'e yazar; başarısızlığı arayüzün gösterebilmesi için bildirir.
    @discardableResult
    public func setAPIKey(_ key: String, for id: UUID) -> Bool {
        do {
            try secrets.setSecret(key.trimmingCharacters(in: .whitespacesAndNewlines), for: id)
            return true
        } catch {
            return false
        }
    }

    public func testConnection(profile: ProviderProfile, apiKey: String) async -> String {
        let provider = ProviderFactory.make(profile: profile, apiKey: apiKey, http: http)
        do {
            let out = try await provider.complete(system: "Reply with the single word OK.", prompt: "ping")
            if settings.profiles.contains(where: { $0.id == profile.id }) {
                settings.activeProfileID = profile.id
                settings.aiEnabled = true
                saveSettings()
            }
            return "Bağlantı başarılı: \(out.prefix(40)). AI etkinleştirildi."
        } catch {
            return "Bağlantı başarısız: \(error.localizedDescription)"
        }
    }
}
