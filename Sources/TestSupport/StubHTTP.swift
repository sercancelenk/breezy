import Foundation
import AI

public final class StubHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _last: URLRequest?
    private let status: Int
    private let body: Data

    public init(status: Int = 200, json: String) {
        self.status = status
        self.body = Data(json.utf8)
    }

    public var lastRequest: URLRequest? { lock.withLock { _last } }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.withLock { _last = request }
        return (body, status)
    }
}
