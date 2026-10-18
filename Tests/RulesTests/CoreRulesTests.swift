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
