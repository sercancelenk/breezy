import Foundation
import CleanerCore
import DiskScanner

struct DevArtifactRule: Rule {
    struct Pattern {
        let dirName: String
        let manifests: [String]
        let marker: String?
        let reason: String

        func matches(_ url: URL) -> Bool {
            let parent = url.deletingLastPathComponent()
            let fm = FileManager.default
            guard manifests.contains(where: { fm.fileExists(atPath: parent.appendingPathComponent($0).path) })
            else { return false }
            if let marker { return fm.fileExists(atPath: url.appendingPathComponent(marker).path) }
            return true
        }
    }

    static let python = ["requirements.txt", "pyproject.toml"]
    static let gradle = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
    static let patterns: [Pattern] = [
        .init(dirName: "node_modules", manifests: ["package.json"], marker: nil,
              reason: "npm bağımlılıkları; `npm install` ile geri gelir"),
        .init(dirName: "target", manifests: ["pom.xml", "Cargo.toml"], marker: nil,
              reason: "Maven/Cargo derleme çıktısı; yeniden üretilir"),
        .init(dirName: "build", manifests: gradle, marker: nil, reason: "Gradle derleme çıktısı; yeniden üretilir"),
        .init(dirName: ".gradle", manifests: gradle, marker: nil, reason: "Gradle proje önbelleği"),
        .init(dirName: "venv", manifests: python, marker: "pyvenv.cfg", reason: "Python sanal ortamı; yeniden kurulur"),
        .init(dirName: ".venv", manifests: python, marker: "pyvenv.cfg", reason: "Python sanal ortamı; yeniden kurulur"),
        .init(dirName: "__pycache__", manifests: python, marker: nil, reason: "Python bytecode önbelleği"),
    ]
    static let skipNames: Set<String> = [".git", "Library", ".Trash", "Applications"]

    func scan(_ context: RuleContext) -> [Finding] {
        var out: [Finding] = []
        let fm = FileManager.default
        for root in context.scanRoots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                        options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if Task.isCancelled { return out }
                // Symlink'ler isDirectory=false döner; böylece takip edilmezler.
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let name = url.lastPathComponent
                if Self.skipNames.contains(name) { e.skipDescendants(); continue }
                guard let p = Self.patterns.first(where: { $0.dirName == name }), p.matches(url) else { continue }
                e.skipDescendants()
                let size = DirectorySizer.size(of: url)
                guard size > 0 else { continue }
                out.append(finding(url, size: size, pattern: p, now: context.now))
            }
        }
        return out
    }

    private func finding(_ url: URL, size: Int64, pattern: Pattern, now: Date) -> Finding {
        let mtime = DirectorySizer.modificationDate(of: url)
        let ageDays = now.timeIntervalSince(mtime ?? .distantPast) / 86_400
        let confidence: Confidence = ageDays < 7 ? .low : ageDays < 30 ? .medium : .high
        let reason = ageDays < 7 ? pattern.reason + " (son 7 günde değişti)" : pattern.reason
        return Finding(url: url, size: size, category: .devArtifact, confidence: confidence,
                       reason: reason, lastModified: mtime)
    }
}
