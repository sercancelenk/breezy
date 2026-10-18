import Foundation
import Testing
import TestSupport
@testable import Safety

@Test func rejectsHomeAndProtectedRoots() throws {
    let t = try TempDir(); defer { t.remove() }
    let gate = SafetyGate(home: t.url)
    #expect(!gate.isAllowed(t.url))
    for d in ["Documents", "Desktop", "Downloads", "Library", "Library/Caches", "Library/Logs",
              "Library/Application Support", ".Trash"] {
        #expect(!gate.isAllowed(t.url.appendingPathComponent(d)), "\(d)")
    }
}

@Test func allowsChildrenOfCachesAndProjectArtifacts() throws {
    let t = try TempDir(); defer { t.remove() }
    let gate = SafetyGate(home: t.url)
    #expect(gate.isAllowed(t.url.appendingPathComponent("Library/Caches/com.foo")))
    #expect(gate.isAllowed(t.url.appendingPathComponent("Documents/proj/node_modules")))
}

@Test func rejectsOutsideHomeAndProtectedSubtrees() throws {
    let t = try TempDir(); defer { t.remove() }
    let gate = SafetyGate(home: t.url)
    #expect(!gate.isAllowed(URL(fileURLWithPath: "/System/Library")))
    #expect(!gate.isAllowed(URL(fileURLWithPath: "/usr/bin")))
    #expect(!gate.isAllowed(t.url.appendingPathComponent(".ssh/id_rsa")))
    #expect(!gate.isAllowed(t.url.appendingPathComponent("Library/Keychains/login.keychain-db")))
}

@Test func rejectsSymlinkEscapeAndDotDot() throws {
    let t = try TempDir(); defer { t.remove() }
    let gate = SafetyGate(home: t.url)
    let link = t.url.appendingPathComponent("Library/Caches/evil")
    try t.dir("Library/Caches")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/usr"))
    #expect(!gate.isAllowed(link))
    let dotdot = URL(fileURLWithPath: t.url.path + "/Library/Caches/../../../../../../../../etc")
    #expect(!gate.isAllowed(dotdot))
}
