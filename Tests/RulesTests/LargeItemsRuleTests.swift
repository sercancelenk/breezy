import Foundation
import Testing
import TestSupport
import CleanerCore
import Safety
@testable import Rules

private let threshold: Int64 = 50_000

private func scan(_ t: TempDir, threshold: Int64 = threshold) -> [Finding] {
    LargeItemsRule().scan(RuleContext(home: t.url, largeThreshold: threshold))
}

@Test func reportsLeafMostBigDirsAndBigFilesOnly() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Movies/film/a.mov", bytes: 120_000)
    try t.file("Projects/app/data/blob.bin", bytes: 70_000)
    try t.file("Projects/app/small.txt", bytes: 1_000)
    try t.file("Misc/tiny/x.bin", bytes: 2_000)
    try t.file("big.iso", bytes: 90_000)
    let names = Set(scan(t).map { $0.url.path.replacingOccurrences(of: t.url.path + "/", with: "") })
    #expect(names == ["Movies/film/a.mov", "Projects/app/data/blob.bin", "big.iso"])
}

@Test func largeItemsAreNeverPreselectedAndFlagUserFolders() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Movies/film/a.mov", bytes: 120_000)
    try t.file("Other/blob/b.bin", bytes: 120_000)
    let out = scan(t)
    let movie = try #require(out.first { $0.url.lastPathComponent == "a.mov" })
    let other = try #require(out.first { $0.url.lastPathComponent == "b.bin" })
    #expect(movie.category == .large && movie.confidence == .low)
    #expect(movie.impact.userData && !movie.impact.preselectable)
    #expect(other.impact.isGeneric && !other.impact.preselectable && !other.impact.userData)
}

@Test func thresholdZeroDisablesAndSymlinksAreNotFollowed() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("real/huge.bin", bytes: 200_000)
    try FileManager.default.createSymbolicLink(at: t.url.appendingPathComponent("link"),
                                               withDestinationURL: t.url.appendingPathComponent("real"))
    #expect(scan(t, threshold: 0).isEmpty)
    #expect(scan(t).map { $0.url.path }.allSatisfy { !$0.hasSuffix("/link") && !$0.contains("/link/") })
}

@Test func looksInsideLibraryWrappersAndSkipsNodeModules() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Library/Application Support/MobileSync/Backup/abc/data.bin", bytes: 150_000)
    try t.file("proj/node_modules/x/y.bin", bytes: 150_000)
    let out = scan(t).map { $0.url.path }
    #expect(out.contains { $0.hasSuffix("MobileSync/Backup/abc/data.bin") })
    #expect(!out.contains { $0.contains("node_modules") })
}

private struct FixedRule: Rule {
    let findings: [Finding]
    func scan(_ context: RuleContext) -> [Finding] { findings }
}

private func f(_ t: TempDir, _ rel: String, _ size: Int64, _ c: FindingCategory) -> Finding {
    Finding(url: t.url.appendingPathComponent(rel), size: size, category: c, confidence: .low,
            reason: "r", lastModified: nil)
}

@Test func engineDropsLargeItemsCoveredByOtherFindingsAndSubtractsInnerOnes() async throws {
    let t = try TempDir(); defer { t.remove() }
    let rules: [any Rule] = [FixedRule(findings: [
        f(t, "Library/Caches/a", 500, .cache),
        f(t, "Library/Caches/a/sub", 400, .large),        // aynı ağacın içinde → düş
        f(t, "proj", 1_000, .large),                      // içinde dev artifact var → 1000-700 = 300
        f(t, "proj/node_modules", 700, .devArtifact),
        f(t, "proj2", 1_000, .large),
        f(t, "proj2/target", 990, .devArtifact),          // kalan 10 < eşik → düş
        f(t, "free", 900, .large),
    ])]
    let ctx = RuleContext(home: t.url, largeThreshold: 200)
    let out = await RuleEngine(rules: rules).scan(ctx, gate: SafetyGate(home: t.url))
    let large = out.filter { $0.category == .large }.map { "\($0.url.lastPathComponent):\($0.size)" }
    #expect(Set(large) == ["proj:300", "free:900"])
}
