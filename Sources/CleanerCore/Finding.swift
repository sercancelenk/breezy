import Foundation

public enum FindingCategory: String, Sendable, Codable, CaseIterable {
    case cache, logs, homebrew, xcode, devArtifact, large, backup, installers

    public var title: String {
        switch self {
        case .cache: "Uygulama önbellekleri"
        case .logs: "Log dosyaları"
        case .homebrew: "Homebrew önbelleği"
        case .xcode: "Xcode"
        case .devArtifact: "Geliştirici artifact'ları"
        case .large: "Büyük öğeler"
        case .backup: "Cihaz yedekleri"
        case .installers: "Kurulum dosyaları"
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
    public let category: FindingCategory
    public var confidence: Confidence
    public var reason: String
    public let lastModified: Date?
    public var impact: Impact

    public init(url: URL, size: Int64, category: FindingCategory, confidence: Confidence,
                reason: String, lastModified: Date?, impact: Impact = .routine) {
        self.impact = impact
        self.url = url
        self.size = size
        self.category = category
        self.confidence = confidence
        self.reason = reason
        self.lastModified = lastModified
    }
}
