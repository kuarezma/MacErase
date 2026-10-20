import Foundation
import Testing
@testable import MacErase

/// A throwaway "home" under the temp dir: every CleanKind root is resolved inside it, nothing real is touched.
private func withFakeHome(_ files: [String], _ body: (URL) throws -> Void) throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MacEraseHome-\(UUID().uuidString)")
    try fm.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: home) }
    for file in files {
        let url = home.appendingPathComponent(file)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }
    try body(home)
}

private func names(_ urls: [URL]) -> Set<String> { Set(urls.map(\.lastPathComponent)) }

struct CleanKindTests {
    @Test func everyRootStaysInsideTheGivenHome() throws {
        try withFakeHome([]) { home in
            for kind in CleanKind.allCases {
                #expect(kind.roots(home: home).allSatisfy { $0.path.hasPrefix(home.path + "/") })
            }
        }
    }

    @Test func onlyRegenerableCategoriesAreOnByDefault() {
        #expect(Set(CleanKind.allCases.filter(\.defaultOn)) == [.caches, .logs, .xcode])
    }

    @Test func appCachesSkipAppleAndOwnFolders() throws {
        try withFakeHome([
            "Library/Caches/com.vendor.tool/a", "Library/Caches/Homebrew/b",
            "Library/Caches/com.apple.Safari/c", "Library/Caches/local.macerase.app/d",
        ]) { home in
            #expect(names(CleanKind.caches.candidates(home: home)) == ["com.vendor.tool", "Homebrew"])
        }
    }

    @Test func symlinkedCachesRootIsIgnored() throws {
        try withFakeHome(["elsewhere/precious/file"]) { home in
            let lib = home.appendingPathComponent("Library")
            try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: lib.appendingPathComponent("Caches"),
                                                       withDestinationURL: home.appendingPathComponent("elsewhere"))
            #expect(CleanKind.caches.candidates(home: home).isEmpty)
            #expect(CleanKind.logs.candidates(home: home).isEmpty)
        }
    }

    @Test func devToolsTakesWholeCacheRootsButChildrenOfDotCache() throws {
        try withFakeHome([
            ".npm/_cacache/index", ".npm/config-keep", ".gradle/caches/x", ".gradle/gradle.properties",
            ".cache/pip/y", ".cache/uv/z",
        ]) { home in
            // Directory listings may report /private/var for /var, so compare the home-relative tail only.
            let found = CleanKind.devTools.candidates(home: home)
                .map { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" }
            #expect(Set(found) == [".npm/_cacache", ".gradle/caches", ".cache/pip", ".cache/uv"])
        }
    }

    @Test func symlinkedDotCacheIsNotEntered() throws {
        try withFakeHome(["external/models/big"]) { home in
            try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".cache"),
                                                       withDestinationURL: home.appendingPathComponent("external"))
            #expect(CleanKind.devTools.candidates(home: home).isEmpty)
        }
    }

    @Test func xcodeAndTrashListChildrenOfTheirRoots() throws {
        try withFakeHome([
            "Library/Developer/Xcode/DerivedData/App-abc/x", "Library/Developer/Xcode/Archives/keep/x",
            ".Trash/old.zip",
        ]) { home in
            #expect(names(CleanKind.xcode.candidates(home: home)) == ["App-abc"])
            #expect(names(CleanKind.trash.candidates(home: home)) == ["old.zip"])
        }
    }
}
