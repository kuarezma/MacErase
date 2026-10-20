import Foundation
import Testing
@testable import MacErase

// Each test owns a unique directory; symlink destinations also stay inside it.
private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("MacEraseTests-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    try body(root)
}

struct FileUtilTests {
    @Test func missingPathHasZeroSize() throws {
        try withTemporaryDirectory { root in
            #expect(FileUtil.size(of: root.appendingPathComponent("missing")) == 0)
        }
    }

    @Test func emptyDirectoryHasZeroSize() throws {
        try withTemporaryDirectory { root in
            #expect(FileUtil.size(of: root) == 0)
        }
    }

    @Test func directorySizeIncludesNestedAndHiddenFiles() throws {
        try withTemporaryDirectory { root in
            let nested = root.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
            let first = root.appendingPathComponent("first.bin")
            let second = nested.appendingPathComponent(".hidden.bin")
            try Data(repeating: 0x41, count: 16_384).write(to: first)
            try Data(repeating: 0x42, count: 32_768).write(to: second)
            // Allocated sizes vary with the filesystem; do not assume logical byte counts.
            let firstSize = FileUtil.size(of: first)
            let secondSize = FileUtil.size(of: second)
            #expect(firstSize > 0)
            #expect(secondSize > 0)
            #expect(FileUtil.size(of: root) == firstSize + secondSize)
        }
    }

    @Test func directorySizeDoesNotFollowNestedSymlink() throws {
        try withTemporaryDirectory { root in
            let target = root.appendingPathComponent("target", isDirectory: true)
            let scanned = root.appendingPathComponent("scanned", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: false)
            let payload = target.appendingPathComponent("payload.bin")
            try Data(repeating: 0x43, count: 16_384).write(to: payload)
            try FileManager.default.createSymbolicLink(
                at: scanned.appendingPathComponent("linked-directory"), withDestinationURL: target
            )
            #expect(FileUtil.size(of: payload) > 0)
            #expect(FileUtil.size(of: scanned) == 0)
        }
    }

    @Test func ordinaryPathIsNotRedirected() throws {
        try withTemporaryDirectory { root in
            #expect(!FileUtil.isRedirected(root))
        }
    }

    @Test func symlinkAndItsDescendantAreRedirected() throws {
        try withTemporaryDirectory { root in
            let target = root.appendingPathComponent("target", isDirectory: true)
            let link = root.appendingPathComponent("link", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try Data([1]).write(to: target.appendingPathComponent("child"))
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            #expect(FileUtil.isRedirected(link))
            #expect(FileUtil.isRedirected(link.appendingPathComponent("child")))
        }
    }

    @Test func removeReportsSuccessAndFailureWithoutRemovingSibling() throws {
        try withTemporaryDirectory { root in
            let removed = root.appendingPathComponent("removed")
            let preserved = root.appendingPathComponent("preserved")
            let missing = root.appendingPathComponent("missing")
            try Data([1]).write(to: removed)
            try Data([2]).write(to: preserved)
            let result = FileUtil.remove([removed, missing])
            #expect(result.done == [removed])
            #expect(result.failed == [missing])
            #expect(!FileManager.default.fileExists(atPath: removed.path))
            #expect(try Data(contentsOf: preserved) == Data([2]))
        }
    }

    @Test func removeDirectoryDeletesItsContents() throws {
        try withTemporaryDirectory { root in
            let directory = root.appendingPathComponent("removed", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try Data([1]).write(to: directory.appendingPathComponent("child"))
            let result = FileUtil.remove([directory])
            #expect(result.done == [directory])
            #expect(result.failed.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        }
    }

    @Test func removingSymlinkPreservesDestination() throws {
        try withTemporaryDirectory { root in
            let target = root.appendingPathComponent("target")
            let link = root.appendingPathComponent("link")
            try Data([1, 2, 3]).write(to: target)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let result = FileUtil.remove([link])
            #expect(result.done == [link])
            #expect(result.failed.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: link.path))
            #expect(try Data(contentsOf: target) == Data([1, 2, 3]))
        }
    }

    @Test func removingEmptySelectionHasNoResults() {
        let result = FileUtil.remove([])
        #expect(result.done.isEmpty)
        #expect(result.failed.isEmpty)
    }
}
