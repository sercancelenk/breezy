import Foundation
import Testing
import TestSupport
import Preferences
@testable import AI

private func bodyJSON(_ r: URLRequest) throws -> [String: Any] {
    let data = try #require(r.httpBody)
    let obj = try JSONSerialization.jsonObject(with: data)
    return try #require(obj as? [String: Any])
}

@Test func anthropicRequestAndResponse() async throws {
    let http = StubHTTP(json: #"{"content":[{"type":"text","text":"merhaba"}]}"#)
    let p = AnthropicProvider(profile: .anthropic(), apiKey: "K", http: http)
    #expect(try await p.complete(system: "S", prompt: "P") == "merhaba")
    let r = try #require(http.lastRequest)
    #expect(r.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(r.value(forHTTPHeaderField: "x-api-key") == "K")
    #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    let sys = try #require(try bodyJSON(r)["system"] as? [[String: Any]])
    #expect((sys[0]["cache_control"] as? [String: String])?["type"] == "ephemeral")
}

@Test func openAICompatibleRequestAndResponse() async throws {
    let http = StubHTTP(json: #"{"choices":[{"message":{"content":"ok"}}]}"#)
    var profile = ProviderProfile.openAICompatible()
    profile.baseURL = "http://localhost:11434/"   // sondaki / tolere edilir
    let p = OpenAICompatibleProvider(profile: profile, apiKey: "K", http: http)
    #expect(try await p.complete(system: "S", prompt: "P") == "ok")
    let r = try #require(http.lastRequest)
    #expect(r.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
    #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer K")
}

@Test func customHTTPTemplateEscapingAuthAndPath() async throws {
    let http = StubHTTP(json: #"{"output":{"text":"cevap"}}"#)
    var profile = ProviderProfile.custom()
    profile.model = "m1"
    profile.auth = .header("X-Api-Key")
    profile.extraHeaders = ["X-Team": "core"]
    let p = CustomHTTPProvider(profile: profile, apiKey: "K", http: http)
    let prompt = "satır1\n\"tırnak\" \\ ve Çalışma"
    #expect(try await p.complete(system: "S", prompt: prompt) == "cevap")
    let r = try #require(http.lastRequest)
    #expect(r.url?.absoluteString == "https://llm.example.com/v1/generate")
    #expect(r.value(forHTTPHeaderField: "X-Api-Key") == "K")
    #expect(r.value(forHTTPHeaderField: "X-Team") == "core")
    let b = try bodyJSON(r)
    #expect(b["prompt"] as? String == prompt)
    #expect(b["model"] as? String == "m1")
}

@Test func customHTTPQueryAuth() async throws {
    let http = StubHTTP(json: #"{"output":{"text":"x"}}"#)
    var profile = ProviderProfile.custom()
    profile.auth = .query("api_key")
    _ = try await CustomHTTPProvider(profile: profile, apiKey: "K", http: http).complete(system: "", prompt: "")
    #expect(http.lastRequest?.url?.absoluteString == "https://llm.example.com/v1/generate?api_key=K")
}

@Test func errorsAreMapped() async throws {
    let unauthorized = StubHTTP(status: 401, json: "{}")
    await #expect(throws: AIError.http(401)) {
        try await OpenAICompatibleProvider(profile: .openAICompatible(), apiKey: "K", http: unauthorized)
            .complete(system: "", prompt: "")
    }
    var profile = ProviderProfile.custom()
    profile.responsePath = "nope.0"
    await #expect(throws: AIError.self) {
        try await CustomHTTPProvider(profile: profile, apiKey: "K", http: StubHTTP(json: #"{"a":1}"#))
            .complete(system: "", prompt: "")
    }
    profile.bodyTemplate = "{ not json {{prompt}}"
    await #expect(throws: AIError.self) {
        try await CustomHTTPProvider(profile: profile, apiKey: "K", http: StubHTTP(json: "{}"))
            .complete(system: "", prompt: "")
    }
    profile.bodyTemplate = "{}"; profile.baseURL = "not a url"
    await #expect(throws: AIError.self) {
        try await CustomHTTPProvider(profile: profile, apiKey: "K", http: StubHTTP(json: "{}"))
            .complete(system: "", prompt: "")
    }
}

@Test func jsonPathLiteReadsNestedAndIndexed() throws {
    let d = Data(#"{"a":[{"b":"x"},{"b":7}]}"#.utf8)
    #expect(try JSONPathLite.extract("a.0.b", from: d) == "x")
    #expect(try JSONPathLite.extract("a.1.b", from: d) == "7")
    #expect(throws: AIError.self) { try JSONPathLite.extract("a.5.b", from: d) }
}

@Test func apiKeyWhitespaceIsTrimmedAndAuthErrorsExplainThemselves() async throws {
    let stub = StubHTTP(json: #"{"content":[{"text":"OK"}]}"#)
    _ = try await AnthropicProvider(profile: .anthropic(), apiKey: "  sk-ant-123\n", http: stub)
        .complete(system: "s", prompt: "p")
    #expect(stub.lastRequest?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-123")
    #expect(AIError.http(401).localizedDescription.contains("API key"))
}
