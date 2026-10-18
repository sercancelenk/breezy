import Foundation
import Preferences

public struct CustomHTTPProvider: AIProvider {
    let profile: ProviderProfile
    let apiKey: String
    let http: any HTTPClient

    public init(profile: ProviderProfile, apiKey: String, http: any HTTPClient) {
        self.profile = profile; self.apiKey = apiKey; self.http = http
    }

    public func complete(system: String, prompt: String) async throws -> String {
        let rendered = try render(profile.bodyTemplate, ["model": profile.model, "system": system, "prompt": prompt])
        guard (try? JSONSerialization.jsonObject(with: Data(rendered.utf8), options: [.fragmentsAllowed])) != nil else {
            throw AIError.invalidConfig("Gövde şablonu geçerli JSON üretmiyor")
        }
        let req = try RequestSupport.makeRequest(profile: profile, apiKey: apiKey, body: Data(rendered.utf8))
        return try JSONPathLite.extract(profile.responsePath, from: try await RequestSupport.send(http, req))
    }

    /// Değerler JSON-kaçışlı yerleştirilir; tırnaklar şablonda yazılı olmalıdır: `"{{prompt}}"`.
    private func render(_ template: String, _ values: [String: String]) throws -> String {
        var out = template
        for (key, value) in values {
            let encoded = try JSONEncoder().encode(value)
            let inner = String(decoding: encoded.dropFirst().dropLast(), as: UTF8.self)
            out = out.replacingOccurrences(of: "{{\(key)}}", with: inner)
        }
        return out
    }
}
