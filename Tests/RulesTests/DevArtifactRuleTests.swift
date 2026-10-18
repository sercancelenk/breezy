import Foundation
import Testing
import TestSupport
import CleanerCore
@testable import Rules

private func scan(_ t: TempDir, root: String = "w") -> [Finding] {
    DevArtifactRule().scan(RuleContext(home: t.url, scanRoots: [t.url.appendingPathComponent(root)]))
}

@Test func nodeModulesNeedsPackageJsonAndSkipsNested() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("w/p1/package.json")
    try t.file("w/p1/node_modules/dep/index.js", bytes: 5_000)
    try t.file("w/p1/node_modules/dep/node_modules/inner/i.js", bytes: 5_000)
    try t.file("w/p2/node_modules/dep/index.js", bytes: 5_000) // manifest yok
    try t.setModified("w/p1/node_modules", daysAgo: 60)
    let out = scan(t)
    #expect(out.count == 1)
    #expect(out[0].url.path.hasSuffix("w/p1/node_modules"))
    #expect(out[0].confidence == .high)
}

@Test func mavenGradleAndPythonArtifacts() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("w/m/pom.xml"); try t.file("w/m/target/classes/A.class", bytes: 5_000)
    try t.file("w/g/build.gradle"); try t.file("w/g/build/out.bin", bytes: 5_000)
    try t.file("w/g/.gradle/c.bin", bytes: 5_000)
    try t.file("w/py/requirements.txt")
    try t.file("w/py/venv/pyvenv.cfg"); try t.file("w/py/venv/lib/x.py", bytes: 5_000)
    try t.file("w/py2/requirements.txt"); try t.file("w/py2/venv/notes.txt", bytes: 5_000) // pyvenv.cfg yok
    let names = Set(scan(t).map { $0.url.pathComponents.suffix(2).joined(separator: "/") })
    #expect(names == ["m/target", "g/build", "g/.gradle", "py/venv"])
}

@Test func recentlyModifiedIsLowConfidence() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("w/p/package.json")
    try t.file("w/p/node_modules/d/i.js", bytes: 5_000)
    try t.setModified("w/p/node_modules", daysAgo: 2)
    #expect(scan(t).first?.confidence == .low)
    try t.setModified("w/p/node_modules", daysAgo: 15)
    #expect(scan(t).first?.confidence == .medium)
}

@Test func symlinkNamedNodeModulesIsIgnored() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("w/p/package.json")
    try t.dir("outside/data"); try t.file("outside/data/big.bin", bytes: 5_000)
    try FileManager.default.createSymbolicLink(
        at: t.url.appendingPathComponent("w/p/node_modules"),
        withDestinationURL: t.url.appendingPathComponent("outside/data"))
    #expect(scan(t).isEmpty)
}
