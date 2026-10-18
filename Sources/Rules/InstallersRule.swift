import Foundation
import CleanerCore
import DiskScanner

/// Downloads içindeki kurulum/imaj dosyaları (dmg, pkg, iso, ipsw). Uzantıya bakar, içeriğe değil.
struct InstallersRule: Rule {
    static let extensions: Set<String> = ["dmg", "pkg", "iso", "ipsw"]

    func scan(_ context: RuleContext) -> [Finding] {
        let dir = context.home.appendingPathComponent("Downloads", isDirectory: true)
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [Finding] = []
        for case let url as URL in e {
            if Task.isCancelled { break }
            guard Self.extensions.contains(url.pathExtension.lowercased()) else { continue }
            let size = DirectorySizer.size(of: url)
            guard size > 0 else { continue }
            let mtime = DirectorySizer.modificationDate(of: url)
            let ageDays = context.now.timeIntervalSince(mtime ?? context.now) / 86_400
            out.append(Finding(url: url, size: size, category: .installers,
                               confidence: ageDays > 30 ? .medium : .low,
                               reason: "Kurulum/imaj dosyası; genelde bir kez kullanılır", lastModified: mtime,
                               impact: Impact(regeneration: .manual, risk: .low,
                                              note: "Kaynağından yeniden indirilebilir; uygulama zaten kurulduysa gerekmez.")))
        }
        return out
    }
}
