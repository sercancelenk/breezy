import Foundation
import Cleaning

public actor StubTrasher: Trasher {
    public struct Boom: Error, LocalizedError {
        public var errorDescription: String? { "izin reddedildi" }
    }

    public private(set) var trashed: [URL] = []
    private let failing: Set<String>

    public init(failing: Set<String> = []) { self.failing = failing }

    public func trash(_ url: URL) async throws {
        if failing.contains(url.path) { throw Boom() }
        trashed.append(url)
    }
}
