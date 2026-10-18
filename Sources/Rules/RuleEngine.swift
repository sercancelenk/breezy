import Foundation
import CleanerCore
import Safety

public struct RuleEngine: Sendable {
    private let rules: [any Rule]

    public init(rules: [any Rule]) { self.rules = rules }

    static let backupRule = ChildrenRule(
        category: .backup, relativeDirectory: "Library/Application Support/MobileSync/Backup", excluding: [],
        confidence: .medium, reason: "iPhone/iPad yedeği",
        impact: Impact(regeneration: .never, risk: .high,
                       note: "Cihazında olmayan veriler yalnızca bu yedekte olabilir; silinirse geri gelmez."))

    /// Ağır ev dizini taraması; akıllı taramadan ayrı çalıştırılır.
    public static func largeItems() -> RuleEngine { RuleEngine(rules: [LargeItemsRule()]) }

    public static func standard() -> RuleEngine {
        RuleEngine(rules: [
            backupRule, InstallersRule(), DownloadsRule(), DocumentsRule(),
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

    public func covers(_ category: FindingCategory) -> Bool { rules.contains { $0.categories.contains(category) } }

    /// `categories` verilirse yalnızca bu kategorileri üretebilen kurallar çalışır ve sonuç bu kategorilerle sınırlanır.
    public func scan(_ context: RuleContext, gate: SafetyGate, categories: Set<FindingCategory>? = nil) async -> [Finding] {
        let selected = categories.map { c in rules.filter { !$0.categories.isDisjoint(with: c) } } ?? rules
        let all = await withTaskGroup(of: [Finding].self) { group in
            for rule in selected { group.addTask { rule.scan(context) } }
            var acc: [Finding] = []
            for await r in group { acc += r }
            return acc
        }
        var seen = Set<String>()
        let allowed = all.filter { f in
            (categories?.contains(f.category) ?? true) && gate.isAllowed(f.url) && !context.excludedPaths.contains { f.url.path == $0 || f.url.path.hasPrefix($0 + "/") }
        }
        return Self.dropNested(Self.reconcileLarge(allowed, threshold: context.largeThreshold))
            .sorted { $0.size > $1.size }
            .filter { seen.insert($0.id).inserted }
    }

    /// Başka bir bulgunun içinde kalan bulgular düşer; aksi halde aynı bayt iki kez sayılır.
    static func dropNested(_ findings: [Finding]) -> [Finding] {
        let paths = findings.map(\.url.path)
        return findings.enumerated().compactMap { i, f in
            paths.enumerated().contains { j, p in j != i && f.url.path.hasPrefix(p + "/") } ? nil : f
        }
    }

    /// Büyük öğe, başka bir bulgunun içindeyse düşer; başka bulguları içeriyorsa onların boyutu çıkarılır.
    public static func reconcileLarge(_ findings: [Finding], threshold: Int64) -> [Finding] {
        let others = findings.filter { $0.category != .large }
        return findings.compactMap { f in
            guard f.category == .large else { return f }
            let p = f.url.path
            if others.contains(where: { p == $0.url.path || p.hasPrefix($0.url.path + "/") }) { return nil }
            let inner = others.filter { $0.url.path.hasPrefix(p + "/") }.reduce(Int64(0)) { $0 + $1.size }
            guard inner > 0 else { return f }
            let rest = f.size - inner
            guard rest >= threshold else { return nil }
            return Finding(url: f.url, size: rest, category: f.category, confidence: f.confidence,
                           reason: f.reason, lastModified: f.lastModified, impact: f.impact,
                           ruleConfidence: f.ruleConfidence)
        }
    }
}
