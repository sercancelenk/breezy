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
    let prompt = AIPrompt(findings: [low, med], home: t.url)
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

private func withImpact(_ f: Finding, _ r: Regeneration, _ k: Risk, _ note: String, generic: Bool) -> Finding {
    var f = f
    f.impact = Impact(regeneration: r, risk: k, note: note, isGeneric: generic)
    return f
}

@Test func genericHighItemsAreAICandidatesKnownOnesAreNot() throws {
    let t = try TempDir(); defer { t.remove() }
    let generic = withImpact(finding(t, "Library/Caches/a", .high), .automatic, .low, "n", generic: true)
    let known = withImpact(finding(t, "Library/Caches/b", .high), .automatic, .low, "n", generic: false)
    #expect(AIScorer.candidates(from: [generic, known]).map(\.id) == [generic.id])
}

@Test func aiImpactOnlyWorsensKnownRuleImpactButFillsGenericOnes() throws {
    let t = try TempDir(); defer { t.remove() }
    let known = withImpact(finding(t, "Library/Caches/k"), .manual, .medium, "kural notu", generic: false)
    let generic = withImpact(finding(t, "Library/Caches/g"), .automatic, .low, "genel", generic: true)
    let prompt = AIPrompt(findings: [known, generic], home: t.url)
    let ik = try #require(prompt.indexedIDs.firstIndex(of: known.id))
    let ig = try #require(prompt.indexedIDs.firstIndex(of: generic.id))
    let out = AIScorer.apply([
        AIVerdict(i: ik, confidence: "medium", reason: "r", regenerates: "automatic", risk: "none", impact: "ai gevşetti"),
        AIVerdict(i: ig, confidence: "medium", reason: "r", regenerates: "never", risk: "high", impact: "oturum kaybolur"),
    ], to: [known, generic], prompt: prompt)
    let k = try #require(out.first { $0.id == known.id }), g = try #require(out.first { $0.id == generic.id })
    #expect(k.impact.regeneration == .manual && k.impact.risk == .medium && k.impact.note == "kural notu")
    #expect(g.impact.regeneration == .never && g.impact.risk == .high && g.impact.note == "oturum kaybolur")
    #expect(g.impact.fromAI)
}

@Test func promptCarriesImpactMetadataAndAsksForImpact() throws {
    let t = try TempDir(); defer { t.remove() }
    let f = withImpact(finding(t, "Library/Caches/JetBrains"), .automatic, .low, "indeks yeniden", generic: true)
    let p = AIPrompt(findings: [f], home: t.url)
    #expect(p.user.contains("indeks yeniden") && p.user.contains("automatic"))
    #expect(p.system.contains("regenerates") && p.system.contains("impact"))
}

@Test func aiCanFlagUserDataButRuleUserDataCannotBeCleared() throws {
    let t = try TempDir(); defer { t.remove() }
    var ruleFlagged = finding(t, "Movies/a")
    ruleFlagged.impact = Impact(regeneration: .never, risk: .medium, note: "n", isGeneric: true, userData: true)
    let plain = finding(t, "Other/b")
    let prompt = AIPrompt(findings: [ruleFlagged, plain], home: t.url)
    let ia = try #require(prompt.indexedIDs.firstIndex(of: ruleFlagged.id))
    let ib = try #require(prompt.indexedIDs.firstIndex(of: plain.id))
    let out = AIScorer.apply([
        AIVerdict(i: ia, confidence: "low", reason: "r", userData: false),
        AIVerdict(i: ib, confidence: "low", reason: "r", userData: true),
    ], to: [ruleFlagged, plain], prompt: prompt)
    #expect(out.first { $0.id == ruleFlagged.id }?.impact.userData == true)
    #expect(out.first { $0.id == plain.id }?.impact.userData == true)
    #expect(!prompt.system.contains("extension") && prompt.system.contains("only path and size"))
}

@Test func parseSalvagesCompleteObjectsFromTruncatedReply() throws {
    let cut = #"[{"i":0,"confidence":"high","reason":"a, b","impact":"x } y"},{"i":1,"confidence":"me"#
    let out = try AIScorer.parse(cut)
    #expect(out.map(\.i) == [0] && out[0].impact == "x } y")
}
