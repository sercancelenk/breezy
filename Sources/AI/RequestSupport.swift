import Foundation
import Preferences

enum RequestSupport {
    static func makeRequest(profile: ProviderProfile, apiKey: String, body: Data,
                            extra: [String: String] = [:]) throws -> URLRequest {
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let path = profile.path.hasPrefix("/") ? profile.path : "/" + profile.path
        guard var comps = URLComponents(string: base + path) else {
            throw AIError.invalidConfig("Geçersiz URL")
        }
        if case .query(let name) = profile.auth {
            comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: name, value: apiKey)]
        }
        guard let url = comps.url, url.scheme != nil, url.host != nil else {
            throw AIError.invalidConfig("Geçersiz URL")
        }
        var r = URLRequest(url: url, timeoutInterval: profile.timeout)
        r.httpMethod = "POST"
        r.httpBody = body
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch profile.auth {
        case .bearer: r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .header(let name): r.setValue(apiKey, forHTTPHeaderField: name)
        case .query: break
        }
        for (k, v) in extra.merging(profile.extraHeaders, uniquingKeysWith: { _, new in new }) {
            r.setValue(v, forHTTPHeaderField: k)
        }
        return r
    }

    static func send(_ http: any HTTPClient, _ request: URLRequest) async throws -> Data {
        let (data, status) = try await http.send(request)
        guard (200..<300).contains(status) else { throw AIError.http(status) }
        return data
    }
}
