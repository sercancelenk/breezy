import Foundation
import CleanerCore
import DiskScanner

struct FixedPathsRule: Rule {
    struct Entry {
        let relativePath: String
        let reason: String
        let confidence: Confidence
        var impact: Impact = .routine
    }

    let category: FindingCategory
    let entries: [Entry]

    func scan(_ context: RuleContext) -> [Finding] {
        entries.compactMap { e in
            guard !Task.isCancelled else { return nil }
            let url = context.home.appendingPathComponent(e.relativePath, isDirectory: true)
            let size = DirectorySizer.size(of: url)
            guard size > 0 else { return nil }
            return Finding(url: url, size: size, category: category, confidence: e.confidence,
                           reason: e.reason, lastModified: DirectorySizer.modificationDate(of: url), impact: e.impact)
        }
    }
}
