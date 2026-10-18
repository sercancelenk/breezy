import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public enum AIError: Error, Equatable, LocalizedError {
    case invalidConfig(String)
    case http(Int)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let m): "Geçersiz ayar: \(m)"
        case .http(let c) where c == 401 || c == 403:
            "HTTP \(c): kimlik doğrulama reddedildi; API key eksik, yanlış ya da bu host için geçersiz"
        case .http(let c): "HTTP \(c)"
        case .badResponse(let m): "Geçersiz yanıt: \(m)"
        }
    }
}

public protocol AIProvider: Sendable {
    func complete(system: String, prompt: String) async throws -> String
}
