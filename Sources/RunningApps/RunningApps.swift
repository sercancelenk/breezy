import AppKit
import Darwin

public struct RunningApp: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let bundleID: String?
    public let memoryBytes: Int64
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, bundleID: String?, memoryBytes: Int64) {
        self.pid = pid; self.name = name; self.bundleID = bundleID; self.memoryBytes = memoryBytes
    }
}

public enum RunningApps {
    /// Kapatılması anlamsız ya da zararlı olan sistem uygulamaları.
    static let protectedBundleIDs: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow"]

    public static func isProtected(bundleID: String?) -> Bool {
        bundleID.map(protectedBundleIDs.contains) ?? false
    }

    public static func top(_ apps: [RunningApp], limit: Int) -> [RunningApp] {
        Array(apps.filter { !isProtected(bundleID: $0.bundleID) }
            .sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
    }

    /// Dock'ta görünen (normal) uygulamalar; Breezy'nin kendisi hariç.
    public static func list(limit: Int = 30) -> [RunningApp] {
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
            .map { RunningApp(pid: $0.processIdentifier, name: $0.localizedName ?? "?",
                              bundleID: $0.bundleIdentifier, memoryBytes: footprint(pid: $0.processIdentifier)) }
        return top(apps, limit: limit)
    }

    /// `force` = false: uygulamaya nazikçe kapanmasını söyler (kaydetme sorabilir). true: anında sonlandırır.
    @discardableResult
    public static func quit(pid: Int32, force: Bool) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !isProtected(bundleID: app.bundleIdentifier) else { return false }
        return force ? app.forceTerminate() : app.terminate()
    }

    private static func footprint(pid: Int32) -> Int64 {
        var info = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return ok == 0 ? Int64(info.ri_phys_footprint) : 0
    }
}
