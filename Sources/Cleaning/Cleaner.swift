import Foundation
import CleanerCore
import Safety

public struct DryRun: Sendable, Equatable {
    public let allowed: [Finding]
    public let rejected: [Finding]
    public var totalBytes: Int64 { allowed.reduce(0) { $0 + $1.size } }
}

public struct CleanReport: Sendable {
    public struct Failure: Sendable {
        public let finding: Finding
        public let message: String
    }

    public let trashed: [Finding]
    public let failures: [Failure]
    public var reclaimedBytes: Int64 { trashed.reduce(0) { $0 + $1.size } }
}

public struct Cleaner: Sendable {
    private let gate: SafetyGate
    private let trasher: any Trasher

    public init(gate: SafetyGate, trasher: any Trasher = WorkspaceTrasher()) {
        self.gate = gate
        self.trasher = trasher
    }

    public func preview(_ findings: [Finding]) -> DryRun {
        DryRun(allowed: findings.filter { gate.isAllowed($0.url) },
               rejected: findings.filter { !gate.isAllowed($0.url) })
    }

    public func clean(_ findings: [Finding]) async -> CleanReport {
        var trashed: [Finding] = []
        var failures: [CleanReport.Failure] = []
        for f in findings {
            guard gate.isAllowed(f.url) else {
                failures.append(.init(finding: f, message: "Güvenlik kontrolü reddetti"))
                continue
            }
            do {
                try await trasher.trash(f.url)
                trashed.append(f)
            } catch {
                failures.append(.init(finding: f, message: error.localizedDescription))
            }
        }
        return CleanReport(trashed: trashed, failures: failures)
    }
}
