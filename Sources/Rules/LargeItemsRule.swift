import Foundation
import CleanerCore
import DiskScanner

/// Eşiğin üzerindeki en iç (leaf-most) klasörleri ve büyük dosyaları listeler. Yalnızca yol ve boyuta bakar.
struct LargeItemsRule: Rule {
    static let skipNames: Set<String> = [".Trash", "node_modules"]
    /// İçine bir seviye daha bakılan sarmalayıcılar; kendi çocukları ayrı iş birimi olur.
    static let transparent: Set<String> = [
        "Library", "Library/Application Support", "Library/Containers", "Library/Group Containers",
    ]
    /// Paket (bundle) uzantıları: içi parçalanmadan tek öğe sayılır.
    static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "sparsebundle", "vmwarevm", "pvm", "framework", "bundle", "plugin", "xcarchive",
    ]
    static let skipRelative: Set<String> = ["Library/Mobile Documents", "Library/Messages"]
    static let userFolders: Set<String> = ["Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures"]

    private struct Frame {
        let path: String
        var size: Int64 = 0
        var big = false
    }

    var categories: Set<FindingCategory> { [.large] }

    func scan(_ context: RuleContext) -> [Finding] {
        let t = context.largeThreshold
        guard t > 0 else { return [] }
        let home = context.home
        var units: [URL] = []
        var out: [Finding] = []
        func visit(_ dir: URL, rel: String) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names {
                let k = dir.appendingPathComponent(name)
                let childRel = rel.isEmpty ? name : rel + "/" + name
                var st = stat()
                guard lstat(k.path, &st) == 0 else { continue }
                switch st.st_mode & S_IFMT {
                case S_IFREG:
                    let size = Int64(st.st_blocks) * 512
                    if size >= t { out.append(Self.finding(k, size: size, home: home, isFile: true)) }
                case S_IFDIR:
                    if Self.skipNames.contains(name) || Self.skipRelative.contains(childRel) { continue }
                    if Self.transparent.contains(childRel) { visit(k, rel: childRel) } else { units.append(k) }
                default: continue
                }
            }
        }
        visit(home, rel: "")
        // Kullanıcının günlük klasörleri önce, Library en sona.
        units.sort { Self.priority($0, home) < Self.priority($1, home) }
        out += Parallel.map(units) { unit, cancel in walk(unit, t, home, cancel) }
        return out
    }

    private static func priority(_ url: URL, _ home: URL) -> Int {
        let rel = url.path.hasPrefix(home.path + "/") ? String(url.path.dropFirst(home.path.count + 1)) : url.path
        if rel.hasPrefix("Library") { return 2 }
        return userFolders.contains(rel.split(separator: "/").first.map(String.init) ?? "") ? 0 : 1
    }

    private func walk(_ start: URL, _ t: Int64, _ home: URL, _ cancel: CancelFlag) -> [Finding] {
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(start.path), nil]
        defer { free(argv[0]) }
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return [] }
        defer { fts_close(fts) }
        var stack: [Frame] = []
        var out: [Finding] = []
        var n = 0
        while let ent = fts_read(fts) {
            n += 1
            if n % 256 == 0, cancel.isSet { break }
            let path = String(cString: ent.pointee.fts_path)
            switch Int32(ent.pointee.fts_info) {
            case FTS_D:
                let name = (path as NSString).lastPathComponent
                if Self.skipNames.contains(name) { fts_set(fts, ent, FTS_SKIP); continue }
                if Self.packageExtensions.contains((name as NSString).pathExtension.lowercased()) {
                    fts_set(fts, ent, FTS_SKIP)
                    let size = DirectorySizer.size(of: URL(fileURLWithPath: path), cancel: cancel)
                    if !stack.isEmpty {
                        stack[stack.count - 1].size += size
                        if size >= t { stack[stack.count - 1].big = true }
                    }
                    if size >= t {
                        out.append(Self.finding(URL(fileURLWithPath: path, isDirectory: true), size: size, home: home, isFile: false))
                    }
                    continue
                }
                stack.append(Frame(path: path))
            case FTS_F:
                guard let s = ent.pointee.fts_statp, !stack.isEmpty else { continue }
                let size = Int64(s.pointee.st_blocks) * 512
                stack[stack.count - 1].size += size
                if size >= t {
                    stack[stack.count - 1].big = true
                    out.append(Self.finding(URL(fileURLWithPath: path), size: size, home: home, isFile: true))
                }
            case FTS_DP:
                guard let fr = stack.popLast() else { continue }
                if !stack.isEmpty {
                    stack[stack.count - 1].size += fr.size
                    if fr.size >= t { stack[stack.count - 1].big = true }
                }
                if fr.size >= t, !fr.big {
                    out.append(Self.finding(URL(fileURLWithPath: fr.path, isDirectory: true), size: fr.size,
                                            home: home, isFile: false))
                }
            default: continue
            }
        }
        return out
    }

    private static func finding(_ url: URL, size: Int64, home: URL, isFile: Bool) -> Finding {
        let homePath = home.path
        let rel = url.path.hasPrefix(homePath + "/") ? String(url.path.dropFirst(homePath.count + 1)) : url.path
        let isUser = userFolders.contains(rel.split(separator: "/").first.map(String.init) ?? "")
        let note = isUser
            ? "Kendi dosyaların olabilir; silinirse geri gelmez (Çöp Kutusu'ndan geri alabilirsin)."
            : "Ne olduğunu kural bilmiyor; geri gelmeyebilir. Silmeden önce Finder'da kontrol et."
        return Finding(url: url, size: size, category: .large, confidence: .low,
                       reason: isFile ? "Büyük dosya" : "Büyük klasör",
                       lastModified: DirectorySizer.modificationDate(of: url),
                       impact: Impact(regeneration: .never, risk: .medium, note: note, isGeneric: true, userData: isUser))
    }
}
