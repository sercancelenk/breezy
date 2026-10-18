import Foundation

public enum DirectorySizer {
    /// POSIX `fts` ile ayrılmış (allocated) boyut; sembolik bağlantılar takip edilmez.
    public static func size(of url: URL, cancel: CancelFlag? = nil) -> Int64 {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return 0 }
        let kind = st.st_mode & S_IFMT
        if kind == S_IFREG { return Int64(st.st_blocks) * 512 }
        guard kind == S_IFDIR else { return 0 }
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(url.path), nil]
        defer { free(argv[0]) }
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return 0 }
        defer { fts_close(fts) }
        var total: Int64 = 0
        var n = 0
        while let ent = fts_read(fts) {
            n += 1
            if n % 512 == 0, Task.isCancelled || cancel?.isSet == true { break }
            if Int32(ent.pointee.fts_info) == FTS_F, let s = ent.pointee.fts_statp {
                total += Int64(s.pointee.st_blocks) * 512
            }
        }
        return total
    }

    public static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
