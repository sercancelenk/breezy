import Foundation

public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case anthropic, openAICompatible, customHTTP

    public var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAICompatible: "OpenAI uyumlu"
        case .customHTTP: "Özel HTTP"
        }
    }
}

public enum AuthStyle: Codable, Sendable, Equatable {
    case bearer
    case header(String)
    case query(String)
}

public struct ProviderProfile: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: ProviderKind
    public var baseURL: String
    public var model: String
    public var path: String
    public var auth: AuthStyle
    public var extraHeaders: [String: String]
    public var bodyTemplate: String
    public var responsePath: String
    public var timeout: TimeInterval

    public init(id: UUID = UUID(), name: String, kind: ProviderKind, baseURL: String, model: String,
                path: String, auth: AuthStyle, extraHeaders: [String: String] = [:],
                bodyTemplate: String = "", responsePath: String = "", timeout: TimeInterval = 60) {
        self.id = id; self.name = name; self.kind = kind; self.baseURL = baseURL; self.model = model
        self.path = path; self.auth = auth; self.extraHeaders = extraHeaders
        self.bodyTemplate = bodyTemplate; self.responsePath = responsePath; self.timeout = timeout
    }

    public static func anthropic() -> ProviderProfile {
        .init(name: "Claude", kind: .anthropic, baseURL: "https://api.anthropic.com",
              model: "claude-sonnet-5-5", path: "/v1/messages", auth: .header("x-api-key"))
    }

    public static func openAICompatible() -> ProviderProfile {
        .init(name: "OpenAI uyumlu", kind: .openAICompatible, baseURL: "http://localhost:11434",
              model: "llama3", path: "/v1/chat/completions", auth: .bearer)
    }

    public static func custom() -> ProviderProfile {
        .init(name: "Şirket LLM", kind: .customHTTP, baseURL: "https://llm.example.com", model: "",
              path: "/v1/generate", auth: .bearer,
              bodyTemplate: #"{"model":"{{model}}","system":"{{system}}","prompt":"{{prompt}}"}"#,
              responsePath: "output.text")
    }

    /// Düzenleme için "Ad: değer" satırları; geçersiz satırlar atlanır.
    public var extraHeadersText: String {
        get { extraHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n") }
        set {
            var d: [String: String] = [:]
            for line in newValue.split(separator: "\n") {
                guard let c = line.firstIndex(of: ":") else { continue }
                let k = line[..<c].trimmingCharacters(in: .whitespaces)
                let v = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { d[k] = v }
            }
            extraHeaders = d
        }
    }
}
