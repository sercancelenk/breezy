import Foundation

public struct TempDir {
    public let url: URL

    public init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleaner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.resolvingSymlinksInPath()
    }

    @discardableResult
    public func dir(_ rel: String) throws -> URL {
        let u = url.appendingPathComponent(rel, isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    public func file(_ rel: String, bytes: Int = 10) throws -> URL {
        let u = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: u)
        return u
    }

    public func setModified(_ rel: String, daysAgo: Int) throws {
        let date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.appendingPathComponent(rel).path)
    }

    public func remove() { try? FileManager.default.removeItem(at: url) }
}
