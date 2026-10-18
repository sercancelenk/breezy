import Foundation
import Testing
import TestSupport
@testable import Preferences

@Test func settingsRoundTripAndFallbacks() throws {
    let t = try TempDir(); defer { t.remove() }
    let store = SettingsStore(fileURL: t.url.appendingPathComponent("sub/settings.json"))
    #expect(store.load(home: t.url).aiEnabled == false) // dosya yok → varsayılan
    var data = SettingsData(scanRoots: ["/x"])
    let p = ProviderProfile.custom()
    data.profiles = [p]; data.activeProfileID = p.id; data.aiEnabled = true
    try store.save(data)
    #expect(store.load(home: t.url) == data)
    #expect(store.load(home: t.url).activeProfile?.id == p.id)
    try Data("garbage".utf8).write(to: store.fileURL)
    #expect(store.load(home: t.url).profiles.isEmpty) // bozuk dosya → varsayılan
}

@Test func defaultsKeepOnlyExistingRoots() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.dir("development"); try t.dir("Documents")
    let roots = SettingsData.defaults(home: t.url).scanRoots.map { URL(fileURLWithPath: $0).lastPathComponent }
    #expect(Set(roots) == ["development", "Documents"])
}

@Test func headersTextParsesAndFormats() {
    var p = ProviderProfile.openAICompatible()
    p.extraHeadersText = "X-Team: core \n bad line\nX-Env:prod: eu\n:novalue"
    #expect(p.extraHeaders == ["X-Team": "core", "X-Env": "prod: eu"])
    #expect(p.extraHeadersText == "X-Env: prod: eu\nX-Team: core")
}

@Test func inMemorySecretStore() throws {
    let s = InMemorySecretStore(); let id = UUID()
    #expect(s.secret(for: id) == nil)
    try s.setSecret("k", for: id); #expect(s.secret(for: id) == "k")
    try s.setSecret(nil, for: id); #expect(s.secret(for: id) == nil)
}

@Test func oldSettingsFileWithoutLargeThresholdStillLoads() throws {
    let t = try TempDir(); defer { t.remove() }
    let file = t.url.appendingPathComponent("s.json")
    try Data(#"{"profiles":[],"aiEnabled":true,"scanRoots":["/x"],"excludedPaths":[]}"#.utf8).write(to: file)
    let loaded = SettingsStore(fileURL: file).load(home: t.url)
    #expect(loaded.aiEnabled && loaded.scanRoots == ["/x"] && loaded.largeItemThresholdMB == 1024 && loaded.appearance == .system)
}

@Test func extraHeadersNeverStoreCredentials() {
    var p = ProviderProfile.custom()
    p.extraHeadersText = "X-Team: a\nAuthorization: Bearer sk-123\nx-api-key: k\nProxy-Authorization: z\nApi-Key: q"
    #expect(p.extraHeaders == ["X-Team": "a"])
}

@Test func appearanceChoiceRoundTrips() throws {
    let t = try TempDir(); defer { t.remove() }
    let store = SettingsStore(fileURL: t.url.appendingPathComponent("s.json"))
    var data = SettingsData()
    #expect(data.appearance == .system)
    data.appearance = .dark
    try store.save(data)
    #expect(store.load(home: t.url).appearance == .dark)
}
