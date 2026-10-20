import Foundation
import Testing
@testable import MacErase

// Fmt shares a formatter, so keep these calls serial and on the main actor.
@Suite(.serialized)
@MainActor
struct FmtTests {
    @Test(arguments: [Int64.min, -1, 0])
    func nonpositiveBytesHaveZeroLabel(_ count: Int64) {
        #expect(Fmt.bytes(count) == "0 KB")
    }

    @Test(arguments: [Int64(1_000), 1_000_000, 1_000_000_000, 1_000_000_000_000, Int64.max])
    func positiveBytesUseFileUnits(_ count: Int64) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        // Locale-aware expectation avoids forcing English labels on Turkish systems.
        #expect(Fmt.bytes(count) == formatter.string(fromByteCount: count))
        #expect(Fmt.bytes(count) != "0 KB")
    }
}
