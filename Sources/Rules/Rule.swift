import Foundation
import CleanerCore

public struct RuleContext: Sendable {
    public let home: URL
    public let scanRoots: [URL]
    public let excludedPaths: Set<String>
    public let now: Date

    public init(home: URL, scanRoots: [URL] = [], excludedPaths: Set<String> = [], now: Date = Date()) {
        self.home = home
        self.scanRoots = scanRoots
        self.excludedPaths = excludedPaths
        self.now = now
    }
}

public protocol Rule: Sendable {
    func scan(_ context: RuleContext) -> [Finding]
}
