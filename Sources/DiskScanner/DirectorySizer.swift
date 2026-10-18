import Foundation

public enum DirectorySizer {
    public static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return fileSize(url) }
        guard let e = fm.enumerator(at: url,
                                    includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                                    options: [],
                                    errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            if Task.isCancelled { break }
            total += fileSize(u)
        }
        return total
    }

    public static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func fileSize(_ u: URL) -> Int64 {
        guard let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
              v.isRegularFile == true else { return 0 }
        return Int64(v.totalFileAllocatedSize ?? 0)
    }
}
