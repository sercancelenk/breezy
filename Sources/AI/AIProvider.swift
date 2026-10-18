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

public enum AIError: Error, Equatable {
    case invalidConfig(String)
    case http(Int)
    case badResponse(String)
}

public protocol AIProvider: Sendable {
    func complete(system: String, prompt: String) async throws -> String
}
