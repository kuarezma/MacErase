import Foundation
import Testing
@testable import MacErase

/// Builds a fake ~/Library and /Library under a temp dir so nothing real is touched.
private func withFakeLibraries(_ entries: [String], _ body: (_ lib: URL, _ sys: URL) throws -> Void) throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MacEraseScan-\(UUID().uuidString)")
    let lib = root.appendingPathComponent("Library"), sys = root.appendingPathComponent("SysLibrary")
    try fm.createDirectory(at: lib, withIntermediateDirectories: true)
    try fm.createDirectory(at: sys, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    for entry in entries {
        let url = (entry.hasPrefix("SYS/") ? sys : lib).appendingPathComponent(entry.replacingOccurrences(of: "SYS/", with: ""))
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }
    try body(lib, sys)
}

private func app(_ name: String, _ id: String) -> InstalledApp {
    InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: id, version: "1")
}

private func leftoverNames(_ app: InstalledApp, ids: [String], lib: URL, sys: URL) -> Set<String> {
    Set(AppScanner.findLeftovers(for: app, allBundleIDs: ids, library: lib, systemLibrary: sys)
        .filter { $0.category != .app }.map { $0.url.lastPathComponent })
}

struct AppScannerTests {
    @Test func matchesExactAndOneWordHelperButNotDeeperProducts() {
        let id = "com.google.chrome"
        #expect(AppScanner.matchesID("com.google.chrome", id: id, otherIDs: []))
        #expect(AppScanner.matchesID("com.google.chrome.helper", id: id, otherIDs: []))
        #expect(!AppScanner.matchesID("com.google.chrome.for.testing", id: id, otherIDs: []))
        #expect(!AppScanner.matchesID("com.google.chrome.app.abcdef", id: id, otherIDs: []))
    }

    @Test func doesNotStealDataOfALongerInstalledId() {
        let others = ["com.foo.bar", "com.foo.bar.pro"]
        #expect(!AppScanner.matchesID("com.foo.bar.pro", id: "com.foo.bar", otherIDs: others))
        #expect(AppScanner.matchesID("com.foo.bar.pro", id: "com.foo.bar.pro", otherIDs: others))
    }

    @Test func groupContainerSuffixNeedsGroupOrTeamIdPrefix() {
        let id = "com.example.editor"
        #expect(AppScanner.matchesID("group.com.example.editor", id: id, otherIDs: []))
        #expect(AppScanner.matchesID("abcde12345.com.example.editor", id: id, otherIDs: []))
        #expect(!AppScanner.matchesID("org.vendor.com.example.editor", id: id, otherIDs: []))
    }

    @Test func stemStripsOnlyKnownExtensions() {
        #expect(AppScanner.stem("com.foo.Bar.plist") == "com.foo.bar")
        #expect(AppScanner.stem("com.foo.Bar.savedState") == "com.foo.bar")
        #expect(AppScanner.stem("com.foo.Bar.helper") == "com.foo.bar.helper")
    }

    @Test func findsOwnLeftoversAndIgnoresOthers() throws {
        try withFakeLibraries([
            "Caches/com.acme.tool/data", "Preferences/com.acme.tool.plist",
            "Application Support/Tool/state", "Saved Application State/com.acme.tool.savedState/w",
            "Caches/com.other.app/data", "Preferences/com.acme.toolbox.plist", "SYS/LaunchDaemons/com.acme.tool.helper.plist",
        ]) { lib, sys in
            let names = leftoverNames(app("Tool", "com.acme.tool"), ids: ["com.acme.tool", "com.other.app"], lib: lib, sys: sys)
            #expect(names == ["com.acme.tool", "com.acme.tool.plist", "Tool", "com.acme.tool.savedState", "com.acme.tool.helper.plist"])
        }
    }

    @Test func sharedVendorFolderIsNotClaimedByName() throws {
        try withFakeLibraries(["Application Support/Google/Chrome/x"]) { lib, sys in
            let google = app("Google", "com.acme.google")
            let ids = ["com.acme.google", "com.google.chrome"]
            #expect(leftoverNames(google, ids: ids, lib: lib, sys: sys).isEmpty)
        }
    }

    @Test func shortNamesAreNeverMatchedByName() throws {
        try withFakeLibraries(["Application Support/Go/x"]) { lib, sys in
            #expect(leftoverNames(app("Go", "com.acme.go"), ids: ["com.acme.go"], lib: lib, sys: sys).isEmpty)
        }
    }

    @Test func appBundleIsAlwaysFirstCategory() throws {
        try withFakeLibraries([]) { lib, sys in
            let found = AppScanner.findLeftovers(for: app("Tool", "com.acme.tool"), allBundleIDs: [], library: lib, systemLibrary: sys)
            #expect(found.first?.category == .app)
        }
    }

    @Test func parsesAnAppBundleAndRejectsOthers() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MacEraseApp-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let contents = root.appendingPathComponent("Demo.app/Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.acme.demo", "CFBundleName": "Demo",
                                    "CFBundleShortVersionString": "2.1", "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        let parsed = AppScanner.app(at: root.appendingPathComponent("Demo.app"))
        #expect(parsed?.bundleID == "com.acme.demo" && parsed?.version == "2.1")
        #expect(AppScanner.app(at: root.appendingPathComponent("notes.txt")) == nil)
    }
}
