import Foundation
import ServiceManagement
import UserNotifications

public enum DiskAlert {
    public static let checkArgument = "--check-disk"
    static let agentPlist = "com.sercancelenk.breezy.diskcheck.plist"

    /// `swift run` gibi .app dışı çalıştırmalarda UserNotifications/SMAppService çöker.
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Uygulama açılışında: bildirim izni ister, günlük kontrol ajanını kaydeder.
    public static func setUp() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let agent = SMAppService.agent(plistName: agentPlist)
        if agent.status != .enabled { try? agent.register() }
    }

    /// LaunchAgent çağrısı: eşik aşıldıysa bildirim gönderir.
    public static func checkAndNotify() async {
        guard isBundled, let usage = try? DiskMonitor.current(), DiskMonitor.shouldWarn(usage) else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Breezy"
        content.body = DiskMonitor.message(for: usage)
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "disk-usage", content: content, trigger: nil))
    }
}
