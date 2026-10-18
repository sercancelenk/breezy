import Foundation
import Testing
@testable import CleanerCore

@Test func findingIdIsPath() {
    let f = Finding(url: URL(fileURLWithPath: "/tmp/a"), size: 1, category: .cache,
                    confidence: .high, reason: "r", lastModified: nil)
    #expect(f.id == "/tmp/a")
}

@Test func confidenceOrderingAndLabels() {
    #expect(Confidence.low < .medium)
    #expect(Confidence.medium < .high)
    #expect(Confidence(label: " HIGH ") == .high)
    #expect(Confidence(label: "nope") == nil)
}
