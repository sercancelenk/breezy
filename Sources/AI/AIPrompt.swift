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
