import Foundation
import Testing
@testable import RunningApps

private func app(_ pid: Int32, _ mb: Int64, bundle: String? = nil) -> RunningApp {
    RunningApp(pid: pid, name: "App\(pid)", bundleID: bundle, memoryBytes: mb * 1_048_576)
}

@Test func sortsByMemoryDescendingAndLimits() {
    let top = RunningApps.top([app(1, 100), app(2, 900), app(3, 400)], limit: 2)
    #expect(top.map(\.pid) == [2, 3])
}

@Test func protectedAppsAreHidden() {
    let list = RunningApps.top([app(1, 500, bundle: "com.apple.finder"), app(2, 100, bundle: "com.foo.bar")], limit: 10)
    #expect(list.map(\.pid) == [2])
    #expect(RunningApps.isProtected(bundleID: "com.apple.finder"))
    #expect(!RunningApps.isProtected(bundleID: nil))
}

@Test func listsRealAppsWithoutSelf() {
    let apps = RunningApps.list()
    #expect(!apps.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
}
