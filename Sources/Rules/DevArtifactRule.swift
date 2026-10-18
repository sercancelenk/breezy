import Foundation
import CleanerCore
import DiskScanner

struct DevArtifactRule: Rule {
    struct Pattern {
        let dirName: String
        let manifests: [String]
        let marker: String?
        let reason: String
        let impact: Impact

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
              reason: "npm bağımlılıkları; `npm install` ile geri gelir",
              impact: Impact(regeneration: .manual, risk: .low, note: "Geri getirmek için `npm install` gerekir; internet yoksa veya paketin sürümü yayından kalktıysa proje çalışmaz.")),
        .init(dirName: "target", manifests: ["pom.xml", "Cargo.toml"], marker: nil,
              reason: "Maven/Cargo derleme çıktısı; yeniden üretilir",
              impact: Impact(regeneration: .manual, risk: .low, note: "Bir sonraki `mvn package` / `cargo build` çıktıyı yeniden üretir; ilk derleme uzun sürer.")),
        .init(dirName: "build", manifests: gradle, marker: nil, reason: "Gradle derleme çıktısı; yeniden üretilir",
              impact: Impact(regeneration: .manual, risk: .low, note: "Bir sonraki Gradle derlemesi çıktıyı yeniden üretir; ilk derleme uzun sürer.")),
        .init(dirName: ".gradle", manifests: gradle, marker: nil, reason: "Gradle proje önbelleği",
              impact: Impact(regeneration: .automatic, risk: .low, note: "Gradle bir sonraki çalışmada önbelleği yeniden oluşturur.")),
        .init(dirName: "venv", manifests: python, marker: "pyvenv.cfg", reason: "Python sanal ortamı; yeniden kurulur",
              impact: Impact(regeneration: .manual, risk: .medium, note: "Paket sürümleri sabitlenmediyse (requirements kilidi yoksa) aynı ortam birebir geri gelmeyebilir; yeniden kurulum internet gerektirir.")),
        .init(dirName: ".venv", manifests: python, marker: "pyvenv.cfg", reason: "Python sanal ortamı; yeniden kurulur",
              impact: Impact(regeneration: .manual, risk: .medium, note: "Paket sürümleri sabitlenmediyse (requirements kilidi yoksa) aynı ortam birebir geri gelmeyebilir; yeniden kurulum internet gerektirir.")),
        .init(dirName: "__pycache__", manifests: python, marker: nil, reason: "Python bytecode önbelleği",
              impact: Impact(regeneration: .automatic, risk: .minimal, note: "Python çalışırken bytecode dosyalarını yeniden üretir.")),
    ]
    static let skipNames: Set<String> = [".git", ".hg", ".svn", "Library", ".Trash", "Applications",
                                          ".idea", ".vscode", "site-packages"]

    var categories: Set<FindingCategory> { [.devArtifact] }

    func scan(_ context: RuleContext) -> [Finding] {
        let fm = FileManager.default
        // Bir kök altındaki iki seviyeyi ayrı iş birimi yap: tek büyük proje klasörü taramayı geciktirmesin.
        var units: [(url: URL, shallow: Bool)] = []
        func dirs(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        }
        for root in context.scanRoots {
            for child in dirs(root) {
                let name = child.lastPathComponent
                if Self.skipNames.contains(name) || name.hasSuffix(".app") || Self.patterns.contains(where: { $0.dirName == name }) {
                    units.append((child, false)); continue
                }
                units.append((child, true))
                units += dirs(child).map { ($0, false) }
            }
        }
        return Parallel.map(units) { unit, cancel in walk(unit.url, context, cancel, shallow: unit.shallow) }
    }

    private func walk(_ start: URL, _ context: RuleContext, _ cancel: CancelFlag, shallow: Bool) -> [Finding] {
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(start.path), nil]
        defer { free(argv[0]) }
        // Sembolik bağlantılar FTS_SL olarak gelir ve takip edilmez.
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return [] }
        defer { fts_close(fts) }
        var out: [Finding] = []
        var n = 0
        while let ent = fts_read(fts) {
            n += 1
            if n % 256 == 0, cancel.isSet { break }
            guard Int32(ent.pointee.fts_info) == FTS_D else { continue }
            let url = URL(fileURLWithPath: String(cString: ent.pointee.fts_path), isDirectory: true)
            let name = url.lastPathComponent
            if Self.skipNames.contains(name) || name.hasSuffix(".app")
                || context.excludedPaths.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) {
                fts_set(fts, ent, FTS_SKIP); continue
            }
            guard let p = Self.patterns.first(where: { $0.dirName == name }), p.matches(url) else {
                if shallow { break }
                continue
            }
            fts_set(fts, ent, FTS_SKIP)
            let size = DirectorySizer.size(of: url, cancel: cancel)
            guard size > 0 else { continue }
            out.append(finding(url, size: size, pattern: p, now: context.now))
        }
        return out
    }

    private func finding(_ url: URL, size: Int64, pattern: Pattern, now: Date) -> Finding {
        let mtime = DirectorySizer.modificationDate(of: url)
        let ageDays = now.timeIntervalSince(mtime ?? .distantPast) / 86_400
        let confidence: Confidence = ageDays < 7 ? .low : ageDays < 30 ? .medium : .high
        let reason = ageDays < 7 ? pattern.reason + " (son 7 günde değişti)" : pattern.reason
        return Finding(url: url, size: size, category: .devArtifact, confidence: confidence,
                       reason: reason, lastModified: mtime, impact: pattern.impact)
    }
}
