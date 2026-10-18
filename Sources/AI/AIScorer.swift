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
