import Foundation
import Testing
import TestSupport
import CleanerCore
import Safety
@testable import Rules

private struct FixedRule: Rule {
    let findings: [Finding]
    func scan(_ context: RuleContext) -> [Finding] { findings }
}

@Test func childrenRuleListsNonEmptyChildrenExceptExcluded() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Library/Caches/com.a/x.bin", bytes: 10_000)
    try t.file("Library/Caches/Homebrew/y.bin", bytes: 10_000)
    try t.dir("Library/Caches/empty")
    let rule = ChildrenRule(category: .cache, relativeDirectory: "Library/Caches",
                            excluding: ["Homebrew"], confidence: .high, reason: "r")
    let out = rule.scan(RuleContext(home: t.url))
    #expect(out.map { $0.url.lastPathComponent } == ["com.a"])
    #expect(out[0].size >= 10_000)
}

@Test func fixedPathsRuleSkipsMissingAndEmpty() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Library/Developer/Xcode/DerivedData/p/o.bin", bytes: 8_000)
    try t.dir("Library/Developer/CoreSimulator/Caches")
    let rule = FixedPathsRule(category: .xcode, entries: [
        .init(relativePath: "Library/Developer/Xcode/DerivedData", reason: "d", confidence: .high),
        .init(relativePath: "Library/Developer/CoreSimulator/Caches", reason: "c", confidence: .high),
        .init(relativePath: "Library/Missing", reason: "m", confidence: .low),
    ])
    let out = rule.scan(RuleContext(home: t.url))
    #expect(out.map { $0.url.lastPathComponent } == ["DerivedData"])
}

@Test func engineFiltersUnsafeExcludedAndDuplicatesAndSortsBySize() async throws {
    let t = try TempDir(); defer { t.remove() }
    func f(_ rel: String, _ size: Int64) -> Finding {
        Finding(url: t.url.appendingPathComponent(rel), size: size, category: .cache,
                confidence: .high, reason: "r", lastModified: nil)
    }
    let outside = Finding(url: URL(fileURLWithPath: "/usr/lib"), size: 99, category: .cache,
                          confidence: .high, reason: "r", lastModified: nil)
    let rules: [any Rule] = [
        FixedRule(findings: [f("Library/Caches/a", 10), f("Library/Caches/b", 30), outside]),
        FixedRule(findings: [f("Library/Caches/a", 10), f("Library/Caches/c", 20)]),
    ]
    let ctx = RuleContext(home: t.url,
                          excludedPaths: [t.url.appendingPathComponent("Library/Caches/c").path])
    let out = await RuleEngine(rules: rules).scan(ctx, gate: SafetyGate(home: t.url))
    #expect(out.map(\.size) == [30, 10])
}

@Test func excludedParentExcludesItsDescendants() async throws {
    let t = try TempDir(); defer { t.remove() }
    let child = Finding(url: t.url.appendingPathComponent("proj/node_modules"), size: 10, category: .devArtifact,
                        confidence: .high, reason: "r", lastModified: nil)
    let sibling = Finding(url: t.url.appendingPathComponent("proj2/node_modules"), size: 5, category: .devArtifact,
                          confidence: .high, reason: "r", lastModified: nil)
    let ctx = RuleContext(home: t.url, excludedPaths: [t.url.appendingPathComponent("proj").path])
    let out = await RuleEngine(rules: [FixedRule(findings: [child, sibling])]).scan(ctx, gate: SafetyGate(home: t.url))
    #expect(out.map(\.size) == [5])
}

@Test func cacheChildrenGetKnownAppImpactOrGenericFlag() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Library/Caches/JetBrains/IntelliJIdea/idx.bin", bytes: 10_000)
    try t.file("Library/Caches/com.mystery.app/x.bin", bytes: 10_000)
    let rule = ChildrenRule(category: .cache, relativeDirectory: "Library/Caches", excluding: [],
                            confidence: .high, reason: "r", impact: .genericCache, knownApps: true)
    let out = rule.scan(RuleContext(home: t.url))
    let jb = try #require(out.first { $0.url.lastPathComponent == "JetBrains" })
    let other = try #require(out.first { $0.url.lastPathComponent == "com.mystery.app" })
    #expect(!jb.impact.isGeneric && jb.impact.note.contains("indeks"))
    #expect(other.impact.isGeneric)
}

@Test func standardRulesDeclareImpactAndArchivesDoNotComeBack() async throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Library/Developer/Xcode/Archives/a.xcarchive/i.bin", bytes: 10_000)
    try t.file("Library/Developer/Xcode/DerivedData/p/o.bin", bytes: 10_000)
    try t.file("Library/Logs/app.log", bytes: 10_000)
    let engine = RuleEngine.standard()
    let out = await awaitScan(engine, t)
    #expect(out.first { $0.url.lastPathComponent == "Archives" }?.impact.regeneration == .never)
    #expect(out.first { $0.url.lastPathComponent == "DerivedData" }?.impact.regeneration == .automatic)
    #expect(out.first { $0.url.lastPathComponent == "Logs" || $0.url.lastPathComponent == "app.log" }?.impact.note.isEmpty == false)
}

private func awaitScan(_ engine: RuleEngine, _ t: TempDir) async -> [Finding] {
    await engine.scan(RuleContext(home: t.url), gate: SafetyGate(home: t.url))
}
