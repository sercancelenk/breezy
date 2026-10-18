import Foundation

/// Silinirse bu öğenin geri gelip gelmeyeceği (kötüden iyiye değil: büyük değer = daha kötü).
public enum Regeneration: Int, Sendable, Comparable {
    case automatic, manual, never

    public static func < (a: Regeneration, b: Regeneration) -> Bool { a.rawValue < b.rawValue }

    public init?(label: String) {
        switch label.trimmingCharacters(in: .whitespaces).lowercased() {
        case "automatic": self = .automatic
        case "manual": self = .manual
        case "never", "none": self = .never
        default: return nil
        }
    }

    public var label: String {
        switch self { case .automatic: "automatic"; case .manual: "manual"; case .never: "never" }
    }

    public var title: String {
        switch self {
        case .automatic: "Kendiliğinden geri gelir"
        case .manual: "Komutla geri gelir"
        case .never: "Geri gelmez"
        }
    }
}

public enum Risk: Int, Sendable, Comparable {
    case minimal, low, medium, high

    public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

    public init?(label: String) {
        switch label.trimmingCharacters(in: .whitespaces).lowercased() {
        case "none", "minimal": self = .minimal
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        default: return nil
        }
    }

    public var label: String {
        switch self { case .minimal: "none"; case .low: "low"; case .medium: "medium"; case .high: "high" }
    }

    public var title: String {
        switch self {
        case .minimal: "Risk yok"
        case .low: "Düşük risk"
        case .medium: "Orta risk"
        case .high: "Yüksek risk"
        }
    }
}

/// "Bunu silersem ne olur?" değerlendirmesi. Kurallar taban çizgisini verir, AI yalnızca kötüleştirebilir.
public struct Impact: Sendable, Hashable {
    public var regeneration: Regeneration
    public var risk: Risk
    public var note: String
    /// Kural bu öğe hakkında özel bir şey bilmiyor; AI'ın incelemesi değerli.
    public var isGeneric: Bool
    public var fromAI: Bool

    public init(regeneration: Regeneration, risk: Risk, note: String, isGeneric: Bool = false, fromAI: Bool = false) {
        self.regeneration = regeneration; self.risk = risk; self.note = note
        self.isGeneric = isGeneric; self.fromAI = fromAI
    }

    public static let routine = Impact(regeneration: .automatic, risk: .low, note: "")
    public static let genericCache = Impact(regeneration: .automatic, risk: .low,
        note: "Uygulama önbelleği; uygulama ihtiyaç duyunca yeniden oluşturur, ilk açılış yavaşlayabilir.",
        isGeneric: true)

    /// Varsayılan seçime girebilir mi? Geri gelmeyenler yalnızca elle seçilir.
    public var preselectable: Bool { regeneration != .never }
}
