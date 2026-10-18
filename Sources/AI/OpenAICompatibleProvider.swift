import Foundation
import Preferences

public struct OpenAICompatibleProvider: AIProvider {
    let profile: ProviderProfile
    let apiKey: String
    let http: any HTTPClient

    public init(profile: ProviderProfile, apiKey: String, http: any HTTPClient) {
        self.profile = profile; self.apiKey = apiKey; self.http = http
    }

    public func complete(system: String, prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": profile.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
        ]
        let req = try RequestSupport.makeRequest(
            profile: profile, apiKey: apiKey, body: try JSONSerialization.data(withJSONObject: body))
        return try JSONPathLite.extract("choices.0.message.content", from: try await RequestSupport.send(http, req))
    }
}
