import Foundation
import Testing
@testable import MacErase

/// Files are written under a temp root; sizes are real bytes so allocated size is predictable enough.
private func withTree(_ files: [String: Int], _ body: (URL) throws -> Void) throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MacEraseLarge-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    for (path, bytes) in files {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: url)
    }
    try body(root)
}

private let big = 256 * 1024
private let threshold: Int64 = 128 * 1024

struct LargeFilesTests {
    @Test func findsBigFilesOnly() throws {
        try withTree(["movie.mov": big, "notes.txt": 10, "Nested/archive.zip": big]) { root in
            let found = LargeFilesModel.find(minBytes: threshold, roots: [root]).map(\.url.lastPathComponent)
            #expect(Set(found) == ["movie.mov", "archive.zip"])
        }
    }

    @Test func skipsDependencyAndBuildFolders() throws {
        try withTree([
            "web/node_modules/pkg/bin.node": big, "ios/Pods/Lib/lib.a": big, "py/venv/lib/x.so": big,
            "web/keep.mp4": big,
        ]) { root in
            let found = LargeFilesModel.find(minBytes: threshold, roots: [root]).map(\.url.lastPathComponent)
            #expect(found == ["keep.mp4"])
        }
    }

    @Test func skipsGitWorkingTreesIncludingWorktreesWithAGitFile() throws {
        try withTree([
            "repo/.git/HEAD": 10, "repo/assets/texture.psd": big,
            "worktree/.git": 10, "worktree/data.bin": big,
            "loose/video.mov": big,
        ]) { root in
            let found = LargeFilesModel.find(minBytes: threshold, roots: [root]).map(\.url.lastPathComponent)
            #expect(found == ["video.mov"])
        }
    }

    @Test func aRootThatIsItselfARepositoryIsSkipped() throws {
        try withTree([".git/HEAD": 10, "big.bin": big]) { root in
            #expect(LargeFilesModel.find(minBytes: threshold, roots: [root]).isEmpty)
        }
    }

    @Test func hiddenFilesAreNeverOffered() throws {
        try withTree([".secret/big.bin": big, ".big.bin": big]) { root in
            #expect(LargeFilesModel.find(minBytes: threshold, roots: [root]).isEmpty)
        }
    }

    @Test func resultsAreSortedBySizeAndCapped() throws {
        try withTree(["a.bin": big, "b.bin": big * 3, "c.bin": big * 2]) { root in
            let found = LargeFilesModel.find(minBytes: threshold, roots: [root], limit: 2)
            #expect(found.map(\.url.lastPathComponent) == ["b.bin", "c.bin"])
        }
    }

    @Test func symlinkToABigFileIsNotListed() throws {
        try withTree(["real/big.bin": big]) { root in
            let scanned = root.appendingPathComponent("scanned")
            try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: scanned.appendingPathComponent("link.bin"),
                                                       withDestinationURL: root.appendingPathComponent("real/big.bin"))
            #expect(LargeFilesModel.find(minBytes: threshold, roots: [scanned]).isEmpty)
        }
    }
}
