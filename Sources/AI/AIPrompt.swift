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
        You review disk-cleanup candidates on macOS. Each item is metadata only: you see only path and size (plus age), never contents, so do not claim to know what a file contains. \
        For every item decide whether deleting it is safe because it can be regenerated, and how confident you are. \
        Also reason about the owning application from the folder names (e.g. JetBrains caches are re-indexed on next launch; \
        browser caches are re-downloaded; an Archives folder cannot be recreated) and state what the user will experience if deleted. \
        "regenerates": automatic = the app recreates it alone, manual = needs a command or re-download, never = cannot be recreated. \
        "userData": true if the item is likely the user's own personal data (documents, photos, videos, downloads, project sources, chat or app databases). \
        "risk": none|low|medium|high chance that an app breaks or user data/sessions/offline content is lost. \
        Reply with ONLY a JSON array: [{"i":<index>,"confidence":"low|medium|high","reason":"<max 12 words, Turkish>",\
        "regenerates":"automatic|manual|never","risk":"none|low|medium|high","impact":"<max 25 words, Turkish: what happens if deleted>","userData":true|false}]. \
        Be conservative: if unsure, use "low" confidence and a higher risk.
        """

    private struct Item: Encodable {
        let i: Int
        let path: String
        let sizeMB: Double
        let category: String
        let ageDays: Int?
        let ruleConfidence: String
        let ruleReason: String
        let ruleRegenerates: String
        let ruleRisk: String
        let ruleImpact: String
        let ruleUserData: Bool
    }

    public init(findings: [Finding], home: URL, now: Date = Date()) {
        let picked = Array(findings.sorted { $0.size > $1.size }.prefix(Self.maxItems))
        indexedIDs = picked.map(\.id)
        let items = picked.enumerated().map { i, f in
            Item(i: i, path: Self.redact(f.url.path, home: home),
                 sizeMB: (Double(f.size) / 1_048_576 * 10).rounded() / 10,
                 category: f.category.rawValue,
                 ageDays: f.lastModified.map { Int(now.timeIntervalSince($0) / 86_400) },
                 ruleConfidence: String(describing: f.confidence), ruleReason: f.reason,
                 ruleRegenerates: f.impact.regeneration.label, ruleRisk: f.impact.risk.label, ruleImpact: f.impact.note, ruleUserData: f.impact.userData)
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
