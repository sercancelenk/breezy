import Foundation

public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    public init() {}

    public func set() { lock.withLock { value = true } }
    public var isSet: Bool { lock.withLock { value } }
}

public enum Parallel {
    /// İşleri çekirdek sayısı kadar iş parçacığına dağıtır. Çağıran Task iptal edilirse bayrak kalkar;
    /// işçiler yeni iş almaz. Kural kodu eşzamanlı olduğu için çağıran thread yalnızca bekler ve iptali izler.
    public static func map<T: Sendable, R: Sendable>(
        _ items: [T], cancel: CancelFlag = CancelFlag(),
        _ work: @escaping @Sendable (T, CancelFlag) -> [R]
    ) -> [R] {
        guard !items.isEmpty else { return [] }
        let lock = NSLock()
        nonisolated(unsafe) var next = 0
        nonisolated(unsafe) var results: [R] = []
        let group = DispatchGroup()
        let workers = min(items.count, max(2, ProcessInfo.processInfo.activeProcessorCount))
        for _ in 0..<workers {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                while !cancel.isSet {
                    let i: Int = lock.withLock { defer { next += 1 }; return next }
                    guard i < items.count else { return }
                    let r = work(items[i], cancel)
                    lock.withLock { results += r }
                }
            }
        }
        while group.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if Task.isCancelled { cancel.set() }
        }
        return results
    }
}
