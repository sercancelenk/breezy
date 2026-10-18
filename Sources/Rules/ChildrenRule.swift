import Foundation
import CleanerCore
import DiskScanner

struct ChildrenRule: Rule {
    let category: FindingCategory
    let relativeDirectory: String
    let excluding: Set<String>
    let confidence: Confidence
    let reason: String

    func scan(_ context: RuleContext) -> [Finding] {
        let dir = context.home.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return kids.compactMap { url in
            guard !Task.isCancelled, !excluding.contains(url.lastPathComponent) else { return nil }
            let size = DirectorySizer.size(of: url)
            guard size > 0 else { return nil }
            return Finding(url: url, size: size, category: category, confidence: confidence,
                           reason: reason, lastModified: DirectorySizer.modificationDate(of: url))
        }
    }
}
