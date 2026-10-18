import Foundation

public struct DiskUsage: Equatable, Sendable {
    public let total: Int64
    public let available: Int64

    public init(total: Int64, available: Int64) { self.total = total; self.available = available }

    public var used: Int64 { total - available }
    public var percent: Int { total > 0 ? Int((Double(used) / Double(total) * 100).rounded()) : 0 }
}

public enum DiskMonitor {
    /// Sonraki sürümlerde ayarlardan değiştirilebilecek.
    public static let defaultThreshold = 0.70

    /// Finder ile aynı "boş alan" tanımı (temizlenebilir alan boş sayılır).
    public static func current(at url: URL = URL(fileURLWithPath: "/")) throws -> DiskUsage {
        let v = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DiskUsage(total: Int64(v.volumeTotalCapacity ?? 0), available: v.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    public static func shouldWarn(_ usage: DiskUsage, threshold: Double = defaultThreshold) -> Bool {
        usage.total > 0 && Double(usage.used) / Double(usage.total) >= threshold
    }

    public static func message(for usage: DiskUsage) -> String {
        "Diskin %\(usage.percent) dolu. Breezy'ye ne dersin?"
    }
}
