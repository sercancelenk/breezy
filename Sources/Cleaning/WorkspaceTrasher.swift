import AppKit

public protocol Trasher: Sendable {
    func trash(_ url: URL) async throws
}

public struct WorkspaceTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) async throws {
        try await recycle(url)
    }

    @MainActor
    private func recycle(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }
}
