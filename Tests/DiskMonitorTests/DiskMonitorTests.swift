import Foundation
import Testing
@testable import DiskMonitor

@Test func usageFractionAndPercent() {
    let u = DiskUsage(total: 1000, available: 250)
    #expect(u.used == 750)
    #expect(u.percent == 75)
    #expect(DiskUsage(total: 0, available: 0).percent == 0) // sıfıra bölme yok
}

@Test func warnsOnlyAtOrAboveThreshold() {
    #expect(DiskMonitor.shouldWarn(DiskUsage(total: 100, available: 31)) == false) // %69
    #expect(DiskMonitor.shouldWarn(DiskUsage(total: 100, available: 30)) == true)  // %70
    #expect(DiskMonitor.shouldWarn(DiskUsage(total: 100, available: 10), threshold: 0.95) == false)
}

@Test func messageMentionsPercent() {
    #expect(DiskMonitor.message(for: DiskUsage(total: 100, available: 16)).contains("%84"))
}

@Test func readsRealVolume() throws {
    let u = try DiskMonitor.current()
    #expect(u.total > 0 && u.available >= 0 && u.available <= u.total)
}
