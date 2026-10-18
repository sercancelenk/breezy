import Foundation
import Testing
import TestSupport
@testable import DiskScanner

@Test func sumsAllocatedSizeOfNestedFiles() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("d/a.bin", bytes: 10_000)
    try t.file("d/sub/b.bin", bytes: 5_000)
    #expect(DirectorySizer.size(of: t.url.appendingPathComponent("d")) >= 15_000)
}

@Test func missingAndEmptyAreZero() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.dir("empty")
    #expect(DirectorySizer.size(of: t.url.appendingPathComponent("empty")) == 0)
    #expect(DirectorySizer.size(of: t.url.appendingPathComponent("nope")) == 0)
}

@Test func singleFileUsesItsOwnSize() throws {
    let t = try TempDir(); defer { t.remove() }
    let f = try t.file("one.bin", bytes: 9_000)
    #expect(DirectorySizer.size(of: f) >= 9_000)
}
