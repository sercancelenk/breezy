import Foundation
import CleanerCore
import DiskScanner

struct ChildrenRule: Rule {
    let category: FindingCategory
    let relativeDirectory: String
    let excluding: Set<String>
    let confidence: Confidence
    let reason: String
    var impact: Impact = .routine
    var knownApps = false

    func scan(_ context: RuleContext) -> [Finding] {
        let dir = context.home.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return Parallel.map(kids) { url, cancel in
            guard !excluding.contains(url.lastPathComponent) else { return [] }
            let size = DirectorySizer.size(of: url, cancel: cancel)
            guard size > 0 else { return [] }
            return [Finding(url: url, size: size, category: category, confidence: confidence,
                            reason: reason, lastModified: DirectorySizer.modificationDate(of: url),
                            impact: (knownApps ? KnownApps.impact(forCacheNamed: url.lastPathComponent) : nil) ?? impact)]
        }
    }
}
