import Foundation

public struct SafetyGate: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    private static let exactProtected: Set<[String]> = [
        ["Desktop"], ["Documents"], ["Downloads"], ["Pictures"], ["Movies"], ["Music"],
        ["Library"], ["Library", "Caches"], ["Library", "Logs"], ["Library", "Application Support"],
        [".Trash"],
    ]
    private static let subtreeProtected: [[String]] = [
        [".ssh"], [".gnupg"], ["Library", "Keychains"], ["Library", "Mobile Documents"], ["Library", "Messages"],
    ]

    public func isAllowed(_ url: URL) -> Bool {
        let h = home.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let p = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard p.count > h.count, Array(p.prefix(h.count)) == h else { return false }
        let rel = Array(p.dropFirst(h.count))
        if Self.exactProtected.contains(rel) { return false }
        for s in Self.subtreeProtected where rel.starts(with: s) { return false }
        return true
    }
}
