import Foundation
import Testing
import TestSupport
import CleanerCore
import Safety
@testable import Cleaning

private func finding(_ url: URL, _ size: Int64) -> Finding {
    Finding(url: url, size: size, category: .cache, confidence: .high, reason: "r", lastModified: nil)
}

@Test func dryRunSeparatesRejected() throws {
    let t = try TempDir(); defer { t.remove() }
    let ok = finding(t.url.appendingPathComponent("Library/Caches/a"), 10)
    let bad = finding(URL(fileURLWithPath: "/usr/lib"), 99)
    let run = Cleaner(gate: SafetyGate(home: t.url), trasher: StubTrasher()).preview([ok, bad])
    #expect(run.allowed == [ok] && run.rejected == [bad] && run.totalBytes == 10)
}

@Test func cleanReportsPartialFailuresWithoutStopping() async throws {
    let t = try TempDir(); defer { t.remove() }
    let a = finding(t.url.appendingPathComponent("Library/Caches/a"), 10)
    let b = finding(t.url.appendingPathComponent("Library/Caches/b"), 20)
    let c = finding(t.url.appendingPathComponent("Library/Caches/c"), 40)
    let evil = finding(URL(fileURLWithPath: "/usr/lib"), 99)
    let stub = StubTrasher(failing: [b.url.path])
    let report = await Cleaner(gate: SafetyGate(home: t.url), trasher: stub).clean([a, b, c, evil])
    #expect(report.trashed == [a, c])
    #expect(report.reclaimedBytes == 50)
    #expect(Set(report.failures.map(\.finding.id)) == [b.id, evil.id])
    #expect(report.failures.first { $0.finding.id == b.id }?.message == "izin reddedildi")
    #expect(await stub.trashed == [a.url, c.url])   // /usr/lib'e dokunulmadı
}
