import Foundation
import CleanerCore

public struct AIVerdict: Codable, Equatable, Sendable {
    public let i: Int
    public let confidence: String
    public let reason: String
    public let regenerates: String?
    public let risk: String?
    public let impact: String?

    public init(i: Int, confidence: String, reason: String,
                regenerates: String? = nil, risk: String? = nil, impact: String? = nil) {
        self.i = i; self.confidence = confidence; self.reason = reason
        self.regenerates = regenerates; self.risk = risk; self.impact = impact
    }
}

public enum AIScorer {
    public static func candidates(from findings: [Finding]) -> [Finding] {
        findings.filter { $0.confidence != .high || $0.impact.isGeneric }
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
            f.impact = merged(f.impact, v)
            byID[f.id] = f
        }
        return findings.map { byID[$0.id] ?? $0 }
    }

    /// Kural biliyorsa AI yalnızca kötüleştirebilir; kural bilmiyorsa (generic) AI'ın notu geçerlidir.
    static func merged(_ rule: Impact, _ v: AIVerdict) -> Impact {
        let regen = max(rule.regeneration, v.regenerates.flatMap(Regeneration.init(label:)) ?? rule.regeneration)
        let risk = max(rule.risk, v.risk.flatMap(Risk.init(label:)) ?? rule.risk)
        let aiNote = (v.impact ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let worse = regen > rule.regeneration || risk > rule.risk
        let useAI = !aiNote.isEmpty && (rule.isGeneric || worse)
        return Impact(regeneration: regen, risk: risk, note: useAI ? aiNote : rule.note,
                      isGeneric: rule.isGeneric, fromAI: rule.fromAI || useAI || rule.isGeneric && v.impact != nil)
    }

    public static func refine(prompt: AIPrompt, findings: [Finding], provider: any AIProvider) async throws -> [Finding] {
        let text = try await provider.complete(system: prompt.system, prompt: prompt.user)
        return apply(try parse(text), to: findings, prompt: prompt)
    }
}
