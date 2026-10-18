import Foundation
import Testing
import TestSupport
import CleanerCore
import Rules
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
