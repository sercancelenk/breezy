import Foundation
import Testing
import TestSupport
import CleanerCore
import Safety
@testable import Rules

@Test func downloadsListsOnlyOldNonInstallerItemsAsUserData() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Downloads/old.pdf", bytes: 5_000); try t.setModified("Downloads/old.pdf", daysAgo: 120)
    try t.file("Downloads/new.pdf", bytes: 5_000); try t.setModified("Downloads/new.pdf", daysAgo: 5)
    try t.file("Downloads/old.dmg", bytes: 5_000); try t.setModified("Downloads/old.dmg", daysAgo: 120)
    try t.file("Downloads/folder/x.bin", bytes: 5_000); try t.setModified("Downloads/folder", daysAgo: 200)
    let out = DownloadsRule().scan(RuleContext(home: t.url))
    #expect(Set(out.map { $0.url.lastPathComponent }) == ["old.pdf", "folder"])
    #expect(out.allSatisfy { $0.category == .downloads && $0.impact.userData && !$0.impact.preselectable })
}

@Test func documentsListsOnlyBigAndOldFiles() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Documents/bigold.mov", bytes: 60_000); try t.setModified("Documents/bigold.mov", daysAgo: 400)
    try t.file("Documents/bignew.mov", bytes: 60_000); try t.setModified("Documents/bignew.mov", daysAgo: 10)
    try t.file("Documents/smallold.txt", bytes: 1_000); try t.setModified("Documents/smallold.txt", daysAgo: 400)
    let out = DocumentsRule(minBytes: 50_000).scan(RuleContext(home: t.url))
    #expect(out.map { $0.url.lastPathComponent } == ["bigold.mov"])
    #expect(out[0].category == .documents && out[0].impact.userData && !out[0].impact.preselectable)
}

@Test func engineCoversNewCategories() {
    #expect(RuleEngine.standard().covers(.downloads))
    #expect(RuleEngine.standard().covers(.documents))
}

@Test func nestedFindingsAreNotCountedTwice() async throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Downloads/old/setup.dmg", bytes: 20_000); try t.setModified("Downloads/old", daysAgo: 200)
    let engine = RuleEngine(rules: [DownloadsRule(), InstallersRule()])
    let out = await engine.scan(RuleContext(home: t.url), gate: SafetyGate(home: t.url))
    #expect(out.map { $0.url.lastPathComponent } == ["old"])
}
