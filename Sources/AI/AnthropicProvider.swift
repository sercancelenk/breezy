import Foundation
import Preferences

public struct AnthropicProvider: AIProvider {
    let profile: ProviderProfile
    let apiKey: String
    let http: any HTTPClient

    public init(profile: ProviderProfile, apiKey: String, http: any HTTPClient) {
        self.profile = profile; self.apiKey = apiKey; self.http = http
    }

    public func complete(system: String, prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": profile.model,
            "max_tokens": 2048,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": prompt]],
        ]
        let req = try RequestSupport.makeRequest(
            profile: profile, apiKey: apiKey,
            body: try JSONSerialization.data(withJSONObject: body),
            extra: ["anthropic-version": "2023-06-01"])
        return try JSONPathLite.extract("content.0.text", from: try await RequestSupport.send(http, req))
    }
}
