import Foundation
import Testing
import TestSupport
import CleanerCore
@testable import Rules

@Test func iosBackupsAreListedAsNonRegenerableBackups() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Library/Application Support/MobileSync/Backup/uuid1/Manifest.db", bytes: 20_000)
    let out = RuleEngine.backupRule.scan(RuleContext(home: t.url))
    #expect(out.count == 1 && out[0].category == .backup)
    #expect(out[0].impact.regeneration == .never && !out[0].impact.preselectable)
}

@Test func downloadsInstallersOnlyByExtensionAndNeverPreselected() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Downloads/app.dmg", bytes: 20_000)
    try t.file("Downloads/tool.pkg", bytes: 20_000)
    try t.file("Downloads/notes.pdf", bytes: 20_000)
    try t.file("Downloads/sub/disk.iso", bytes: 20_000)
    let out = InstallersRule().scan(RuleContext(home: t.url))
    #expect(Set(out.map { $0.url.lastPathComponent }) == ["app.dmg", "tool.pkg", "disk.iso"])
    #expect(out.allSatisfy { $0.category == .installers && $0.confidence != .high })
}
