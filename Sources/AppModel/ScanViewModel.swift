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
    public private(set) var isLargeScanning = false
    private(set) var scanTask: Task<Void, Never>?
    private(set) var largeTask: Task<Void, Never>?
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

    public var grouped: [(category: FindingCategory, items: [Finding])] {
        FindingCategory.allCases.compactMap { c in
            let items = findings.filter { $0.category == c }
            return items.isEmpty ? nil : (category: c, items: items)
        }
    }
    public var selectedFindings: [Finding] { findings.filter { selected.contains($0.id) } }
    public var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.size } }
    public var totalBytes: Int64 { findings.reduce(0) { $0 + $1.size } }

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
                              largeThreshold: Int64(max(0, settings.largeItemThresholdMB)) * 1_048_576)
        let result = await engine.scan(ctx, gate: SafetyGate(home: home))
        if Task.isCancelled { phase = findings.isEmpty ? .idle : before; return }
        let keptLarge = findings.filter { $0.category == .large }
        findings = RuleEngine.reconcileLarge(result + keptLarge, threshold: largeThresholdBytes)
            .sorted { $0.size > $1.size }
        selected = Set(result.filter { $0.confidence == .high && $0.impact.preselectable }.map(\.id))
        phase = .ready
    }

    private var largeThresholdBytes: Int64 { Int64(max(100, settings.largeItemThresholdMB)) * 1_048_576 }

    public func startLargeScan() {
        guard !isLargeScanning else { return }
        isLargeScanning = true
        largeTask = Task { await scanLarge() }
    }

    public func cancelLargeScan() { largeTask?.cancel() }

    /// Ev dizinindeki büyük öğeler; akıllı taramadan bağımsız, sonuçlar mevcut listeye eklenir.
    public func scanLarge() async {
        isLargeScanning = true
        defer { isLargeScanning = false }
        let ctx = RuleContext(home: home, excludedPaths: Set(settings.excludedPaths), largeThreshold: largeThresholdBytes)
        let result = await largeEngine.scan(ctx, gate: SafetyGate(home: home))
        if Task.isCancelled { return }
        let others = findings.filter { $0.category != .large }
        findings = RuleEngine.reconcileLarge(others + result.filter { $0.category == .large }, threshold: largeThresholdBytes)
            .sorted { $0.size > $1.size }
        selected.formIntersection(Set(findings.map(\.id)))
        if phase == .idle { phase = .ready }
    }

    /// AI düğmesinin neden kapalı olduğu; kullanılabilirse nil.
    public var aiUnavailableReason: String? {
        if !settings.aiEnabled { return "AI desteği kapalı" }
        if settings.activeProfile == nil { return "Aktif AI profili yok" }
        if findings.isEmpty { return "Önce tarama yap" }
        if AIScorer.candidates(from: findings).isEmpty { return "AI'ın değerlendireceği öğe yok" }
        return nil
    }

    public func aiPrompt() -> AIPrompt? {
        guard settings.aiEnabled, settings.activeProfile != nil else { return nil }
        let candidates = AIScorer.candidates(from: findings)
        return candidates.isEmpty ? nil : AIPrompt(findings: candidates, home: home)
    }

    public func runAI(_ prompt: AIPrompt) async {
        guard let profile = settings.activeProfile, !aiRunning else { return }
        aiRunning = true
        defer { aiRunning = false }
        let provider = ProviderFactory.make(profile: profile, apiKey: secrets.secret(for: profile.id) ?? "", http: http)
        do {
            let text = try await provider.complete(system: prompt.system, prompt: prompt.user)
            findings = AIScorer.apply(try AIScorer.parse(text), to: findings, prompt: prompt)
            selected.subtract(findings.filter { !$0.impact.preselectable }.map(\.id))
            aiStatus = "AI \(prompt.indexedIDs.count) öğeyi değerlendirdi."
        } catch {
            aiStatus = "AI kullanılamadı, kural tabanlı sonuçlar gösteriliyor (\(error.localizedDescription))."
        }
    }

    public func dryRun() -> DryRun {
        Cleaner(gate: SafetyGate(home: home), trasher: trasher).preview(selectedFindings)
    }

    public func clean() async {
        phase = .cleaning
        let r = await Cleaner(gate: SafetyGate(home: home), trasher: trasher).clean(selectedFindings)
        report = r
        let gone = Set(r.trashed.map(\.id))
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
