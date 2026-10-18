# Cleaner App v1 (Smart Tarama) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native SwiftUI macOS uygulaması: kural motoruyla gereksiz dosyaları bulur, isteğe bağlı AI ile güven puanlarını iyileştirir, onayla Çöp Kutusu'na taşır.

**Architecture:** Tek Swift Package, tek sorumluluklu kütüphane modülleri (`CleanerCore`, `DiskScanner`, `Safety`, `Rules`, `Preferences`, `AI`, `Cleaning`, `AppModel`) ve ince bir SwiftUI executable (`CleanerApp`). Tüm silme `Safety` geçidinden ve `Cleaning` modülünden geçer. AI yalnızca kuralların bulduğu öğeleri yeniden puanlar, yeni yol üretemez.

**Tech Stack:** Swift 6.2 (strict concurrency, Swift 6 dil modu), SwiftUI + Observation, Swift Testing (`import Testing`), Security (Keychain), AppKit (`NSWorkspace.recycle`). Üçüncü parti bağımlılık yok.

**Spec:** `docs/superpowers/specs/2026-10-18-cleaner-app-design.md`

## Global Constraints

- Swift tools version `6.2`, platform `.macOS(.v26)` (derleyici `.v26`'yı tanımazsa `.v15` kullan ve bunu AGENTS.md'ye not et).
- Modül adları aynen: `CleanerCore`, `DiskScanner`, `Safety`, `Rules`, `Preferences`, `AI`, `Cleaning`, `AppModel`, `CleanerApp`; test yardımcıları `TestSupport`.
- Kalıcı silme yok; yalnızca `NSWorkspace.recycle`. Her silme `SafetyGate.isAllowed` kontrolünden geçer.
- AI'a yalnızca metadata gider (yol `~` ile kısaltılmış, boyut, kategori, yaş, kural güveni). Dosya içeriği asla.
- API key yalnızca Keychain'de (`KeychainSecretStore`); `settings.json`'a, loga, teste yazılmaz.
- AI kapalı veya hatalıysa kural-only sonuçlar korunur.
- Kullanıcıya görünen metinler Türkçe, kod tanımlayıcıları İngilizce.
- Testler Swift Testing ile; çalıştırma `swift test -q [--filter <Ad>]`, derleme `swift build -q`.
- Her commit mesajı şu satırla biter: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
- v1 dışı: manuel gezgin, Docker/Podman, öğrenme hafızası, Application Support analizi, kalıcı silme.

## Review Focus

Spec'in ima ettiği ama başka bir yerde test edilmeyen durumlar; her satırın testi sahibi task'ta var:

1. Taranan kökte `node_modules` adlı symlink dışarıyı gösteriyor, ya da ev içindeki symlink `/usr`'a kaçıyor: asla önerilmez ve silinmez (Task 3 ve Task 5).
2. Klasör adlarında boşluk ve Türkçe karakter (`Çalışma Klasörü`): AI prompt'unda bozulmadan görünür, ev dizini `~`'a çevrilir (Task 8).
3. Aynı yolu iki kural bulur veya kullanıcı hariç tuttu: tek kez listelenir, hariç tutulan listelenmez (Task 4).
4. AI çöp, kod bloğuna sarılı JSON, aralık dışı indeks döner ya da `low` öğeyi `high` yapmaya çalışır: ilk iki durumda hata/yok sayma, sonuncuda en fazla bir seviye yükselme (Task 8).
5. Seçimden sonra dosya kayboldu veya izin reddedildi, ya da tarama hiç sonuç döndürmedi: işlem çökmez, hata rapora yazılır, boş sonuç `ready` fazında kalır (Task 9 ve Task 10).

---

### Task 1: Paket iskeleti ve CleanerCore

**Files:**
- Create: `Package.swift`, `.gitignore`
- Create: `Sources/CleanerCore/Finding.swift`
- Create: `Sources/TestSupport/TempDir.swift`
- Test: `Tests/CleanerCoreTests/FindingTests.swift`

**Interfaces:**
- Produces: `enum Category`, `enum Confidence` (Comparable, `init?(label:)`, `title`), `struct Finding`, `TempDir` test yardımcısı.

- [ ] **Step 1: Repo ve paket iskeletini kur**

```bash
cd /Users/sercancelenk/development/workspaces/projects/cleaner-app
git init -q
printf '.build/\nbuild/\n.swiftpm/\nDerivedData/\n*.xcuserstate\n' > .gitignore
```

`Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanerApp",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CleanerCore"),
        .target(name: "TestSupport"),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore", "TestSupport"]),
    ]
)
```

`Sources/TestSupport/TempDir.swift`:

```swift
import Foundation

public struct TempDir {
    public let url: URL

    public init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleaner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.resolvingSymlinksInPath()
    }

    @discardableResult
    public func dir(_ rel: String) throws -> URL {
        let u = url.appendingPathComponent(rel, isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    public func file(_ rel: String, bytes: Int = 10) throws -> URL {
        let u = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: u)
        return u
    }

    public func setModified(_ rel: String, daysAgo: Int) throws {
        let date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.appendingPathComponent(rel).path)
    }

    public func remove() { try? FileManager.default.removeItem(at: url) }
}
```

- [ ] **Step 2: Başarısız testi yaz**

`Tests/CleanerCoreTests/FindingTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

@Test func findingIdIsPath() {
    let f = Finding(url: URL(fileURLWithPath: "/tmp/a"), size: 1, category: .cache,
                    confidence: .high, reason: "r", lastModified: nil)
    #expect(f.id == "/tmp/a")
}

@Test func confidenceOrderingAndLabels() {
    #expect(Confidence.low < .medium)
    #expect(Confidence.medium < .high)
    #expect(Confidence(label: " HIGH ") == .high)
    #expect(Confidence(label: "nope") == nil)
}
```

- [ ] **Step 3: Testin başarısız olduğunu doğrula**

Run: `swift test -q --filter CleanerCoreTests`
Expected: FAIL, `cannot find 'Finding' in scope` (veya hedefte kaynak yok hatası; `Finding.swift` yazılana kadar).

- [ ] **Step 4: Uygula**

`Sources/CleanerCore/Finding.swift`:

```swift
import Foundation

public enum Category: String, Sendable, Codable, CaseIterable {
    case cache, logs, homebrew, xcode, devArtifact

    public var title: String {
        switch self {
        case .cache: "Uygulama önbellekleri"
        case .logs: "Log dosyaları"
        case .homebrew: "Homebrew önbelleği"
        case .xcode: "Xcode"
        case .devArtifact: "Geliştirici artifact'ları"
        }
    }
}

public enum Confidence: Int, Sendable, Codable, Comparable {
    case low, medium, high

    public static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }

    public init?(label: String) {
        switch label.trimmingCharacters(in: .whitespaces).lowercased() {
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .low: "Düşük"
        case .medium: "Orta"
        case .high: "Yüksek"
        }
    }
}

public struct Finding: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let category: Category
    public var confidence: Confidence
    public var reason: String
    public let lastModified: Date?

    public init(url: URL, size: Int64, category: Category, confidence: Confidence,
                reason: String, lastModified: Date?) {
        self.url = url
        self.size = size
        self.category = category
        self.confidence = confidence
        self.reason = reason
        self.lastModified = lastModified
    }
}
```

- [ ] **Step 5: Testin geçtiğini doğrula**

Run: `swift test -q --filter CleanerCoreTests`
Expected: PASS. `.v26` hata verirse `Package.swift`'te `.v15` yap.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -q -m "chore: package scaffold and CleanerCore models

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: DiskScanner (dizin boyutu)

**Files:**
- Create: `Sources/DiskScanner/DirectorySizer.swift`
- Modify: `Package.swift` (targets'a ekle)
- Test: `Tests/DiskScannerTests/DirectorySizerTests.swift`

**Interfaces:**
- Consumes: yok.
- Produces: `DirectorySizer.size(of: URL) -> Int64` (ayrılmış disk boyutu, iptalde o ana kadarki toplam), `DirectorySizer.modificationDate(of: URL) -> Date?`.

- [ ] **Step 1: Package.swift'e ekle**

```swift
        .target(name: "DiskScanner", dependencies: ["CleanerCore"]),
        .testTarget(name: "DiskScannerTests", dependencies: ["DiskScanner", "TestSupport"]),
```

- [ ] **Step 2: Başarısız testi yaz**

```swift
import Foundation
import Testing
import TestSupport
@testable import DiskScanner

@Test func sumsAllocatedSizeOfNestedFiles() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("d/a.bin", bytes: 10_000)
    try t.file("d/sub/b.bin", bytes: 5_000)
    #expect(DirectorySizer.size(of: t.url.appendingPathComponent("d")) >= 15_000)
}

@Test func missingAndEmptyAreZero() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.dir("empty")
    #expect(DirectorySizer.size(of: t.url.appendingPathComponent("empty")) == 0)
    #expect(DirectorySizer.size(of: t.url.appendingPathComponent("nope")) == 0)
}

@Test func singleFileUsesItsOwnSize() throws {
    let t = try TempDir(); defer { t.remove() }
    let f = try t.file("one.bin", bytes: 9_000)
    #expect(DirectorySizer.size(of: f) >= 9_000)
}
```

- [ ] **Step 3: Başarısızlığı doğrula**

Run: `swift test -q --filter DiskScannerTests` → FAIL (`DirectorySizer` yok).

- [ ] **Step 4: Uygula**

```swift
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
```

- [ ] **Step 5: Geçtiğini doğrula** — `swift test -q --filter DiskScannerTests` → PASS.

- [ ] **Step 6: Commit** — `git add -A && git commit -q -m "feat: DirectorySizer"` (trailer'ı ekle).

---

### Task 3: Safety geçidi

**Files:**
- Create: `Sources/Safety/SafetyGate.swift`
- Modify: `Package.swift`
- Test: `Tests/SafetyTests/SafetyGateTests.swift`

**Interfaces:**
- Produces: `struct SafetyGate: Sendable { init(home: URL = home); func isAllowed(_ url: URL) -> Bool }`. Symlink'ler çözülür; ev dizini dışı, ev kökü, korunan kökler ve korunan alt ağaçlar reddedilir.

- [ ] **Step 1: Package.swift**

```swift
        .target(name: "Safety", dependencies: ["CleanerCore"]),
        .testTarget(name: "SafetyTests", dependencies: ["Safety", "TestSupport"]),
```

- [ ] **Step 2: Başarısız testi yaz**

```swift
import Foundation
import Testing
import TestSupport
@testable import Safety

@Test func rejectsHomeAndProtectedRoots() throws {
    let t = try TempDir(); defer { t.remove() }
    let gate = SafetyGate(home: t.url)
    #expect(!gate.isAllowed(t.url))
    for d in ["Documents", "Desktop", "Downloads", "Library", "Library/Caches", "Library/Logs",
              "Library/Application Support", ".Trash"] {
        #expect(!gate.isAllowed(t.url.appendingPathComponent(d)), "\(d)")
    }
}

@Test func allowsChildrenOfCachesAndProjectArtifacts() throws {
    let t = try TempDir(); defer { t.remove() }
    let gate = SafetyGate(home: t.url)
    #expect(gate.isAllowed(t.url.appendingPathComponent("Library/Caches/com.foo")))
    #expect(gate.isAllowed(t.url.appendingPathComponent("Documents/proj/node_modules")))
}

@Test func rejectsOutsideHomeAndProtectedSubtrees() throws {
    let t = try TempDir(); defer { t.remove() }
    let gate = SafetyGate(home: t.url)
    #expect(!gate.isAllowed(URL(fileURLWithPath: "/System/Library")))
    #expect(!gate.isAllowed(URL(fileURLWithPath: "/usr/bin")))
    #expect(!gate.isAllowed(t.url.appendingPathComponent(".ssh/id_rsa")))
    #expect(!gate.isAllowed(t.url.appendingPathComponent("Library/Keychains/login.keychain-db")))
}

@Test func rejectsSymlinkEscapeAndDotDot() throws {
    let t = try TempDir(); defer { t.remove() }
    let gate = SafetyGate(home: t.url)
    let link = t.url.appendingPathComponent("Library/Caches/evil")
    try t.dir("Library/Caches")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/usr"))
    #expect(!gate.isAllowed(link))
    let dotdot = URL(fileURLWithPath: t.url.path + "/Library/Caches/../../../../../../../../etc")
    #expect(!gate.isAllowed(dotdot))
}
```

- [ ] **Step 3:** `swift test -q --filter SafetyTests` → FAIL.

- [ ] **Step 4: Uygula**

```swift
import Foundation

public struct SafetyGate: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    private static let exactProtected: Set<[String]> = [
        ["Desktop"], ["Documents"], ["Downloads"], ["Pictures"], ["Movies"], ["Music"],
        ["Library"], ["Library", "Caches"], ["Library", "Logs"], ["Library", "Application Support"],
        [".Trash"],
    ]
    private static let subtreeProtected: [[String]] = [
        [".ssh"], [".gnupg"], ["Library", "Keychains"], ["Library", "Mobile Documents"], ["Library", "Messages"],
    ]

    public func isAllowed(_ url: URL) -> Bool {
        let h = home.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let p = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard p.count > h.count, Array(p.prefix(h.count)) == h else { return false }
        let rel = Array(p.dropFirst(h.count))
        if Self.exactProtected.contains(rel) { return false }
        for s in Self.subtreeProtected where rel.starts(with: s) { return false }
        return true
    }
}
```

- [ ] **Step 5:** `swift test -q --filter SafetyTests` → PASS.

- [ ] **Step 6: Commit** — `feat: SafetyGate`.

---

### Task 4: Rules çekirdeği (ChildrenRule, FixedPathsRule, RuleEngine)

**Files:**
- Create: `Sources/Rules/Rule.swift`, `Sources/Rules/ChildrenRule.swift`, `Sources/Rules/FixedPathsRule.swift`, `Sources/Rules/RuleEngine.swift`
- Modify: `Package.swift`
- Test: `Tests/RulesTests/CoreRulesTests.swift`

**Interfaces:**
- Consumes: `DirectorySizer`, `SafetyGate`, `Finding`.
- Produces:
  - `struct RuleContext: Sendable { init(home: URL, scanRoots: [URL] = [], excludedPaths: Set<String> = [], now: Date = Date()) }`
  - `protocol Rule: Sendable { func scan(_ context: RuleContext) -> [Finding] }` (senkron, iptal için `Task.isCancelled` kontrol eder)
  - `RuleEngine(rules:)`, `RuleEngine.standard()`, `func scan(_ context: RuleContext, gate: SafetyGate) async -> [Finding]` (güvenli, hariç tutulmamış, tekil, boyuta göre azalan).

- [ ] **Step 1: Package.swift**

```swift
        .target(name: "Rules", dependencies: ["CleanerCore", "DiskScanner", "Safety"]),
        .testTarget(name: "RulesTests", dependencies: ["Rules", "TestSupport"]),
```

- [ ] **Step 2: Başarısız testi yaz**

```swift
import Foundation
import Testing
import TestSupport
import CleanerCore
import Safety
@testable import Rules

private struct FixedRule: Rule {
    let findings: [Finding]
    func scan(_ context: RuleContext) -> [Finding] { findings }
}

@Test func childrenRuleListsNonEmptyChildrenExceptExcluded() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Library/Caches/com.a/x.bin", bytes: 10_000)
    try t.file("Library/Caches/Homebrew/y.bin", bytes: 10_000)
    try t.dir("Library/Caches/empty")
    let rule = ChildrenRule(category: .cache, relativeDirectory: "Library/Caches",
                            excluding: ["Homebrew"], confidence: .high, reason: "r")
    let out = rule.scan(RuleContext(home: t.url))
    #expect(out.map { $0.url.lastPathComponent } == ["com.a"])
    #expect(out[0].size >= 10_000)
}

@Test func fixedPathsRuleSkipsMissingAndEmpty() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("Library/Developer/Xcode/DerivedData/p/o.bin", bytes: 8_000)
    try t.dir("Library/Developer/CoreSimulator/Caches")
    let rule = FixedPathsRule(category: .xcode, entries: [
        .init(relativePath: "Library/Developer/Xcode/DerivedData", reason: "d", confidence: .high),
        .init(relativePath: "Library/Developer/CoreSimulator/Caches", reason: "c", confidence: .high),
        .init(relativePath: "Library/Missing", reason: "m", confidence: .low),
    ])
    let out = rule.scan(RuleContext(home: t.url))
    #expect(out.map { $0.url.lastPathComponent } == ["DerivedData"])
}

@Test func engineFiltersUnsafeExcludedAndDuplicatesAndSortsBySize() async throws {
    let t = try TempDir(); defer { t.remove() }
    func f(_ rel: String, _ size: Int64) -> Finding {
        Finding(url: t.url.appendingPathComponent(rel), size: size, category: .cache,
                confidence: .high, reason: "r", lastModified: nil)
    }
    let outside = Finding(url: URL(fileURLWithPath: "/usr/lib"), size: 99, category: .cache,
                          confidence: .high, reason: "r", lastModified: nil)
    let rules: [any Rule] = [
        FixedRule(findings: [f("Library/Caches/a", 10), f("Library/Caches/b", 30), outside]),
        FixedRule(findings: [f("Library/Caches/a", 10), f("Library/Caches/c", 20)]),
    ]
    let ctx = RuleContext(home: t.url,
                          excludedPaths: [t.url.appendingPathComponent("Library/Caches/c").path])
    let out = await RuleEngine(rules: rules).scan(ctx, gate: SafetyGate(home: t.url))
    #expect(out.map(\.size) == [30, 10])
}
```

- [ ] **Step 3:** `swift test -q --filter RulesTests` → FAIL.

- [ ] **Step 4: Uygula**

`Rule.swift`:

```swift
import Foundation
import CleanerCore

public struct RuleContext: Sendable {
    public let home: URL
    public let scanRoots: [URL]
    public let excludedPaths: Set<String>
    public let now: Date

    public init(home: URL, scanRoots: [URL] = [], excludedPaths: Set<String> = [], now: Date = Date()) {
        self.home = home
        self.scanRoots = scanRoots
        self.excludedPaths = excludedPaths
        self.now = now
    }
}

public protocol Rule: Sendable {
    func scan(_ context: RuleContext) -> [Finding]
}
```

`ChildrenRule.swift`:

```swift
import Foundation
import CleanerCore
import DiskScanner

struct ChildrenRule: Rule {
    let category: Category
    let relativeDirectory: String
    let excluding: Set<String>
    let confidence: Confidence
    let reason: String

    func scan(_ context: RuleContext) -> [Finding] {
        let dir = context.home.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return kids.compactMap { url in
            guard !Task.isCancelled, !excluding.contains(url.lastPathComponent) else { return nil }
            let size = DirectorySizer.size(of: url)
            guard size > 0 else { return nil }
            return Finding(url: url, size: size, category: category, confidence: confidence,
                           reason: reason, lastModified: DirectorySizer.modificationDate(of: url))
        }
    }
}
```

`FixedPathsRule.swift`:

```swift
import Foundation
import CleanerCore
import DiskScanner

struct FixedPathsRule: Rule {
    struct Entry {
        let relativePath: String
        let reason: String
        let confidence: Confidence
    }

    let category: Category
    let entries: [Entry]

    func scan(_ context: RuleContext) -> [Finding] {
        entries.compactMap { e in
            guard !Task.isCancelled else { return nil }
            let url = context.home.appendingPathComponent(e.relativePath, isDirectory: true)
            let size = DirectorySizer.size(of: url)
            guard size > 0 else { return nil }
            return Finding(url: url, size: size, category: category, confidence: e.confidence,
                           reason: e.reason, lastModified: DirectorySizer.modificationDate(of: url))
        }
    }
}
```

`RuleEngine.swift` (`DevArtifactRule` Task 5'te eklenir; `standard()` şimdilik onsuz):

```swift
import Foundation
import CleanerCore
import Safety

public struct RuleEngine: Sendable {
    private let rules: [any Rule]

    public init(rules: [any Rule]) { self.rules = rules }

    public static func standard() -> RuleEngine {
        RuleEngine(rules: [
            ChildrenRule(category: .cache, relativeDirectory: "Library/Caches", excluding: ["Homebrew"],
                         confidence: .high, reason: "Uygulama önbelleği; uygulama yeniden oluşturur"),
            ChildrenRule(category: .logs, relativeDirectory: "Library/Logs", excluding: [],
                         confidence: .high, reason: "Log dosyaları"),
            FixedPathsRule(category: .homebrew, entries: [
                .init(relativePath: "Library/Caches/Homebrew",
                      reason: "Homebrew indirme önbelleği; `brew cleanup` karşılığı", confidence: .high),
            ]),
            FixedPathsRule(category: .xcode, entries: [
                .init(relativePath: "Library/Developer/Xcode/DerivedData",
                      reason: "Xcode derleme çıktıları; yeniden üretilir", confidence: .high),
                .init(relativePath: "Library/Developer/CoreSimulator/Caches",
                      reason: "Simulator önbelleği", confidence: .high),
                .init(relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
                      reason: "Eski cihaz destek dosyaları; cihaz bağlanınca yeniden iner", confidence: .medium),
                .init(relativePath: "Library/Developer/Xcode/Archives",
                      reason: "Xcode arşivleri; yayınlanmış build'ler olabilir", confidence: .low),
            ]),
        ])
    }

    public func scan(_ context: RuleContext, gate: SafetyGate) async -> [Finding] {
        let all = await withTaskGroup(of: [Finding].self) { group in
            for rule in rules { group.addTask { rule.scan(context) } }
            var acc: [Finding] = []
            for await r in group { acc += r }
            return acc
        }
        var seen = Set<String>()
        return all
            .filter { gate.isAllowed($0.url) && !context.excludedPaths.contains($0.url.path) }
            .sorted { $0.size > $1.size }
            .filter { seen.insert($0.id).inserted }
    }
}
```

- [ ] **Step 5:** `swift test -q --filter RulesTests` → PASS.

- [ ] **Step 6: Commit** — `feat: core rules and RuleEngine`.

---

### Task 5: DevArtifactRule

**Files:**
- Create: `Sources/Rules/DevArtifactRule.swift`
- Modify: `Sources/Rules/RuleEngine.swift` (`standard()` listesine `DevArtifactRule()` ekle)
- Test: `Tests/RulesTests/DevArtifactRuleTests.swift`

**Interfaces:**
- Consumes: `RuleContext.scanRoots`, `RuleContext.now`.
- Produces: `struct DevArtifactRule: Rule` (parametresiz init). Yaş: <7 gün `.low`, <30 gün `.medium`, aksi `.high`.

- [ ] **Step 1: Başarısız testi yaz**

```swift
import Foundation
import Testing
import TestSupport
import CleanerCore
@testable import Rules

private func scan(_ t: TempDir, root: String = "w") -> [Finding] {
    DevArtifactRule().scan(RuleContext(home: t.url, scanRoots: [t.url.appendingPathComponent(root)]))
}

@Test func nodeModulesNeedsPackageJsonAndSkipsNested() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("w/p1/package.json")
    try t.file("w/p1/node_modules/dep/index.js", bytes: 5_000)
    try t.file("w/p1/node_modules/dep/node_modules/inner/i.js", bytes: 5_000)
    try t.file("w/p2/node_modules/dep/index.js", bytes: 5_000) // manifest yok
    try t.setModified("w/p1/node_modules", daysAgo: 60)
    let out = scan(t)
    #expect(out.count == 1)
    #expect(out[0].url.path.hasSuffix("w/p1/node_modules"))
    #expect(out[0].confidence == .high)
}

@Test func mavenGradleAndPythonArtifacts() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("w/m/pom.xml"); try t.file("w/m/target/classes/A.class", bytes: 5_000)
    try t.file("w/g/build.gradle"); try t.file("w/g/build/out.bin", bytes: 5_000)
    try t.file("w/g/.gradle/c.bin", bytes: 5_000)
    try t.file("w/py/requirements.txt")
    try t.file("w/py/venv/pyvenv.cfg"); try t.file("w/py/venv/lib/x.py", bytes: 5_000)
    try t.file("w/py2/requirements.txt"); try t.file("w/py2/venv/notes.txt", bytes: 5_000) // pyvenv.cfg yok
    let names = Set(scan(t).map { $0.url.path.replacingOccurrences(of: t.url.path + "/w/", with: "") })
    #expect(names == ["m/target", "g/build", "g/.gradle", "py/venv"])
}

@Test func recentlyModifiedIsLowConfidence() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("w/p/package.json")
    try t.file("w/p/node_modules/d/i.js", bytes: 5_000)
    try t.setModified("w/p/node_modules", daysAgo: 2)
    #expect(scan(t).first?.confidence == .low)
    try t.setModified("w/p/node_modules", daysAgo: 15)
    #expect(scan(t).first?.confidence == .medium)
}

@Test func symlinkNamedNodeModulesIsIgnored() throws {
    let t = try TempDir(); defer { t.remove() }
    try t.file("w/p/package.json")
    try t.dir("outside/data"); try t.file("outside/data/big.bin", bytes: 5_000)
    try FileManager.default.createSymbolicLink(
        at: t.url.appendingPathComponent("w/p/node_modules"),
        withDestinationURL: t.url.appendingPathComponent("outside/data"))
    #expect(scan(t).isEmpty)
}
```

- [ ] **Step 2:** `swift test -q --filter DevArtifactRuleTests` → FAIL.

- [ ] **Step 3: Uygula**

```swift
import Foundation
import CleanerCore
import DiskScanner

struct DevArtifactRule: Rule {
    struct Pattern {
        let dirName: String
        let manifests: [String]
        let marker: String?
        let reason: String

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
              reason: "npm bağımlılıkları; `npm install` ile geri gelir"),
        .init(dirName: "target", manifests: ["pom.xml", "Cargo.toml"], marker: nil,
              reason: "Maven/Cargo derleme çıktısı; yeniden üretilir"),
        .init(dirName: "build", manifests: gradle, marker: nil, reason: "Gradle derleme çıktısı; yeniden üretilir"),
        .init(dirName: ".gradle", manifests: gradle, marker: nil, reason: "Gradle proje önbelleği"),
        .init(dirName: "venv", manifests: python, marker: "pyvenv.cfg", reason: "Python sanal ortamı; yeniden kurulur"),
        .init(dirName: ".venv", manifests: python, marker: "pyvenv.cfg", reason: "Python sanal ortamı; yeniden kurulur"),
        .init(dirName: "__pycache__", manifests: python, marker: nil, reason: "Python bytecode önbelleği"),
    ]
    static let skipNames: Set<String> = [".git", "Library", ".Trash", "Applications"]

    func scan(_ context: RuleContext) -> [Finding] {
        var out: [Finding] = []
        let fm = FileManager.default
        for root in context.scanRoots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                        options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if Task.isCancelled { return out }
                // Symlink'ler isDirectory=false döner; böylece takip edilmezler.
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let name = url.lastPathComponent
                if Self.skipNames.contains(name) { e.skipDescendants(); continue }
                guard let p = Self.patterns.first(where: { $0.dirName == name }), p.matches(url) else { continue }
                e.skipDescendants()
                let size = DirectorySizer.size(of: url)
                guard size > 0 else { continue }
                out.append(finding(url, size: size, pattern: p, now: context.now))
            }
        }
        return out
    }

    private func finding(_ url: URL, size: Int64, pattern: Pattern, now: Date) -> Finding {
        let mtime = DirectorySizer.modificationDate(of: url)
        let ageDays = now.timeIntervalSince(mtime ?? .distantPast) / 86_400
        let confidence: Confidence = ageDays < 7 ? .low : ageDays < 30 ? .medium : .high
        let reason = ageDays < 7 ? pattern.reason + " (son 7 günde değişti)" : pattern.reason
        return Finding(url: url, size: size, category: .devArtifact, confidence: confidence,
                       reason: reason, lastModified: mtime)
    }
}
```

`RuleEngine.standard()` listesinin sonuna `DevArtifactRule(),` ekle.

- [ ] **Step 4:** `swift test -q --filter RulesTests` → PASS (tüm Rules testleri).

- [ ] **Step 5: Commit** — `feat: DevArtifactRule`.

---

### Task 6: Preferences (profiller, ayarlar, Keychain)

**Files:**
- Create: `Sources/Preferences/ProviderProfile.swift`, `Sources/Preferences/SettingsStore.swift`, `Sources/Preferences/SecretStore.swift`
- Modify: `Package.swift`
- Test: `Tests/PreferencesTests/PreferencesTests.swift`

**Interfaces:**
- Produces:
  - `enum ProviderKind { anthropic, openAICompatible, customHTTP }`, `enum AuthStyle { bearer, header(String), query(String) }`
  - `struct ProviderProfile` alanları: `id, name, kind, baseURL, model, path, auth, extraHeaders, bodyTemplate, responsePath, timeout`; `extraHeadersText`; fabrikalar `.anthropic()`, `.openAICompatible()`, `.custom()`.
  - `struct SettingsData` alanları: `profiles, activeProfileID, aiEnabled, scanRoots, excludedPaths`; `activeProfile`; `static defaults(home:)`.
  - `struct SettingsStore { init(fileURL:); static var standard; load(home:) -> SettingsData; save(_:) throws }`
  - `protocol SecretStore: Sendable { secret(for: UUID) -> String?; setSecret(_: String?, for: UUID) throws }`, `InMemorySecretStore`, `KeychainSecretStore`.

- [ ] **Step 1: Package.swift**

```swift
        .target(name: "Preferences", dependencies: ["CleanerCore"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences", "TestSupport"]),
```

- [ ] **Step 2: Başarısız testi yaz**

```swift
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
```

- [ ] **Step 3:** `swift test -q --filter PreferencesTests` → FAIL.

- [ ] **Step 4: Uygula**

`ProviderProfile.swift`:

```swift
import Foundation

public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case anthropic, openAICompatible, customHTTP

    public var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAICompatible: "OpenAI uyumlu"
        case .customHTTP: "Özel HTTP"
        }
    }
}

public enum AuthStyle: Codable, Sendable, Equatable {
    case bearer
    case header(String)
    case query(String)
}

public struct ProviderProfile: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: ProviderKind
    public var baseURL: String
    public var model: String
    public var path: String
    public var auth: AuthStyle
    public var extraHeaders: [String: String]
    public var bodyTemplate: String
    public var responsePath: String
    public var timeout: TimeInterval

    public init(id: UUID = UUID(), name: String, kind: ProviderKind, baseURL: String, model: String,
                path: String, auth: AuthStyle, extraHeaders: [String: String] = [:],
                bodyTemplate: String = "", responsePath: String = "", timeout: TimeInterval = 60) {
        self.id = id; self.name = name; self.kind = kind; self.baseURL = baseURL; self.model = model
        self.path = path; self.auth = auth; self.extraHeaders = extraHeaders
        self.bodyTemplate = bodyTemplate; self.responsePath = responsePath; self.timeout = timeout
    }

    public static func anthropic() -> ProviderProfile {
        .init(name: "Claude", kind: .anthropic, baseURL: "https://api.anthropic.com",
              model: "claude-sonnet-5-5", path: "/v1/messages", auth: .header("x-api-key"))
    }

    public static func openAICompatible() -> ProviderProfile {
        .init(name: "OpenAI uyumlu", kind: .openAICompatible, baseURL: "http://localhost:11434",
              model: "llama3", path: "/v1/chat/completions", auth: .bearer)
    }

    public static func custom() -> ProviderProfile {
        .init(name: "Şirket LLM", kind: .customHTTP, baseURL: "https://llm.example.com", model: "",
              path: "/v1/generate", auth: .bearer,
              bodyTemplate: #"{"model":"{{model}}","system":"{{system}}","prompt":"{{prompt}}"}"#,
              responsePath: "output.text")
    }

    /// Düzenleme için "Ad: değer" satırları; geçersiz satırlar atlanır.
    public var extraHeadersText: String {
        get { extraHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n") }
        set {
            var d: [String: String] = [:]
            for line in newValue.split(separator: "\n") {
                guard let c = line.firstIndex(of: ":") else { continue }
                let k = line[..<c].trimmingCharacters(in: .whitespaces)
                let v = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { d[k] = v }
            }
            extraHeaders = d
        }
    }
}
```

`SettingsStore.swift`:

```swift
import Foundation

public struct SettingsData: Codable, Sendable, Equatable {
    public var profiles: [ProviderProfile]
    public var activeProfileID: UUID?
    public var aiEnabled: Bool
    public var scanRoots: [String]
    public var excludedPaths: [String]

    public init(profiles: [ProviderProfile] = [], activeProfileID: UUID? = nil, aiEnabled: Bool = false,
                scanRoots: [String] = [], excludedPaths: [String] = []) {
        self.profiles = profiles; self.activeProfileID = activeProfileID; self.aiEnabled = aiEnabled
        self.scanRoots = scanRoots; self.excludedPaths = excludedPaths
    }

    public var activeProfile: ProviderProfile? { profiles.first { $0.id == activeProfileID } }

    public static func defaults(home: URL) -> SettingsData {
        let candidates = ["Developer", "development", "dev", "Projects", "projects",
                          "workspace", "workspaces", "src", "code", "Documents", "Desktop"]
        let roots = candidates.map { home.appendingPathComponent($0).path }
            .filter { FileManager.default.fileExists(atPath: $0) }
        return SettingsData(scanRoots: roots)
    }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static var standard: SettingsStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SettingsStore(fileURL: base.appendingPathComponent("CleanerApp/settings.json"))
    }

    public func load(home: URL) -> SettingsData {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data)
        else { return .defaults(home: home) }
        return decoded
    }

    public func save(_ settings: SettingsData) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(settings).write(to: fileURL, options: .atomic)
    }
}
```

`SecretStore.swift`:

```swift
import Foundation
import Security

public protocol SecretStore: Sendable {
    func secret(for id: UUID) -> String?
    func setSecret(_ value: String?, for id: UUID) throws
}

public enum SecretError: Error { case keychain(OSStatus) }

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]

    public init() {}

    public func secret(for id: UUID) -> String? { lock.withLock { values[id] } }

    public func setSecret(_ value: String?, for id: UUID) throws {
        lock.withLock { values[id] = value }
    }
}

public struct KeychainSecretStore: SecretStore {
    private let service = "CleanerApp.ai"

    public init() {}

    private func base(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func secret(for id: UUID) -> String? {
        var q = base(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public func setSecret(_ value: String?, for id: UUID) throws {
        SecItemDelete(base(id) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var q = base(id)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretError.keychain(status) }
    }
}
```

- [ ] **Step 5:** `swift test -q --filter PreferencesTests` → PASS. (Keychain gerçek makinede Task 13'te elle doğrulanır.)

- [ ] **Step 6: Commit** — `feat: Preferences (profiles, settings store, secret stores)`.

---

### Task 7: AI sağlayıcıları (Anthropic, OpenAI uyumlu, Özel HTTP)

**Files:**
- Create: `Sources/AI/AIProvider.swift`, `Sources/AI/RequestSupport.swift`, `Sources/AI/JSONPathLite.swift`, `Sources/AI/AnthropicProvider.swift`, `Sources/AI/OpenAICompatibleProvider.swift`, `Sources/AI/CustomHTTPProvider.swift`, `Sources/AI/ProviderFactory.swift`
- Create: `Sources/TestSupport/StubHTTP.swift`
- Modify: `Package.swift`
- Test: `Tests/AITests/ProviderTests.swift`

**Interfaces:**
- Consumes: `ProviderProfile`, `AuthStyle` (Preferences).
- Produces:
  - `protocol HTTPClient: Sendable { func send(_ request: URLRequest) async throws -> (Data, Int) }`, `URLSessionHTTPClient`
  - `enum AIError: Error, Equatable { invalidConfig(String), http(Int), badResponse(String) }`
  - `protocol AIProvider: Sendable { func complete(system: String, prompt: String) async throws -> String }`
  - `ProviderFactory.make(profile:apiKey:http:) -> any AIProvider`
  - Test: `final class StubHTTP: HTTPClient` (`lastRequest`, sabit yanıt).

- [ ] **Step 1: Package.swift**

```swift
        .target(name: "AI", dependencies: ["CleanerCore", "Preferences"]),
        .testTarget(name: "AITests", dependencies: ["AI", "Preferences", "TestSupport"]),
```
ve `TestSupport` hedefinin bağımlılıklarını `["AI"]` yap: `.target(name: "TestSupport", dependencies: ["AI"])`.

- [ ] **Step 2: StubHTTP ve başarısız testleri yaz**

`Sources/TestSupport/StubHTTP.swift`:

```swift
import Foundation
import AI

public final class StubHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _last: URLRequest?
    private let status: Int
    private let body: Data

    public init(status: Int = 200, json: String) {
        self.status = status
        self.body = Data(json.utf8)
    }

    public var lastRequest: URLRequest? { lock.withLock { _last } }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.withLock { _last = request }
        return (body, status)
    }
}
```

`Tests/AITests/ProviderTests.swift`:

```swift
import Foundation
import Testing
import TestSupport
import Preferences
@testable import AI

private func bodyJSON(_ r: URLRequest) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: try #require(r.httpBody)) as? [String: Any])
}

@Test func anthropicRequestAndResponse() async throws {
    let http = StubHTTP(json: #"{"content":[{"type":"text","text":"merhaba"}]}"#)
    let p = AnthropicProvider(profile: .anthropic(), apiKey: "K", http: http)
    #expect(try await p.complete(system: "S", prompt: "P") == "merhaba")
    let r = try #require(http.lastRequest)
    #expect(r.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(r.value(forHTTPHeaderField: "x-api-key") == "K")
    #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    let sys = try #require(try bodyJSON(r)["system"] as? [[String: Any]])
    #expect((sys[0]["cache_control"] as? [String: String])?["type"] == "ephemeral")
}

@Test func openAICompatibleRequestAndResponse() async throws {
    let http = StubHTTP(json: #"{"choices":[{"message":{"content":"ok"}}]}"#)
    var profile = ProviderProfile.openAICompatible()
    profile.baseURL = "http://localhost:11434/"   // sondaki / tolere edilir
    let p = OpenAICompatibleProvider(profile: profile, apiKey: "K", http: http)
    #expect(try await p.complete(system: "S", prompt: "P") == "ok")
    let r = try #require(http.lastRequest)
    #expect(r.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
    #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer K")
}

@Test func customHTTPTemplateEscapingAuthAndPath() async throws {
    let http = StubHTTP(json: #"{"output":{"text":"cevap"}}"#)
    var profile = ProviderProfile.custom()
    profile.model = "m1"
    profile.auth = .header("X-Api-Key")
    profile.extraHeaders = ["X-Team": "core"]
    let p = CustomHTTPProvider(profile: profile, apiKey: "K", http: http)
    let prompt = "satır1\n\"tırnak\" \\ ve Çalışma"
    #expect(try await p.complete(system: "S", prompt: prompt) == "cevap")
    let r = try #require(http.lastRequest)
    #expect(r.url?.absoluteString == "https://llm.example.com/v1/generate")
    #expect(r.value(forHTTPHeaderField: "X-Api-Key") == "K")
    #expect(r.value(forHTTPHeaderField: "X-Team") == "core")
    let b = try bodyJSON(r)
    #expect(b["prompt"] as? String == prompt)
    #expect(b["model"] as? String == "m1")
}

@Test func customHTTPQueryAuth() async throws {
    let http = StubHTTP(json: #"{"output":{"text":"x"}}"#)
    var profile = ProviderProfile.custom()
    profile.auth = .query("api_key")
    _ = try await CustomHTTPProvider(profile: profile, apiKey: "K", http: http).complete(system: "", prompt: "")
    #expect(http.lastRequest?.url?.absoluteString == "https://llm.example.com/v1/generate?api_key=K")
}

@Test func errorsAreMapped() async throws {
    let unauthorized = StubHTTP(status: 401, json: "{}")
    await #expect(throws: AIError.http(401)) {
        try await OpenAICompatibleProvider(profile: .openAICompatible(), apiKey: "K", http: unauthorized)
            .complete(system: "", prompt: "")
    }
    var profile = ProviderProfile.custom()
    profile.responsePath = "nope.0"
    await #expect(throws: AIError.self) {
        try await CustomHTTPProvider(profile: profile, apiKey: "K", http: StubHTTP(json: #"{"a":1}"#))
            .complete(system: "", prompt: "")
    }
    profile.bodyTemplate = "{ not json {{prompt}}"
    await #expect(throws: AIError.self) {
        try await CustomHTTPProvider(profile: profile, apiKey: "K", http: StubHTTP(json: "{}"))
            .complete(system: "", prompt: "")
    }
    profile.bodyTemplate = "{}"; profile.baseURL = "not a url"
    await #expect(throws: AIError.self) {
        try await CustomHTTPProvider(profile: profile, apiKey: "K", http: StubHTTP(json: "{}"))
            .complete(system: "", prompt: "")
    }
}

@Test func jsonPathLiteReadsNestedAndIndexed() throws {
    let d = Data(#"{"a":[{"b":"x"},{"b":7}]}"#.utf8)
    #expect(try JSONPathLite.extract("a.0.b", from: d) == "x")
    #expect(try JSONPathLite.extract("a.1.b", from: d) == "7")
    #expect(throws: AIError.self) { try JSONPathLite.extract("a.5.b", from: d) }
}
```

- [ ] **Step 3:** `swift test -q --filter AITests` → FAIL.

- [ ] **Step 4: Uygula**

`AIProvider.swift`:

```swift
import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public enum AIError: Error, Equatable {
    case invalidConfig(String)
    case http(Int)
    case badResponse(String)
}

public protocol AIProvider: Sendable {
    func complete(system: String, prompt: String) async throws -> String
}
```

`RequestSupport.swift`:

```swift
import Foundation
import Preferences

enum RequestSupport {
    static func makeRequest(profile: ProviderProfile, apiKey: String, body: Data,
                            extra: [String: String] = [:]) throws -> URLRequest {
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let path = profile.path.hasPrefix("/") ? profile.path : "/" + profile.path
        guard var comps = URLComponents(string: base + path) else {
            throw AIError.invalidConfig("Geçersiz URL")
        }
        if case .query(let name) = profile.auth {
            comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: name, value: apiKey)]
        }
        guard let url = comps.url, url.scheme != nil, url.host != nil else {
            throw AIError.invalidConfig("Geçersiz URL")
        }
        var r = URLRequest(url: url, timeoutInterval: profile.timeout)
        r.httpMethod = "POST"
        r.httpBody = body
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch profile.auth {
        case .bearer: r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .header(let name): r.setValue(apiKey, forHTTPHeaderField: name)
        case .query: break
        }
        for (k, v) in extra.merging(profile.extraHeaders, uniquingKeysWith: { _, new in new }) {
            r.setValue(v, forHTTPHeaderField: k)
        }
        return r
    }

    static func send(_ http: any HTTPClient, _ request: URLRequest) async throws -> Data {
        let (data, status) = try await http.send(request)
        guard (200..<300).contains(status) else { throw AIError.http(status) }
        return data
    }
}
```

`JSONPathLite.swift`:

```swift
import Foundation

enum JSONPathLite {
    static func extract(_ path: String, from data: Data) throws -> String {
        guard var node = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw AIError.badResponse("Yanıt JSON değil")
        }
        for part in path.split(separator: ".").map(String.init) {
            if let i = Int(part), let arr = node as? [Any], arr.indices.contains(i) {
                node = arr[i]
            } else if let dict = node as? [String: Any], let v = dict[part] {
                node = v
            } else {
                throw AIError.badResponse("Yanıtta '\(path)' yolu bulunamadı")
            }
        }
        if let s = node as? String { return s }
        if node is NSNumber { return "\(node)" }
        throw AIError.badResponse("'\(path)' metin değil")
    }
}
```

`AnthropicProvider.swift`:

```swift
import Foundation
import Preferences

public struct AnthropicProvider: AIProvider {
    let profile: ProviderProfile
    let apiKey: String
    let http: any HTTPClient

    public init(profile: ProviderProfile, apiKey: String, http: any HTTPClient) {
        self.profile = profile; self.apiKey = apiKey; self.http = http
    }

    public func complete(system: String, prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": profile.model,
            "max_tokens": 2048,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": prompt]],
        ]
        let req = try RequestSupport.makeRequest(
            profile: profile, apiKey: apiKey,
            body: try JSONSerialization.data(withJSONObject: body),
            extra: ["anthropic-version": "2023-06-01"])
        return try JSONPathLite.extract("content.0.text", from: try await RequestSupport.send(http, req))
    }
}
```

`OpenAICompatibleProvider.swift`:

```swift
import Foundation
import Preferences

public struct OpenAICompatibleProvider: AIProvider {
    let profile: ProviderProfile
    let apiKey: String
    let http: any HTTPClient

    public init(profile: ProviderProfile, apiKey: String, http: any HTTPClient) {
        self.profile = profile; self.apiKey = apiKey; self.http = http
    }

    public func complete(system: String, prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": profile.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
        ]
        let req = try RequestSupport.makeRequest(
            profile: profile, apiKey: apiKey, body: try JSONSerialization.data(withJSONObject: body))
        return try JSONPathLite.extract("choices.0.message.content", from: try await RequestSupport.send(http, req))
    }
}
```

`CustomHTTPProvider.swift`:

```swift
import Foundation
import Preferences

public struct CustomHTTPProvider: AIProvider {
    let profile: ProviderProfile
    let apiKey: String
    let http: any HTTPClient

    public init(profile: ProviderProfile, apiKey: String, http: any HTTPClient) {
        self.profile = profile; self.apiKey = apiKey; self.http = http
    }

    public func complete(system: String, prompt: String) async throws -> String {
        let rendered = try render(profile.bodyTemplate, ["model": profile.model, "system": system, "prompt": prompt])
        guard (try? JSONSerialization.jsonObject(with: Data(rendered.utf8), options: [.fragmentsAllowed])) != nil else {
            throw AIError.invalidConfig("Gövde şablonu geçerli JSON üretmiyor")
        }
        let req = try RequestSupport.makeRequest(profile: profile, apiKey: apiKey, body: Data(rendered.utf8))
        return try JSONPathLite.extract(profile.responsePath, from: try await RequestSupport.send(http, req))
    }

    /// Değerler JSON-kaçışlı yerleştirilir; tırnaklar şablonda yazılı olmalıdır: `"{{prompt}}"`.
    private func render(_ template: String, _ values: [String: String]) throws -> String {
        var out = template
        for (key, value) in values {
            let encoded = try JSONEncoder().encode(value)
            let inner = String(decoding: encoded.dropFirst().dropLast(), as: UTF8.self)
            out = out.replacingOccurrences(of: "{{\(key)}}", with: inner)
        }
        return out
    }
}
```

`ProviderFactory.swift`:

```swift
import Foundation
import Preferences

public enum ProviderFactory {
    public static func make(profile: ProviderProfile, apiKey: String,
                            http: any HTTPClient = URLSessionHTTPClient()) -> any AIProvider {
        switch profile.kind {
        case .anthropic: AnthropicProvider(profile: profile, apiKey: apiKey, http: http)
        case .openAICompatible: OpenAICompatibleProvider(profile: profile, apiKey: apiKey, http: http)
        case .customHTTP: CustomHTTPProvider(profile: profile, apiKey: apiKey, http: http)
        }
    }
}
```

- [ ] **Step 5:** `swift test -q --filter AITests` → PASS. `CustomHTTPProvider` şablon testi `"{{model}}"` yer tutucularının tırnak içinde yazıldığına dayanır (varsayılan `.custom()` şablonu böyledir).

- [ ] **Step 6: Commit** — `feat: AI providers (Anthropic, OpenAI-compatible, custom HTTP)`.

---

### Task 8: AI puanlama (prompt, ayrıştırma, uygulama)

**Files:**
- Create: `Sources/AI/AIPrompt.swift`, `Sources/AI/AIScorer.swift`
- Test: `Tests/AITests/ScorerTests.swift`

**Interfaces:**
- Consumes: `Finding`, `Confidence`, `AIProvider`, `AIError`.
- Produces:
  - `struct AIPrompt: Sendable, Identifiable { init(findings: [Finding], home: URL, now: Date = Date()); system; user; preview; indexedIDs: [String]; static maxItems = 100 }`
  - `struct AIVerdict: Codable, Equatable { i: Int; confidence: String; reason: String }`
  - `enum AIScorer { candidates(from:) -> [Finding]; parse(_:) throws -> [AIVerdict]; apply(_:to:prompt:) -> [Finding]; refine(prompt:findings:provider:) async throws -> [Finding] }`
  - Kural: AI güveni en fazla bir seviye yükseltebilir (`min(AI, kural+1)`); geçersiz indeks/etiket yok sayılır.

- [ ] **Step 1: Başarısız testi yaz**

```swift
import Foundation
import Testing
import TestSupport
import CleanerCore
@testable import AI

private func finding(_ t: TempDir, _ rel: String, size: Int64 = 1_048_576,
                     _ c: Confidence = .medium) -> Finding {
    Finding(url: t.url.appendingPathComponent(rel), size: size, category: .cache, confidence: c,
            reason: "kural", lastModified: Date().addingTimeInterval(-10 * 86_400))
}

@Test func promptRedactsHomeKeepsUnicodeAndLimitsItems() throws {
    let t = try TempDir(); defer { t.remove() }
    let f = finding(t, "Library/Caches/Çalışma Klasörü")
    let prompt = AIPrompt(findings: [f], home: t.url)
    #expect(!prompt.user.contains(t.url.path))
    #expect(prompt.user.contains("~/Library/Caches/Çalışma Klasörü"))
    #expect(prompt.preview.contains(prompt.system) && prompt.preview.contains(prompt.user))
    #expect(prompt.indexedIDs == [f.id])
    let many = (0..<150).map { finding(t, "Library/Caches/c\($0)", size: Int64($0 + 1)) }
    #expect(AIPrompt(findings: many, home: t.url).indexedIDs.count == AIPrompt.maxItems)
}

@Test func parseToleratesFencesAndRejectsGarbage() throws {
    let fenced = "```json\n[{\"i\":0,\"confidence\":\"high\",\"reason\":\"ok\"}]\n```"
    #expect(try AIScorer.parse(fenced) == [AIVerdict(i: 0, confidence: "high", reason: "ok")])
    #expect(throws: AIError.self) { try AIScorer.parse("sorry, no") }
    #expect(throws: AIError.self) { try AIScorer.parse("[{\"x\":1}]") }
}

@Test func applyClampsRaiseIgnoresInvalidAndNeverAddsFindings() throws {
    let t = try TempDir(); defer { t.remove() }
    let low = finding(t, "Library/Caches/a", .low)
    let med = finding(t, "Library/Caches/b", .medium)
    let prompt = AIPrompt(findings: [low, med], home: t.url)  // boyut eşit; sıra korunur
    let idxLow = try #require(prompt.indexedIDs.firstIndex(of: low.id))
    let idxMed = try #require(prompt.indexedIDs.firstIndex(of: med.id))
    let verdicts = [
        AIVerdict(i: idxLow, confidence: "high", reason: "çok güvenli"),   // low → en fazla medium
        AIVerdict(i: idxMed, confidence: "low", reason: "emin değilim"),   // düşürme serbest
        AIVerdict(i: 99, confidence: "high", reason: "yok"),               // aralık dışı
        AIVerdict(i: 0, confidence: "bogus", reason: "x"),                 // geçersiz etiket
    ]
    let out = AIScorer.apply(verdicts, to: [low, med], prompt: prompt)
    #expect(out.count == 2)
    #expect(out.first { $0.id == low.id }?.confidence == .medium)
    #expect(out.first { $0.id == low.id }?.reason == "çok güvenli")
    #expect(out.first { $0.id == med.id }?.confidence == .low)
}

@Test func candidatesExcludeHighAndRefineUsesProvider() async throws {
    let t = try TempDir(); defer { t.remove() }
    let high = finding(t, "Library/Caches/h", .high)
    let med = finding(t, "Library/Caches/m", .medium)
    #expect(AIScorer.candidates(from: [high, med]).map(\.id) == [med.id])
    struct Canned: AIProvider {
        func complete(system: String, prompt: String) async throws -> String {
            "[{\"i\":0,\"confidence\":\"high\",\"reason\":\"güvenli\"}]"
        }
    }
    let prompt = AIPrompt(findings: [med], home: t.url)
    let out = try await AIScorer.refine(prompt: prompt, findings: [high, med], provider: Canned())
    #expect(out.first { $0.id == med.id }?.confidence == .high)
}
```

- [ ] **Step 2:** `swift test -q --filter ScorerTests` → FAIL.

- [ ] **Step 3: Uygula**

`AIPrompt.swift`:

```swift
import Foundation
import CleanerCore

public struct AIPrompt: Sendable, Identifiable {
    public let id = UUID()
    public let system: String
    public let user: String
    public let indexedIDs: [String]
    public static let maxItems = 100

    /// Kullanıcıya onay için gösterilen, gönderilecek verinin birebir kopyası.
    public var preview: String { "SYSTEM:\n\(system)\n\nUSER:\n\(user)" }

    static let systemPrompt = """
        You review disk-cleanup candidates on macOS. Each item is metadata only; you cannot see file contents. \
        For every item decide whether deleting it is safe because it can be regenerated, and how confident you are. \
        Reply with ONLY a JSON array: [{"i":<index>,"confidence":"low|medium|high","reason":"<max 12 words, Turkish>"}]. \
        Be conservative: if unsure, use "low".
        """

    private struct Item: Encodable {
        let i: Int
        let path: String
        let sizeMB: Double
        let category: String
        let ageDays: Int?
        let ruleConfidence: String
        let ruleReason: String
    }

    public init(findings: [Finding], home: URL, now: Date = Date()) {
        let picked = Array(findings.sorted { $0.size > $1.size }.prefix(Self.maxItems))
        indexedIDs = picked.map(\.id)
        let items = picked.enumerated().map { i, f in
            Item(i: i, path: Self.redact(f.url.path, home: home),
                 sizeMB: (Double(f.size) / 1_048_576 * 10).rounded() / 10,
                 category: f.category.rawValue,
                 ageDays: f.lastModified.map { Int(now.timeIntervalSince($0) / 86_400) },
                 ruleConfidence: String(describing: f.confidence), ruleReason: f.reason)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        user = String(decoding: (try? enc.encode(items)) ?? Data("[]".utf8), as: UTF8.self)
        system = Self.systemPrompt
    }

    static func redact(_ path: String, home: URL) -> String {
        if path == home.path { return "~" }
        if path.hasPrefix(home.path + "/") { return "~" + String(path.dropFirst(home.path.count)) }
        return path
    }
}
```

`AIScorer.swift`:

```swift
import Foundation
import CleanerCore

public struct AIVerdict: Codable, Equatable, Sendable {
    public let i: Int
    public let confidence: String
    public let reason: String

    public init(i: Int, confidence: String, reason: String) {
        self.i = i; self.confidence = confidence; self.reason = reason
    }
}

public enum AIScorer {
    public static func candidates(from findings: [Finding]) -> [Finding] {
        findings.filter { $0.confidence != .high }
    }

    public static func parse(_ text: String) throws -> [AIVerdict] {
        guard let s = text.firstIndex(of: "["), let e = text.lastIndex(of: "]"), s < e else {
            throw AIError.badResponse("JSON dizisi bulunamadı")
        }
        do {
            return try JSONDecoder().decode([AIVerdict].self, from: Data(text[s...e].utf8))
        } catch {
            throw AIError.badResponse("JSON çözülemedi")
        }
    }

    public static func apply(_ verdicts: [AIVerdict], to findings: [Finding], prompt: AIPrompt) -> [Finding] {
        var byID = Dictionary(findings.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for v in verdicts {
            guard prompt.indexedIDs.indices.contains(v.i),
                  let level = Confidence(label: v.confidence),
                  var f = byID[prompt.indexedIDs[v.i]] else { continue }
            let cap = Confidence(rawValue: min(f.confidence.rawValue + 1, Confidence.high.rawValue)) ?? .high
            f.confidence = min(level, cap)
            if !v.reason.isEmpty { f.reason = v.reason }
            byID[f.id] = f
        }
        return findings.map { byID[$0.id] ?? $0 }
    }

    public static func refine(prompt: AIPrompt, findings: [Finding], provider: any AIProvider) async throws -> [Finding] {
        let text = try await provider.complete(system: prompt.system, prompt: prompt.user)
        return apply(try parse(text), to: findings, prompt: prompt)
    }
}
```

- [ ] **Step 4:** `swift test -q --filter AITests` → PASS.

- [ ] **Step 5: Commit** — `feat: AI scoring (prompt, parse, apply)`.

---

### Task 9: Cleaning (dry-run ve Çöp Kutusu'na taşıma)

**Files:**
- Create: `Sources/Cleaning/Cleaner.swift`, `Sources/Cleaning/WorkspaceTrasher.swift`
- Create: `Sources/TestSupport/StubTrasher.swift`
- Modify: `Package.swift`
- Test: `Tests/CleaningTests/CleanerTests.swift`

**Interfaces:**
- Consumes: `SafetyGate`, `Finding`.
- Produces:
  - `protocol Trasher: Sendable { func trash(_ url: URL) async throws }`, `WorkspaceTrasher`
  - `struct DryRun: Sendable, Equatable { allowed, rejected: [Finding]; totalBytes }`
  - `struct CleanReport: Sendable { struct Failure { finding, message }; trashed: [Finding]; failures: [Failure]; reclaimedBytes }`
  - `struct Cleaner: Sendable { init(gate:trasher:); preview(_:) -> DryRun; clean(_:) async -> CleanReport }`
  - Test: `actor StubTrasher: Trasher` (`trashed`, `failing: Set<String>`).

- [ ] **Step 1: Package.swift**

```swift
        .target(name: "Cleaning", dependencies: ["CleanerCore", "Safety"]),
        .testTarget(name: "CleaningTests", dependencies: ["Cleaning", "TestSupport"]),
```
`TestSupport` bağımlılıklarını `["AI", "Cleaning"]` yap.

- [ ] **Step 2: StubTrasher ve başarısız testi yaz**

`Sources/TestSupport/StubTrasher.swift`:

```swift
import Foundation
import Cleaning

public actor StubTrasher: Trasher {
    public struct Boom: Error, LocalizedError {
        public var errorDescription: String? { "izin reddedildi" }
    }

    public private(set) var trashed: [URL] = []
    private let failing: Set<String>

    public init(failing: Set<String> = []) { self.failing = failing }

    public func trash(_ url: URL) async throws {
        if failing.contains(url.path) { throw Boom() }
        trashed.append(url)
    }
}
```

`Tests/CleaningTests/CleanerTests.swift`:

```swift
import Foundation
import Testing
import TestSupport
import CleanerCore
import Safety
@testable import Cleaning

private func finding(_ url: URL, _ size: Int64) -> Finding {
    Finding(url: url, size: size, category: .cache, confidence: .high, reason: "r", lastModified: nil)
}

@Test func dryRunSeparatesRejected() throws {
    let t = try TempDir(); defer { t.remove() }
    let ok = finding(t.url.appendingPathComponent("Library/Caches/a"), 10)
    let bad = finding(URL(fileURLWithPath: "/usr/lib"), 99)
    let run = Cleaner(gate: SafetyGate(home: t.url), trasher: StubTrasher()).preview([ok, bad])
    #expect(run.allowed == [ok] && run.rejected == [bad] && run.totalBytes == 10)
}

@Test func cleanReportsPartialFailuresWithoutStopping() async throws {
    let t = try TempDir(); defer { t.remove() }
    let a = finding(t.url.appendingPathComponent("Library/Caches/a"), 10)
    let b = finding(t.url.appendingPathComponent("Library/Caches/b"), 20)
    let c = finding(t.url.appendingPathComponent("Library/Caches/c"), 40)
    let evil = finding(URL(fileURLWithPath: "/usr/lib"), 99)
    let stub = StubTrasher(failing: [b.url.path])
    let report = await Cleaner(gate: SafetyGate(home: t.url), trasher: stub).clean([a, b, c, evil])
    #expect(report.trashed == [a, c])
    #expect(report.reclaimedBytes == 50)
    #expect(Set(report.failures.map(\.finding.id)) == [b.id, evil.id])
    #expect(report.failures.first { $0.finding.id == b.id }?.message == "izin reddedildi")
    #expect(await stub.trashed == [a.url, c.url])   // /usr/lib'e dokunulmadı
}
```

- [ ] **Step 3:** `swift test -q --filter CleaningTests` → FAIL.

- [ ] **Step 4: Uygula**

`WorkspaceTrasher.swift`:

```swift
import AppKit

public protocol Trasher: Sendable {
    func trash(_ url: URL) async throws
}

public struct WorkspaceTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) async throws {
        try await recycle(url)
    }

    @MainActor
    private func recycle(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }
}
```

`Cleaner.swift`:

```swift
import Foundation
import CleanerCore
import Safety

public struct DryRun: Sendable, Equatable {
    public let allowed: [Finding]
    public let rejected: [Finding]
    public var totalBytes: Int64 { allowed.reduce(0) { $0 + $1.size } }
}

public struct CleanReport: Sendable {
    public struct Failure: Sendable {
        public let finding: Finding
        public let message: String
    }

    public let trashed: [Finding]
    public let failures: [Failure]
    public var reclaimedBytes: Int64 { trashed.reduce(0) { $0 + $1.size } }
}

public struct Cleaner: Sendable {
    private let gate: SafetyGate
    private let trasher: any Trasher

    public init(gate: SafetyGate, trasher: any Trasher = WorkspaceTrasher()) {
        self.gate = gate
        self.trasher = trasher
    }

    public func preview(_ findings: [Finding]) -> DryRun {
        DryRun(allowed: findings.filter { gate.isAllowed($0.url) },
               rejected: findings.filter { !gate.isAllowed($0.url) })
    }

    public func clean(_ findings: [Finding]) async -> CleanReport {
        var trashed: [Finding] = []
        var failures: [CleanReport.Failure] = []
        for f in findings {
            guard gate.isAllowed(f.url) else {
                failures.append(.init(finding: f, message: "Güvenlik kontrolü reddetti"))
                continue
            }
            do {
                try await trasher.trash(f.url)
                trashed.append(f)
            } catch {
                failures.append(.init(finding: f, message: error.localizedDescription))
            }
        }
        return CleanReport(trashed: trashed, failures: failures)
    }
}
```

- [ ] **Step 5:** `swift test -q --filter CleaningTests` → PASS.

- [ ] **Step 6: Commit** — `feat: Cleaner with dry-run and recycle`.

---

### Task 10: AppModel (ScanViewModel)

**Files:**
- Create: `Sources/AppModel/ScanViewModel.swift`
- Modify: `Package.swift`
- Test: `Tests/AppModelTests/ScanViewModelTests.swift`

**Interfaces:**
- Consumes: `RuleEngine`, `RuleContext`, `SafetyGate`, `SettingsStore`, `SettingsData`, `SecretStore`, `ProviderFactory`, `HTTPClient`, `AIScorer`, `AIPrompt`, `Cleaner`, `Trasher`.
- Produces `@MainActor @Observable final class ScanViewModel`:
  - `init(store: SettingsStore, secrets: any SecretStore, engine: RuleEngine = .standard(), home: URL, trasher: any Trasher = WorkspaceTrasher(), http: any HTTPClient = URLSessionHTTPClient())`
  - `static func live() -> ScanViewModel`, `static func hasFullDiskAccess(home:) -> Bool`
  - durum: `phase: Phase (.idle .scanning .ready .cleaning .done)`, `findings`, `selected: Set<String>`, `report: CleanReport?`, `aiStatus: String?`, `settings: SettingsData`
  - `grouped: [(category: Category, items: [Finding])]`, `selectedFindings`, `selectedBytes`, `totalBytes`
  - `scan() async`, `aiPrompt() -> AIPrompt?`, `runAI(_:) async`, `dryRun() -> DryRun`, `clean() async`, `saveSettings()`, `apiKey(for:) -> String`, `setAPIKey(_:for:)`, `testConnection(profile:apiKey:) async -> String`

- [ ] **Step 1: Package.swift**

```swift
        .target(name: "AppModel", dependencies: ["CleanerCore", "Rules", "Safety", "Preferences", "AI", "Cleaning"]),
        .testTarget(name: "AppModelTests", dependencies: ["AppModel", "Rules", "TestSupport"]),
```

- [ ] **Step 2: Başarısız testleri yaz**

```swift
import Foundation
import Testing
import TestSupport
import CleanerCore
import Rules
import Preferences
import AI
import Cleaning
@testable import AppModel

private struct StubRule: Rule {
    let findings: [Finding]
    func scan(_ context: RuleContext) -> [Finding] { findings }
}

private func finding(_ t: TempDir, _ name: String, _ size: Int64, _ c: Confidence) -> Finding {
    Finding(url: t.url.appendingPathComponent("Library/Caches/\(name)"), size: size, category: .cache,
            confidence: c, reason: "r", lastModified: nil)
}

@MainActor
private func makeModel(_ t: TempDir, findings: [Finding], trasher: any Trasher = StubTrasher(),
                       http: any HTTPClient = StubHTTP(json: "{}")) -> ScanViewModel {
    ScanViewModel(store: SettingsStore(fileURL: t.url.appendingPathComponent("s.json")),
                  secrets: InMemorySecretStore(),
                  engine: RuleEngine(rules: [StubRule(findings: findings)]),
                  home: t.url, trasher: trasher, http: http)
}

@MainActor @Test func scanSortsPreselectsHighAndHandlesEmpty() async throws {
    let t = try TempDir(); defer { t.remove() }
    let big = finding(t, "big", 300, .high), mid = finding(t, "mid", 200, .medium)
    let m = makeModel(t, findings: [mid, big])
    await m.scan()
    #expect(m.phase == .ready)
    #expect(m.findings.map(\.id) == [big.id, mid.id])
    #expect(m.selected == [big.id])
    #expect(m.totalBytes == 500 && m.selectedBytes == 300)
    let empty = makeModel(t, findings: [])
    await empty.scan()
    #expect(empty.phase == .ready && empty.findings.isEmpty)
}

@MainActor @Test func cleanRemovesTrashedKeepsFailedAndReports() async throws {
    let t = try TempDir(); defer { t.remove() }
    let a = finding(t, "a", 10, .high), b = finding(t, "b", 20, .high)
    let m = makeModel(t, findings: [a, b], trasher: StubTrasher(failing: [b.url.path]))
    await m.scan()
    await m.clean()
    #expect(m.phase == .done)
    #expect(m.report?.trashed.map(\.id) == [a.id])
    #expect(m.report?.failures.map(\.finding.id) == [b.id])
    #expect(m.findings.map(\.id) == [b.id])
}

@MainActor @Test func aiOffReturnsNilAndFailureKeepsRuleResults() async throws {
    let t = try TempDir(); defer { t.remove() }
    let med = finding(t, "m", 10, .medium)
    let ok = StubHTTP(json: #"{"content":[{"text":"[{\"i\":0,\"confidence\":\"high\",\"reason\":\"güvenli\"}]"}]}"#)
    let m = makeModel(t, findings: [med], http: ok)
    await m.scan()
    #expect(m.aiPrompt() == nil)                       // AI kapalı
    let profile = ProviderProfile.anthropic()
    m.settings.profiles = [profile]; m.settings.activeProfileID = profile.id; m.settings.aiEnabled = true
    let prompt = try #require(m.aiPrompt())
    await m.runAI(prompt)
    #expect(m.findings.first?.confidence == .high)
    let bad = makeModel(t, findings: [med], http: StubHTTP(status: 500, json: "{}"))
    await bad.scan()
    bad.settings.profiles = [profile]; bad.settings.activeProfileID = profile.id; bad.settings.aiEnabled = true
    await bad.runAI(try #require(bad.aiPrompt()))
    #expect(bad.findings.first?.confidence == .medium)
    #expect(bad.aiStatus?.contains("kural tabanlı") == true)
}
```

(`AIPrompt` Equatable değildir; `m.aiPrompt() == nil` karşılaştırması `Optional` nil kontrolü olarak derlenir.)

- [ ] **Step 3:** `swift test -q --filter AppModelTests` → FAIL.

- [ ] **Step 4: Uygula**

```swift
import Foundation
import Observation
import CleanerCore
import Rules
import Safety
import Preferences
import AI
import Cleaning

@MainActor @Observable
public final class ScanViewModel {
    public enum Phase: Equatable, Sendable { case idle, scanning, ready, cleaning, done }

    public private(set) var phase: Phase = .idle
    public private(set) var findings: [Finding] = []
    public var selected: Set<String> = []
    public private(set) var report: CleanReport?
    public private(set) var aiStatus: String?
    public var settings: SettingsData

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let engine: RuleEngine
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let trasher: any Trasher
    @ObservationIgnored private let http: any HTTPClient

    public init(store: SettingsStore, secrets: any SecretStore, engine: RuleEngine = .standard(),
                home: URL, trasher: any Trasher = WorkspaceTrasher(),
                http: any HTTPClient = URLSessionHTTPClient()) {
        self.store = store; self.secrets = secrets; self.engine = engine
        self.home = home; self.trasher = trasher; self.http = http
        self.settings = store.load(home: home)
    }

    public static func live() -> ScanViewModel {
        ScanViewModel(store: .standard, secrets: KeychainSecretStore(),
                      home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Full Disk Access yoksa Safari klasörü listelenemez (TCC reddi).
    public static func hasFullDiskAccess(home: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Safari").path)
            return true
        } catch {
            let ns = error as NSError
            let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            return !(ns.code == NSFileReadNoPermissionError || posix == Int(EPERM) || posix == Int(EACCES))
        }
    }

    // MARK: Türetilmiş durum

    public var grouped: [(category: Category, items: [Finding])] {
        Category.allCases.compactMap { c in
            let items = findings.filter { $0.category == c }
            return items.isEmpty ? nil : (category: c, items: items)
        }
    }
    public var selectedFindings: [Finding] { findings.filter { selected.contains($0.id) } }
    public var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.size } }
    public var totalBytes: Int64 { findings.reduce(0) { $0 + $1.size } }

    // MARK: Akış

    public func scan() async {
        phase = .scanning
        report = nil
        aiStatus = nil
        let ctx = RuleContext(home: home,
                              scanRoots: settings.scanRoots.map { URL(fileURLWithPath: $0, isDirectory: true) },
                              excludedPaths: Set(settings.excludedPaths))
        let result = await engine.scan(ctx, gate: SafetyGate(home: home))
        findings = result
        selected = Set(result.filter { $0.confidence == .high }.map(\.id))
        phase = .ready
    }

    public func aiPrompt() -> AIPrompt? {
        guard settings.aiEnabled, settings.activeProfile != nil else { return nil }
        let candidates = AIScorer.candidates(from: findings)
        return candidates.isEmpty ? nil : AIPrompt(findings: candidates, home: home)
    }

    public func runAI(_ prompt: AIPrompt) async {
        guard let profile = settings.activeProfile else { return }
        let provider = ProviderFactory.make(profile: profile, apiKey: secrets.secret(for: profile.id) ?? "", http: http)
        do {
            findings = try await AIScorer.refine(prompt: prompt, findings: findings, provider: provider)
            aiStatus = "AI \(prompt.indexedIDs.count) öğeyi değerlendirdi."
        } catch {
            aiStatus = "AI kullanılamadı, kural tabanlı sonuçlar gösteriliyor (\(error))."
        }
    }

    public func dryRun() -> DryRun {
        Cleaner(gate: SafetyGate(home: home), trasher: trasher).preview(selectedFindings)
    }

    public func clean() async {
        phase = .cleaning
        let r = await Cleaner(gate: SafetyGate(home: home), trasher: trasher).clean(selectedFindings)
        report = r
        let gone = Set(r.trashed.map(\.id))
        findings.removeAll { gone.contains($0.id) }
        selected.subtract(gone)
        phase = .done
    }

    // MARK: Ayarlar

    public func saveSettings() { try? store.save(settings) }

    public func apiKey(for id: UUID) -> String { secrets.secret(for: id) ?? "" }

    public func setAPIKey(_ key: String, for id: UUID) { try? secrets.setSecret(key, for: id) }

    public func testConnection(profile: ProviderProfile, apiKey: String) async -> String {
        let provider = ProviderFactory.make(profile: profile, apiKey: apiKey, http: http)
        do {
            let out = try await provider.complete(system: "Reply with the single word OK.", prompt: "ping")
            return "Bağlantı başarılı: \(out.prefix(40))"
        } catch {
            return "Bağlantı başarısız: \(error)"
        }
    }
}
```

- [ ] **Step 5:** `swift test -q --filter AppModelTests` → PASS. Ardından tüm paket: `swift test -q` → PASS.

- [ ] **Step 6: Commit** — `feat: ScanViewModel`.

---

### Task 11: SwiftUI uygulaması: pano, onay, AI önizleme

**Files:**
- Create: `Sources/CleanerApp/CleanerMain.swift`, `Sources/CleanerApp/DashboardView.swift`, `Sources/CleanerApp/FindingRow.swift`, `Sources/CleanerApp/Sheets.swift`, `Sources/CleanerApp/Format.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `ScanViewModel` (Task 10), `AIPrompt`, `DryRun`, `CleanReport`.
- Produces: çalışan pencere; `SettingsView` Task 12'de eklenir (bu task'ta geçici `Text("Ayarlar")`).

GUI birim testi yoktur; doğrulama derleme + elle çalıştırma.

- [ ] **Step 1: Package.swift**

```swift
        .executableTarget(name: "CleanerApp",
                          dependencies: ["AppModel", "CleanerCore", "AI", "Cleaning", "Preferences"]),
```

- [ ] **Step 2: Dosyaları yaz**

`Format.swift`:

```swift
import Foundation

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
```

`CleanerMain.swift`:

```swift
import SwiftUI
import AppModel

@main
struct CleanerMain: App {
    @State private var model = ScanViewModel.live()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
        }
        Settings {
            Text("Ayarlar")   // Task 12'de SettingsView ile değişir
                .environment(model)
        }
    }
}
```

`FindingRow.swift`:

```swift
import SwiftUI
import AppModel
import CleanerCore

struct FindingRow: View {
    @Environment(ScanViewModel.self) private var model
    let finding: Finding

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(finding.id) },
                set: { on in
                    if on { model.selected.insert(finding.id) } else { model.selected.remove(finding.id) }
                }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(finding.url.lastPathComponent).font(.headline)
                Text((finding.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(finding.reason).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(finding.confidence.title)
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(badgeColor.opacity(0.2), in: Capsule())
                .foregroundStyle(badgeColor)
            Text(Format.bytes(finding.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .contextMenu {
            Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
        }
    }

    private var badgeColor: Color {
        switch finding.confidence {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }
}
```

`Sheets.swift`:

```swift
import SwiftUI
import AppModel
import AI

struct ConfirmSheet: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let run = model.dryRun()
        VStack(alignment: .leading, spacing: 12) {
            Text("Çöp Kutusu'na taşı").font(.title2.bold())
            Text("\(run.allowed.count) öğe, toplam \(Format.bytes(run.totalBytes)) Çöp Kutusu'na taşınacak. Alan, Çöp Kutusu'nu boşaltınca açılır.")
            if !run.rejected.isEmpty {
                Text("Güvenlik nedeniyle atlanacak: \(run.rejected.count) öğe").foregroundStyle(.red)
            }
            List(run.allowed) { f in
                HStack { Text(f.url.lastPathComponent); Spacer(); Text(Format.bytes(f.size)).monospacedDigit() }
            }
            .frame(minHeight: 160)
            HStack {
                Spacer()
                Button("İptal", role: .cancel) { dismiss() }
                Button("Çöp Kutusu'na taşı") {
                    dismiss()
                    Task { await model.clean() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(run.allowed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

struct AIPreviewSheet: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: AIPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI'a gönderilecek veri").font(.title2.bold())
            Text("Yalnızca aşağıdaki metadata gönderilir (dosya içeriği gönderilmez).")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(prompt.preview).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 240)
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                Button("Gönder") {
                    dismiss()
                    Task { await model.runAI(prompt) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}
```

`DashboardView.swift`:

```swift
import SwiftUI
import AppModel
import AI
import Cleaning

struct DashboardView: View {
    @Environment(ScanViewModel.self) private var model
    @State private var showConfirm = false
    @State private var aiPrompt: AIPrompt?
    @State private var hasFDA = true

    var body: some View {
        VStack(spacing: 0) {
            header
            if !hasFDA { fdaBanner }
            if let status = model.aiStatus { banner(status, systemImage: "sparkles") }
            if model.phase == .done, let r = model.report { resultBanner(r) }
            content
        }
        .sheet(isPresented: $showConfirm) { ConfirmSheet() }
        .sheet(item: $aiPrompt) { AIPreviewSheet(prompt: $0) }
        .task { hasFDA = ScanViewModel.hasFullDiskAccess(home: FileManager.default.homeDirectoryForCurrentUser) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Geri kazanılabilir").font(.caption).foregroundStyle(.secondary)
                Text(Format.bytes(model.totalBytes)).font(.largeTitle.bold()).monospacedDigit()
            }
            Spacer()
            Button("Tara") { Task { await model.scan() } }
                .disabled(model.phase == .scanning || model.phase == .cleaning)
            Button("AI ile iyileştir") { aiPrompt = model.aiPrompt() }
                .disabled(model.aiPrompt() == nil)
            Button("Temizle (\(model.selected.count) • \(Format.bytes(model.selectedBytes)))") { showConfirm = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selected.isEmpty || model.phase != .ready && model.phase != .done)
        }
        .padding()
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView("Henüz taranmadı", systemImage: "externaldrive",
                                   description: Text("“Tara” ile gereksiz dosyaları bul."))
        case .scanning:
            ProgressView("Taranıyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cleaning:
            ProgressView("Taşınıyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready, .done:
            if model.findings.isEmpty {
                ContentUnavailableView("Temiz", systemImage: "checkmark.seal",
                                       description: Text("Önerilecek bir şey bulunamadı."))
            } else {
                List {
                    ForEach(model.grouped, id: \.category) { group in
                        Section(group.category.title) {
                            ForEach(group.items) { FindingRow(finding: $0) }
                        }
                    }
                }
            }
        }
    }

    private var fdaBanner: some View {
        HStack {
            Image(systemName: "lock.shield")
            Text("Tam Disk Erişimi verilmedi; bazı klasörler taranamayabilir.")
            Spacer()
            Button("Ayarları aç") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding(8).background(.yellow.opacity(0.2))
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        HStack { Image(systemName: systemImage); Text(text); Spacer() }
            .padding(8).background(.blue.opacity(0.1))
    }

    private func resultBanner(_ r: CleanReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
            Text("\(r.trashed.count) öğe (\(Format.bytes(r.reclaimedBytes))) Çöp Kutusu'na taşındı."
                 + (r.failures.isEmpty ? "" : " \(r.failures.count) öğe taşınamadı.")
                 + " Alan, Çöp Kutusu'nu boşaltınca açılır.")
            Spacer()
            Button("Çöp Kutusu'nu aç") {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
            }
        }
        .padding(8).background(.green.opacity(0.15))
    }
}
```

`DashboardView.swift` import listesine `import Cleaning` eklemeyi unutma.

- [ ] **Step 3: Derle**

Run: `swift build -q`
Expected: hatasız. Swift 6 eşzamanlılık uyarı/hataları çıkarsa (ör. `NSWorkspace` erişimi) en dar kapsamda `@MainActor` ekleyerek çöz.

- [ ] **Step 4: Elle çalıştır**

Run: `swift run CleanerApp`
Expected: pencere açılır; “Tara” sonuç listeler; satırlar seçilebilir; “Temizle” onay sheet'ini açar. Bu adımda gerçek silmeyi onaylama; yalnızca “İptal” et.

- [ ] **Step 5: Commit** — `feat: SwiftUI dashboard, confirm and AI preview sheets`.

---

### Task 12: Settings penceresi (AI profilleri, tarama kökleri)

**Files:**
- Create: `Sources/CleanerApp/SettingsView.swift`, `Sources/CleanerApp/ProfileEditor.swift`
- Modify: `Sources/CleanerApp/CleanerMain.swift` (`Settings { SettingsView().environment(model) }`)

**Interfaces:**
- Consumes: `ScanViewModel.settings`, `saveSettings()`, `apiKey(for:)`, `setAPIKey(_:for:)`, `testConnection(profile:apiKey:)`.

- [ ] **Step 1: `CleanerMain.swift` düzenle**

`Settings { Text("Ayarlar") ... }` bloğunu şununla değiştir:

```swift
        Settings {
            SettingsView().environment(model)
        }
```

- [ ] **Step 2: `SettingsView.swift`**

```swift
import SwiftUI
import AppModel
import Preferences

struct SettingsView: View {
    var body: some View {
        TabView {
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
            ScanSettingsView().tabItem { Label("Tarama", systemImage: "folder") }
        }
        .frame(width: 600, height: 560)
        .padding()
    }
}

struct AISettingsView: View {
    @Environment(ScanViewModel.self) private var model
    @State private var apiKey = ""
    @State private var testResult = ""

    private var activeIndex: Int? {
        model.settings.profiles.firstIndex { $0.id == model.settings.activeProfileID }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("AI desteğini aç", isOn: $model.settings.aiEnabled)
            Picker("Aktif profil", selection: $model.settings.activeProfileID) {
                Text("Yok").tag(UUID?.none)
                ForEach(model.settings.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            HStack {
                Menu("Profil ekle") {
                    Button("Claude (Anthropic)") { add(.anthropic()) }
                    Button("OpenAI uyumlu (Ollama, LiteLLM, Azure…)") { add(.openAICompatible()) }
                    Button("Özel HTTP (şirket LLM platformu)") { add(.custom()) }
                }
                Button("Profili sil", role: .destructive) { removeActive() }.disabled(activeIndex == nil)
            }
            if let i = activeIndex {
                ProfileEditor(profile: $model.settings.profiles[i], apiKey: $apiKey, testResult: $testResult)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { model.saveSettings() }
        .onChange(of: model.settings.activeProfileID, initial: true) {
            apiKey = model.settings.activeProfileID.map { model.apiKey(for: $0) } ?? ""
            testResult = ""
        }
        .onChange(of: apiKey) {
            if let id = model.settings.activeProfileID { model.setAPIKey(apiKey, for: id) }
        }
    }

    private func add(_ profile: ProviderProfile) {
        model.settings.profiles.append(profile)
        model.settings.activeProfileID = profile.id
    }

    private func removeActive() {
        guard let i = activeIndex else { return }
        let id = model.settings.profiles[i].id
        model.setAPIKey("", for: id)
        model.settings.profiles.remove(at: i)
        model.settings.activeProfileID = model.settings.profiles.first?.id
    }
}

struct ScanSettingsView: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            PathListEditor(title: "Taranacak proje kökleri", paths: $model.settings.scanRoots)
            PathListEditor(title: "Hariç tutulan yollar", paths: $model.settings.excludedPaths)
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { model.saveSettings() }
    }
}

struct PathListEditor: View {
    let title: String
    @Binding var paths: [String]

    var body: some View {
        Section(title) {
            ForEach(paths, id: \.self) { p in
                HStack {
                    Text(p).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { paths.removeAll { $0 == p } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button("Klasör ekle…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let u = panel.url, !paths.contains(u.path) { paths.append(u.path) }
            }
        }
    }
}
```

- [ ] **Step 3: `ProfileEditor.swift`**

```swift
import SwiftUI
import AppModel
import Preferences

struct ProfileEditor: View {
    @Environment(ScanViewModel.self) private var model
    @Binding var profile: ProviderProfile
    @Binding var apiKey: String
    @Binding var testResult: String
    @State private var headersText = ""

    private var authKind: Binding<Int> {
        Binding(
            get: {
                switch profile.auth { case .bearer: 0; case .header: 1; case .query: 2 }
            },
            set: { kind in
                let current = authName.wrappedValue
                switch kind {
                case 0: profile.auth = .bearer
                case 1: profile.auth = .header(current.isEmpty ? "x-api-key" : current)
                default: profile.auth = .query(current.isEmpty ? "key" : current)
                }
            })
    }

    private var authName: Binding<String> {
        Binding(
            get: {
                switch profile.auth { case .bearer: ""; case .header(let n), .query(let n): n }
            },
            set: { name in
                switch profile.auth {
                case .bearer: break
                case .header: profile.auth = .header(name)
                case .query: profile.auth = .query(name)
                }
            })
    }

    var body: some View {
        Section("Profil") {
            TextField("Ad", text: $profile.name)
            Picker("Tür", selection: $profile.kind) {
                ForEach(ProviderKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Host / Base URL", text: $profile.baseURL)
            TextField("Endpoint yolu", text: $profile.path)
            TextField("Model", text: $profile.model)
            Picker("Kimlik doğrulama", selection: authKind) {
                Text("Bearer token").tag(0)
                Text("Özel header").tag(1)
                Text("Query parametresi").tag(2)
            }
            if authKind.wrappedValue != 0 { TextField("Header / parametre adı", text: authName) }
            SecureField("API key (Keychain'de saklanır)", text: $apiKey)
            VStack(alignment: .leading) {
                Text("Ekstra header'lar (Ad: değer)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $headersText).font(.body.monospaced()).frame(height: 56)
            }
            Stepper("Zaman aşımı: \(Int(profile.timeout)) sn", value: $profile.timeout, in: 5...300, step: 5)
        }
        if profile.kind == .customHTTP {
            Section("İstek şablonu") {
                VStack(alignment: .leading) {
                    Text("Gövde (JSON). Yer tutucular: {{model}}, {{system}}, {{prompt}} — tırnak içinde yazın.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $profile.bodyTemplate).font(.body.monospaced()).frame(height: 90)
                }
                TextField("Yanıt metni JSON yolu (ör. choices.0.message.content)", text: $profile.responsePath)
            }
        }
        Section {
            HStack {
                Button("Bağlantıyı test et") {
                    testResult = "Test ediliyor…"
                    let p = profile, k = apiKey
                    Task { testResult = await model.testConnection(profile: p, apiKey: k) }
                }
                Text(testResult).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { headersText = profile.extraHeadersText }
        .onChange(of: profile.id) { headersText = profile.extraHeadersText }
        .onChange(of: headersText) { profile.extraHeadersText = headersText }
    }
}
```

- [ ] **Step 4: Derle ve elle doğrula**

Run: `swift build -q` → hatasız.
Run: `swift run CleanerApp`, ⌘, ile Ayarlar: üç profil türü eklenir, alanlar düzenlenir, uygulama kapanıp açılınca korunur (`~/Library/Application Support/CleanerApp/settings.json`), API key bu dosyada **yoktur** (`grep -c "sk-" ~/Library/Application\ Support/CleanerApp/settings.json` → 0).

- [ ] **Step 5: Commit** — `feat: Settings window with AI profiles and scan roots`.

---

### Task 13: .app paketleme, Full Disk Access ve uçtan uca doğrulama

**Files:**
- Create: `scripts/make-app.sh`
- Modify: `AGENTS.md` (komutlar bölümüne paketleme satırı)

**Interfaces:** yok (dağıtım betiği).

- [ ] **Step 1: `scripts/make-app.sh` yaz**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -q
BIN="$(swift build -c release --show-bin-path)/CleanerApp"
APP="build/Cleaner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/CleanerApp"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Cleaner</string>
  <key>CFBundleExecutable</key><string>CleanerApp</string>
  <key>CFBundleIdentifier</key><string>com.sercancelenk.cleaner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "$APP"
```

```bash
chmod +x scripts/make-app.sh && scripts/make-app.sh
```
Expected: son satır `build/Cleaner.app`.

- [ ] **Step 2: AGENTS.md komutlar bölümüne ekle**

`- Paketle: \`scripts/make-app.sh\` → \`build/Cleaner.app\` (ad-hoc imza; her yeniden derlemede Tam Disk Erişimi tekrar istenebilir)`

- [ ] **Step 3: Full Disk Access ver**

Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi → `build/Cleaner.app` ekle. Uygulamayı `open build/Cleaner.app` ile aç. Beklenen: sarı FDA uyarısı görünmez.

- [ ] **Step 4: Uçtan uca elle doğrulama (gerçek disk, ama yalnızca test verisiyle sil)**

1. Test projesi oluştur: `mkdir -p ~/development/_cleaner_e2e/p && cd ~/development/_cleaner_e2e/p && echo '{}' > package.json && mkdir -p node_modules/x && head -c 5000000 /dev/zero > node_modules/x/big.bin && touch -t 202501010000 node_modules` (taranan köklerde `~/development` olmalı).
2. Uygulamada “Tara”: `_cleaner_e2e/p/node_modules` listede, “Yüksek” güven.
3. Boyut kontrolü: `du -sh ~/Library/Caches` ile en büyük cache satırı aynı büyüklük mertebesinde.
4. Yalnızca `node_modules` satırını seç → “Temizle” → onay sheet'inde yalnızca o öğe görünür → onayla. Beklenen: banner “1 öğe … Çöp Kutusu'na taşındı”, `~/.Trash` içinde `node_modules` var, Finder'da “Put Back” ile geri alınabilir.
5. AI: Ayarlar'da OpenAI uyumlu profil (ör. yerel Ollama) veya Claude profili ekle, API key gir, “Bağlantıyı test et” → “Bağlantı başarılı”. Panoda “AI ile iyileştir” → önizleme sheet'inde yalnızca `~/…` yolları ve boyutlar görünür → gönder → durum satırı “AI N öğeyi değerlendirdi”. Yanlış key ile tekrarla → “kural tabanlı sonuçlar gösteriliyor” ve liste değişmez.
6. Özel HTTP profili: şirket platformunun host/path/auth/şablon/yanıt yolu girilir, test edilir.
7. Temizlik: `rm -rf ~/development/_cleaner_e2e`; Çöp Kutusu'ndaki test klasörünü Finder'dan boşalt.

- [ ] **Step 5: Tüm testler ve commit**

Run: `swift test -q` → PASS.
`git add -A && git commit -q -m "feat: app bundle script and e2e verification"` (trailer'ı ekle).

---

## Self-Review

- **Spec kapsamı:** Kural motoru ve kategoriler (T4, T5), Safety (T3), AI soyutlaması + CustomHTTP + Keychain + profiller (T6, T7), metadata-only + önizleme/onay (T8, T11), AI hatasında kural-only (T10), dry-run + Çöp Kutusu (T9, T11), pano/ayarlar (T11, T12), FDA yönlendirmesi (T11), tarama iptali (`Task.isCancelled`, T2/T4/T5), test stratejisi (her task). Spec'ten bilinçli sapma: Trash kuralı çıkarıldı (spec'te not edildi). 
- **Placeholder taraması:** TBD/TODO yok; her kod adımı tam kod içerir.
- **Tip tutarlılığı:** `Finding`, `Confidence.title`, `RuleContext`, `RuleEngine.scan(_:gate:)`, `AIPrompt.indexedIDs`, `CleanReport.trashed/failures/reclaimedBytes`, `ScanViewModel` API adları task'lar arasında aynı.
- **Review Focus:** Her madde ilgili task'ta bir testle sabitlendi (1: T3+T5, 2: T8, 3: T4, 4: T8, 5: T9+T10).
