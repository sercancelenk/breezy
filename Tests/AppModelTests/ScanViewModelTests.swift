import Foundation
import Testing
import TestSupport
import CleanerCore
import Rules
import Safety
import Preferences
import AI
import Cleaning
@testable import AppModel

private struct StubRule: Rule {
    let findings: [Finding]
    func scan(_ context: RuleContext) -> [Finding] { findings }
}

private func finding(_ t: TempDir, _ name: String, _ size: Int64, _ c: Confidence) -> Finding {
    Finding(url: t.url.appendingPathComponent("Library/Caches/\(name)"), size: size, category: .cache,
            confidence: c, reason: "r", lastModified: nil)
}

@MainActor
private func makeModel(_ t: TempDir, findings: [Finding], trasher: any Trasher = StubTrasher(),
                       http: any HTTPClient = StubHTTP(json: "{}")) -> ScanViewModel {
    ScanViewModel(store: SettingsStore(fileURL: t.url.appendingPathComponent("s.json")),
                  secrets: InMemorySecretStore(),
                  engine: RuleEngine(rules: [StubRule(findings: findings)]),
                  home: t.url, trasher: trasher, http: http)
}

@MainActor @Test func scanSortsPreselectsHighAndHandlesEmpty() async throws {
    let t = try TempDir(); defer { t.remove() }
    let big = finding(t, "big", 300, .high), mid = finding(t, "mid", 200, .medium)
    let m = makeModel(t, findings: [mid, big])
    await m.scan()
    #expect(m.phase == .ready)
    #expect(m.findings.map(\.id) == [big.id, mid.id])
    #expect(m.selected == [big.id])
    #expect(m.totalBytes == 500 && m.selectedBytes == 300)
    let empty = makeModel(t, findings: [])
    await empty.scan()
    #expect(empty.phase == .ready && empty.findings.isEmpty)
}

@MainActor @Test func cleanRemovesTrashedKeepsFailedAndReports() async throws {
    let t = try TempDir(); defer { t.remove() }
    let a = finding(t, "a", 10, .high), b = finding(t, "b", 20, .high)
    let m = makeModel(t, findings: [a, b], trasher: StubTrasher(failing: [b.url.path]))
    await m.scan()
    await m.clean()
    #expect(m.phase == .done)
    #expect(m.report?.trashed.map(\.id) == [a.id])
    #expect(m.report?.failures.map(\.finding.id) == [b.id])
    #expect(m.findings.map(\.id) == [b.id])
}

@MainActor @Test func aiOffReturnsNilAndFailureKeepsRuleResults() async throws {
    let t = try TempDir(); defer { t.remove() }
    let med = finding(t, "m", 10, .medium)
    let ok = StubHTTP(json: #"{"content":[{"text":"[{\"i\":0,\"confidence\":\"high\",\"reason\":\"güvenli\"}]"}]}"#)
    let m = makeModel(t, findings: [med], http: ok)
    await m.scan()
    #expect(m.aiPrompt() == nil)                       // AI kapalı
    let profile = ProviderProfile.anthropic()
    m.settings.profiles = [profile]; m.settings.activeProfileID = profile.id; m.settings.aiEnabled = true
    let prompt = try #require(m.aiPrompt())
    await m.runAI(prompt)
    #expect(m.findings.first?.confidence == .high)
    let bad = makeModel(t, findings: [med], http: StubHTTP(status: 500, json: "{}"))
    await bad.scan()
    bad.settings.profiles = [profile]; bad.settings.activeProfileID = profile.id; bad.settings.aiEnabled = true
    await bad.runAI(try #require(bad.aiPrompt()))
    #expect(bad.findings.first?.confidence == .medium)
    #expect(bad.aiStatus?.contains("kural tabanlı") == true)
}

private final class Box: @unchecked Sendable { var model: ScanViewModel? }

private struct HookHTTP: HTTPClient {
    let reply: String
    let onSend: @Sendable () async -> Void
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        await onSend()
        return (Data(reply.utf8), 200)
    }
}

private struct FailingHTTP: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        throw URLError(.notConnectedToInternet,
                       userInfo: ["NSErrorFailingURLStringKey": "https://h/p?key=SECRET123"])
    }
}

@MainActor @Test func aiResultDoesNotResurrectItemsCleanedWhileInFlight() async throws {
    let t = try TempDir(); defer { t.remove() }
    let med = finding(t, "m", 10, .medium), hi = finding(t, "h", 20, .high)
    let box = Box()
    let http = HookHTTP(reply: #"{"content":[{"text":"[{\"i\":0,\"confidence\":\"high\",\"reason\":\"ok\"}]"}]}"#) {
        await box.model?.clean()
    }
    let m = makeModel(t, findings: [med, hi], http: http)
    box.model = m
    await m.scan()
    let profile = ProviderProfile.anthropic()
    m.settings.profiles = [profile]; m.settings.activeProfileID = profile.id; m.settings.aiEnabled = true
    await m.runAI(try #require(m.aiPrompt()))
    #expect(m.findings.map(\.id) == [med.id])
    #expect(m.findings.first?.confidence == .high)
    #expect(!m.aiRunning)
}

@MainActor @Test func errorTextsNeverContainQueryKey() async throws {
    let t = try TempDir(); defer { t.remove() }
    let med = finding(t, "m", 10, .medium)
    let m = makeModel(t, findings: [med], http: FailingHTTP())
    await m.scan()
    let profile = ProviderProfile.anthropic()
    m.settings.profiles = [profile]; m.settings.activeProfileID = profile.id; m.settings.aiEnabled = true
    await m.runAI(try #require(m.aiPrompt()))
    #expect(m.aiStatus?.contains("SECRET123") == false)
    let r = await m.testConnection(profile: profile, apiKey: "k")
    #expect(!r.contains("SECRET123"))
}

private struct BlockingRule: Rule {
    func scan(_ context: RuleContext) -> [Finding] {
        while !Task.isCancelled { usleep(1_000) }
        return []
    }
}

@MainActor @Test func cancelledScanPublishesNothing() async throws {
    let t = try TempDir(); defer { t.remove() }
    let m = ScanViewModel(store: SettingsStore(fileURL: t.url.appendingPathComponent("s.json")),
                          secrets: InMemorySecretStore(), engine: RuleEngine(rules: [BlockingRule()]),
                          home: t.url, trasher: StubTrasher(), http: StubHTTP(json: "{}"))
    m.startScan()
    #expect(m.phase == .scanning)
    m.cancelScan()
    await m.scanTask?.value
    #expect(m.phase == .idle && m.findings.isEmpty)
}

private struct RootsRule: Rule {
    let t: URL
    func scan(_ context: RuleContext) -> [Finding] {
        context.scanRoots.map {
            Finding(url: t.appendingPathComponent("Library/Caches/\($0.lastPathComponent)"), size: 1,
                    category: .cache, confidence: .high, reason: "r", lastModified: nil)
        }
    }
}

@MainActor @Test func scanRootsOutsideHomeAreIgnored() async throws {
    let t = try TempDir(); defer { t.remove() }
    let m = ScanViewModel(store: SettingsStore(fileURL: t.url.appendingPathComponent("s.json")),
                          secrets: InMemorySecretStore(), engine: RuleEngine(rules: [RootsRule(t: t.url)]),
                          home: t.url, trasher: StubTrasher(), http: StubHTTP(json: "{}"))
    m.settings.scanRoots = [t.url.appendingPathComponent("in").path, "/Volumes/ext/out"]
    await m.scan()
    #expect(m.findings.map { $0.url.lastPathComponent } == ["in"])
}

@MainActor @Test func itemsThatDoNotComeBackAreNeverPreselected() async throws {
    let t = try TempDir(); defer { t.remove() }
    var archive = finding(t, "arch", 300, .high)
    archive.impact = Impact(regeneration: .never, risk: .high, note: "geri gelmez")
    let cache = finding(t, "c", 100, .high)
    let m = makeModel(t, findings: [archive, cache])
    await m.scan()
    #expect(m.selected == [cache.id])
}

private func largeFinding(_ t: TempDir, _ name: String, _ size: Int64) -> Finding {
    Finding(url: t.url.appendingPathComponent("Other/\(name)"), size: size, category: .large, confidence: .low,
            reason: "r", lastModified: nil,
            impact: Impact(regeneration: .never, risk: .medium, note: "n", isGeneric: true))
}

@MainActor private func makeModel(_ t: TempDir, findings: [Finding], large: [Finding]) -> ScanViewModel {
    ScanViewModel(store: SettingsStore(fileURL: t.url.appendingPathComponent("s.json")),
                  secrets: InMemorySecretStore(),
                  engine: RuleEngine(rules: [StubRule(findings: findings)]),
                  largeEngine: RuleEngine(rules: [StubRule(findings: large)]),
                  home: t.url, trasher: StubTrasher(), http: StubHTTP(json: "{}"))
}

@MainActor @Test func largeScanIsSeparateMergesAndNeverSelects() async throws {
    let t = try TempDir(); defer { t.remove() }
    let cache = finding(t, "c", 100, .high)
    let m = makeModel(t, findings: [cache], large: [largeFinding(t, "big", 5_000)])
    await m.scanLarge()                       // akıllı tarama yapılmadan da çalışır
    #expect(m.findings.map(\.category) == [.large] && m.selected.isEmpty && m.phase == .ready)
    await m.scan()                            // akıllı tarama büyük öğeleri silmez
    #expect(Set(m.findings.map(\.category)) == [.cache, .large])
    #expect(m.selected == [cache.id])
    await m.scanLarge()                       // tekrar taramak eskisini değiştirir, çoğaltmaz
    #expect(m.findings.filter { $0.category == .large }.count == 1)
    #expect(!m.isLargeScanning)
}

@MainActor @Test func largeScanDropsItemsInsideSmartFindings() async throws {
    let t = try TempDir(); defer { t.remove() }
    let cache = finding(t, "c", 100, .high)
    let inner = Finding(url: cache.url.appendingPathComponent("deep"), size: 50, category: .large, confidence: .low,
                        reason: "r", lastModified: nil)
    let m = makeModel(t, findings: [cache], large: [inner])
    await m.scan()
    await m.scanLarge()
    #expect(m.findings.map(\.id) == [cache.id])
}

@Test func standardEngineDoesNotWalkWholeHomeForLargeItems() async throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Other/blob/b.bin", bytes: 120_000)
    let out = await RuleEngine.standard().scan(RuleContext(home: t.url, largeThreshold: 50_000),
                                               gate: SafetyGate(home: t.url))
    #expect(!out.contains { $0.category == .large })
}

@MainActor @Test func successfulConnectionTestActivatesAIImmediately() async throws {
    let t = try TempDir(); defer { t.remove() }
    let ok = StubHTTP(json: #"{"content":[{"text":"OK"}]}"#)
    let m = makeModel(t, findings: [finding(t, "m", 10, .medium)], http: ok)
    await m.scan()
    let profile = ProviderProfile.anthropic()
    m.settings.profiles = [profile]
    #expect(m.aiUnavailableReason?.contains("kapalı") == true)
    let r = await m.testConnection(profile: profile, apiKey: "k")
    #expect(r.contains("başarılı"))
    #expect(m.settings.aiEnabled && m.settings.activeProfileID == profile.id)
    #expect(m.aiUnavailableReason == nil && m.aiPrompt() != nil)
    let t2 = try TempDir(); defer { t2.remove() }
    let bad = makeModel(t2, findings: [], http: StubHTTP(status: 401, json: "{}"))
    bad.settings.profiles = [profile]
    _ = await bad.testConnection(profile: profile, apiKey: "k")
    #expect(!bad.settings.aiEnabled)
}
