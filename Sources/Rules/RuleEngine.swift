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
