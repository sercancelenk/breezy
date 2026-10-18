import Foundation
import CleanerCore
import DiskScanner

/// Downloads'ta 90 günden eski üst düzey öğeler. Kurulum dosyaları `InstallersRule`'a aittir.
struct DownloadsRule: Rule {
    var categories: Set<FindingCategory> { [.downloads] }

    func scan(_ context: RuleContext) -> [Finding] {
        let dir = context.home.appendingPathComponent("Downloads", isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        var out: [Finding] = []
        for url in items {
            if Task.isCancelled { break }
            guard !InstallersRule.extensions.contains(url.pathExtension.lowercased()),
                  let mtime = DirectorySizer.modificationDate(of: url),
                  context.now.timeIntervalSince(mtime) / 86_400 > 90 else { continue }
            let size = DirectorySizer.size(of: url)
            guard size > 0 else { continue }
            out.append(Finding(url: url, size: size, category: .downloads, confidence: .low,
                               reason: "90 günden uzun süredir Downloads'ta duruyor", lastModified: mtime,
                               impact: Impact(regeneration: .manual, risk: .medium,
                                              note: "Kişisel dosyan olabilir; kaynağından yeniden indirilebiliyorsa sorun olmaz.",
                                              userData: true)))
        }
        return out
    }
}

/// Documents'ta büyük (varsayılan 100 MB+) ve 1 yıldır değişmemiş dosyalar.
struct DocumentsRule: Rule {
    var minBytes: Int64 = 100 * 1_048_576

    var categories: Set<FindingCategory> { [.documents] }

    func scan(_ context: RuleContext) -> [Finding] {
        let dir = context.home.appendingPathComponent("Documents", isDirectory: true)
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [Finding] = []
        for case let url as URL in e {
            if Task.isCancelled { break }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let mtime = DirectorySizer.modificationDate(of: url),
                  context.now.timeIntervalSince(mtime) / 86_400 > 365 else { continue }
            let size = DirectorySizer.size(of: url)
            guard size >= minBytes else { continue }
            out.append(Finding(url: url, size: size, category: .documents, confidence: .low,
                               reason: "Büyük dosya; 1 yıldan uzun süredir değişmemiş", lastModified: mtime,
                               impact: Impact(regeneration: .never, risk: .high,
                                              note: "Kişisel belge olabilir; başka bir yerde yedeği yoksa geri gelmez. iCloud ile eşitleniyorsa tüm cihazlardan silinir.",
                                              userData: true)))
        }
        return out
    }
}
