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

@Test func symlinksAreNotFollowedWhenSizing() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("big/x.bin", bytes: 100_000)
    try t.file("d/a.bin", bytes: 5_000)
    try FileManager.default.createSymbolicLink(at: t.url.appendingPathComponent("d/link"),
                                               withDestinationURL: t.url.appendingPathComponent("big"))
    let size = DirectorySizer.size(of: t.url.appendingPathComponent("d"))
    #expect(size >= 5_000 && size < 50_000)
}

@Test func parallelMapReturnsEveryItemsResults() {
    let out = Parallel.map(Array(1...50)) { n, _ in [n, n * 10] }
    #expect(out.sorted() == (1...50).flatMap { [$0, $0 * 10] }.sorted())
}

@Test func parallelMapStopsPickingWorkWhenCancelled() {
    let flag = CancelFlag()
    let out = Parallel.map(Array(1...200), cancel: flag) { n, f -> [Int] in
        if n == 1 { f.set() }
        return [n]
    }
    #expect(out.count < 200)
}
