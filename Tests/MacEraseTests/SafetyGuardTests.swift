import Foundation
import Testing
@testable import MacErase

private func sandbox(_ body: (URL) throws -> Void) throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MacEraseSafety-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try body(root)
}

struct SafetyGuardTests {
    @Test func removeRefusesWhenParentIsASymlink() throws {
        try sandbox { root in
            let fm = FileManager.default
            let real = root.appendingPathComponent("real"), link = root.appendingPathComponent("link")
            try fm.createDirectory(at: real, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: real.appendingPathComponent("precious.txt"))
            try fm.createSymbolicLink(at: link, withDestinationURL: real)

            let result = FileUtil.remove([link.appendingPathComponent("precious.txt")])
            #expect(result.done.isEmpty && result.failed.count == 1)
            #expect(fm.fileExists(atPath: real.appendingPathComponent("precious.txt").path))
        }
    }

    @Test func restoreMovesItemBackAndReportsNothingRemaining() throws {
        try sandbox { root in
            let fm = FileManager.default
            let from = root.appendingPathComponent("docs/a.txt"), to = root.appendingPathComponent("trash/a.txt")
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("a".utf8).write(to: to)
            let result = FileUtil.restore([(from: from, to: to)])
            #expect(result.restored == 1 && result.remaining.isEmpty)
            #expect(fm.fileExists(atPath: from.path) && !fm.fileExists(atPath: to.path))
        }
    }

    @Test func restoreNeverOverwritesAndKeepsTheRecordForRetry() throws {
        try sandbox { root in
            let fm = FileManager.default
            let from = root.appendingPathComponent("a.txt"), to = root.appendingPathComponent("trash/a.txt")
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("trashed".utf8).write(to: to)
            try Data("new".utf8).write(to: from)
            let result = FileUtil.restore([(from: from, to: to)])
            #expect(result.restored == 0 && result.remaining.count == 1)
            #expect(try String(contentsOf: from, encoding: .utf8) == "new")
        }
    }

    @Test func restoreRefusesWhenOriginalParentBecameASymlink() throws {
        try sandbox { root in
            let fm = FileManager.default
            let elsewhere = root.appendingPathComponent("elsewhere"), parent = root.appendingPathComponent("parent")
            let to = root.appendingPathComponent("trash/a.txt")
            try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: parent, withDestinationURL: elsewhere)
            try Data("a".utf8).write(to: to)
            let result = FileUtil.restore([(from: parent.appendingPathComponent("a.txt"), to: to)])
            #expect(result.restored == 0 && result.remaining.count == 1)
            #expect(!fm.fileExists(atPath: elsewhere.appendingPathComponent("a.txt").path))
        }
    }
}
