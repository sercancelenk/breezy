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
    public var settings: SettingsData

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let engine: RuleEngine
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let trasher: any Trasher
    @ObservationIgnored private let http: any HTTPClient

    public init(store: SettingsStore, secrets: any SecretStore, engine: RuleEngine = .standard(),
                home: URL, trasher: any Trasher = WorkspaceTrasher(),
                http: any HTTPClient = URLSessionHTTPClient()) {
        self.store = store; self.secrets = secrets; self.engine = engine
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

    public func scan() async {
        phase = .scanning
        report = nil
        aiStatus = nil
        let ctx = RuleContext(home: home,
                              scanRoots: settings.scanRoots.map { URL(fileURLWithPath: $0, isDirectory: true) },
                              excludedPaths: Set(settings.excludedPaths))
        let result = await engine.scan(ctx, gate: SafetyGate(home: home))
        findings = result
        selected = Set(result.filter { $0.confidence == .high }.map(\.id))
        phase = .ready
    }

    public func aiPrompt() -> AIPrompt? {
        guard settings.aiEnabled, settings.activeProfile != nil else { return nil }
        let candidates = AIScorer.candidates(from: findings)
        return candidates.isEmpty ? nil : AIPrompt(findings: candidates, home: home)
    }

    public func runAI(_ prompt: AIPrompt) async {
        guard let profile = settings.activeProfile else { return }
        let provider = ProviderFactory.make(profile: profile, apiKey: secrets.secret(for: profile.id) ?? "", http: http)
        do {
            findings = try await AIScorer.refine(prompt: prompt, findings: findings, provider: provider)
            aiStatus = "AI \(prompt.indexedIDs.count) öğeyi değerlendirdi."
        } catch {
            aiStatus = "AI kullanılamadı, kural tabanlı sonuçlar gösteriliyor (\(error))."
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

    public func setAPIKey(_ key: String, for id: UUID) { try? secrets.setSecret(key, for: id) }

    public func testConnection(profile: ProviderProfile, apiKey: String) async -> String {
        let provider = ProviderFactory.make(profile: profile, apiKey: apiKey, http: http)
        do {
            let out = try await provider.complete(system: "Reply with the single word OK.", prompt: "ping")
            return "Bağlantı başarılı: \(out.prefix(40))"
        } catch {
            return "Bağlantı başarısız: \(error)"
        }
    }
}
