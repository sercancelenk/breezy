import Foundation
import CleanerCore

public struct RuleContext: Sendable {
    public let home: URL
    public let scanRoots: [URL]
    public let excludedPaths: Set<String>
    public let now: Date
    /// Bayt; 0 = büyük öğe taraması kapalı.
    public let largeThreshold: Int64

    public init(home: URL, scanRoots: [URL] = [], excludedPaths: Set<String> = [], now: Date = Date(),
                largeThreshold: Int64 = 0) {
        self.home = home
        self.scanRoots = scanRoots
        self.excludedPaths = excludedPaths
        self.now = now
        self.largeThreshold = largeThreshold
    }
}

public protocol Rule: Sendable {
    /// Bu kuralın üretebileceği kategoriler; kategori bazlı taramada ilgisiz kurallar çalıştırılmaz.
    var categories: Set<FindingCategory> { get }
    func scan(_ context: RuleContext) -> [Finding]
}

public extension Rule {
    var categories: Set<FindingCategory> { Set(FindingCategory.allCases) }
}
