import Foundation
import CleanerCore
import Safety

public struct RuleEngine: Sendable {
    private let rules: [any Rule]

    public init(rules: [any Rule]) { self.rules = rules }

    public static func standard() -> RuleEngine {
        RuleEngine(rules: [
            ChildrenRule(category: .cache, relativeDirectory: "Library/Caches", excluding: ["Homebrew"],
                         confidence: .high, reason: "Uygulama önbelleği; uygulama yeniden oluşturur",
                         impact: .genericCache, knownApps: true),
            ChildrenRule(category: .logs, relativeDirectory: "Library/Logs", excluding: [],
                         confidence: .high, reason: "Log dosyaları",
                         impact: Impact(regeneration: .automatic, risk: .minimal,
                                        note: "Geçmiş hata ayıklama kayıtları kaybolur; uygulamalar normal çalışmaya devam eder.")),
            FixedPathsRule(category: .homebrew, entries: [
                .init(relativePath: "Library/Caches/Homebrew",
                      reason: "Homebrew indirme önbelleği; `brew cleanup` karşılığı", confidence: .high,
                      impact: Impact(regeneration: .automatic, risk: .minimal,
                                     note: "Kurulu paketler etkilenmez; yeniden kurulumda paketler tekrar indirilir.")),
            ]),
            DevArtifactRule(),
            FixedPathsRule(category: .xcode, entries: [
                .init(relativePath: "Library/Developer/Xcode/DerivedData",
                      reason: "Xcode derleme çıktıları; yeniden üretilir", confidence: .high,
                      impact: Impact(regeneration: .automatic, risk: .low,
                                     note: "Projeler bir sonraki derlemede sıfırdan derlenir; ilk build uzun sürer.")),
                .init(relativePath: "Library/Developer/CoreSimulator/Caches",
                      reason: "Simulator önbelleği", confidence: .high,
                      impact: Impact(regeneration: .automatic, risk: .low,
                                     note: "Simulator açılışta önbelleği yeniden oluşturur.")),
                .init(relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
                      reason: "Eski cihaz destek dosyaları; cihaz bağlanınca yeniden iner", confidence: .medium,
                      impact: Impact(regeneration: .manual, risk: .low,
                                     note: "Cihaz bir sonraki bağlanışta semboller yeniden iner; bu sırada cihaz hata ayıklaması bekler.")),
                .init(relativePath: "Library/Developer/Xcode/Archives",
                      reason: "Xcode arşivleri; yayınlanmış build'ler olabilir", confidence: .low,
                      impact: Impact(regeneration: .never, risk: .high,
                                     note: "Yeniden üretilemez: yayınlanmış sürümlerin dSYM sembolleri burada olabilir; silinirse çökme raporları çözümlenemez.")),
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
            .filter { f in
                gate.isAllowed(f.url) && !context.excludedPaths.contains { f.url.path == $0 || f.url.path.hasPrefix($0 + "/") }
            }
            .sorted { $0.size > $1.size }
            .filter { seen.insert($0.id).inserted }
    }
}
