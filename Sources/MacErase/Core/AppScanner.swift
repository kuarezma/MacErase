import Foundation

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    var id: URL { url }
}

enum LeftoverCategory: Int, CaseIterable, Comparable {
    case app, support, caches, preferences, containers, logs, savedState, launchItems

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .app: String(localized: "Uygulama")
        case .support: String(localized: "Uygulama Verileri")
        case .caches: String(localized: "Önbellek")
        case .preferences: String(localized: "Tercihler")
        case .containers: String(localized: "Konteynerler")
        case .logs: String(localized: "Günlükler")
        case .savedState: String(localized: "Kayıtlı Durum")
        case .launchItems: String(localized: "Başlangıç Öğeleri")
        }
    }

    var symbol: String {
        switch self {
        case .app: "app.fill"
        case .support: "folder.fill"
        case .caches: "memorychip"
        case .preferences: "slider.horizontal.3"
        case .containers: "shippingbox.fill"
        case .logs: "doc.text.fill"
        case .savedState: "clock.arrow.circlepath"
        case .launchItems: "power"
        }
    }
}

struct Leftover: Identifiable, Hashable {
    let url: URL
    let category: LeftoverCategory
    var size: Int64?
    let needsAdmin: Bool
    var id: URL { url }
}

enum AppScanner {
    private static let ownBundleID = "local.macerase.app"

    /// Apps that ship with macOS (e.g. /Applications/Safari.app links into a system cryptex) cannot be
    /// removed, but their data folders could still be trashed, so they are never offered.
    static func isSystemApp(_ url: URL) -> Bool {
        let real = url.resolvingSymlinksInPath().path
        return real.hasPrefix("/System/") || real.contains("/Cryptexes/")
    }

    /// Reads an .app bundle. Returns nil for non-bundles, macOS system apps and MacErase itself.
    static func app(at url: URL) -> InstalledApp? {
        guard url.pathExtension == "app", !isSystemApp(url), let bundle = Bundle(url: url) else { return nil }
        let id = bundle.bundleIdentifier ?? ""
        if id == ownBundleID { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(url: url, name: name, bundleID: id,
                            version: (info["CFBundleShortVersionString"] as? String) ?? "")
    }

    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), FileUtil.home.appendingPathComponent("Applications")]
        var apps: [InstalledApp] = []
        var seen = Set<URL>()
        for root in roots {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                if walker.level > 2 { walker.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                walker.skipDescendants()
                let real = url.resolvingSymlinksInPath()
                guard !seen.contains(real), let app = app(at: url) else { continue }
                seen.insert(real)
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct Location {
        let path: String
        let category: LeftoverCategory
        let matchesByName: Bool
    }

    private static func locations(library: URL, system: URL) -> [Location] {
        let lib = library.path, sys = system.path
        return [
            Location(path: "\(lib)/Application Support", category: .support, matchesByName: true),
            Location(path: "\(lib)/Caches", category: .caches, matchesByName: true),
            Location(path: "\(lib)/Preferences", category: .preferences, matchesByName: false),
            Location(path: "\(lib)/Preferences/ByHost", category: .preferences, matchesByName: false),
            Location(path: "\(lib)/Containers", category: .containers, matchesByName: false),
            Location(path: "\(lib)/Group Containers", category: .containers, matchesByName: false),
            Location(path: "\(lib)/Application Scripts", category: .containers, matchesByName: false),
            Location(path: "\(lib)/Logs", category: .logs, matchesByName: true),
            Location(path: "\(lib)/Saved Application State", category: .savedState, matchesByName: false),
            Location(path: "\(lib)/WebKit", category: .support, matchesByName: true),
            Location(path: "\(lib)/HTTPStorages", category: .caches, matchesByName: false),
            Location(path: "\(lib)/Cookies", category: .support, matchesByName: false),
            Location(path: "\(lib)/LaunchAgents", category: .launchItems, matchesByName: false),
            Location(path: "\(sys)/Application Support", category: .support, matchesByName: true),
            Location(path: "\(sys)/Caches", category: .caches, matchesByName: false),
            Location(path: "\(sys)/Preferences", category: .preferences, matchesByName: false),
            Location(path: "\(sys)/LaunchAgents", category: .launchItems, matchesByName: false),
            Location(path: "\(sys)/LaunchDaemons", category: .launchItems, matchesByName: false),
            Location(path: "\(sys)/PrivilegedHelperTools", category: .launchItems, matchesByName: false),
        ]
    }

    private static let knownExtensions: Set<String> = ["plist", "savedstate", "binarycookies", "sfl2", "sfl3"]

    static func stem(_ entry: String) -> String {
        let lower = entry.lowercased()
        let ext = (lower as NSString).pathExtension
        return knownExtensions.contains(ext) ? (lower as NSString).deletingPathExtension : lower
    }

    /// True when `stem` belongs to bundle id `id` and not to a longer, separately installed id (e.g. Chrome vs Chrome Canary).
    static func matchesID(_ stem: String, id: String, otherIDs: [String]) -> Bool {
        guard !id.isEmpty else { return false }
        func owns(_ candidate: String) -> Bool {
            if stem == candidate { return true }
            if stem.hasSuffix("." + candidate) {
                // Only "group.<id>" and "<TEAMID>.<id>" are real group-container names.
                let prefix = stem.dropLast(candidate.count + 1)
                return prefix == "group" || (prefix.count == 10 && prefix.allSatisfy { $0.isLetter || $0.isNumber })
            }
            // "<id>.<one word>" is a helper/storage of this app; deeper suffixes (".app.x", ".for.testing") are other products.
            guard stem.hasPrefix(candidate + ".") else { return false }
            return !stem.dropFirst(candidate.count + 1).contains(".")
        }
        guard owns(id) else { return false }
        return !otherIDs.contains { $0.count > id.count && $0.hasPrefix(id + ".") && owns($0) }
    }

    static func findLeftovers(for app: InstalledApp, allBundleIDs: [String],
                              library: URL = FileUtil.library,
                              systemLibrary: URL = URL(fileURLWithPath: "/Library")) -> [Leftover] {
        let fm = FileManager.default
        let id = app.bundleID.lowercased()
        let name = app.name.lowercased()
        let others = allBundleIDs.map { $0.lowercased() }
        // A name like "Google" is a shared vendor folder when other apps' bundle ids contain it as a segment.
        let nameIsShared = others.contains { $0 != id && $0.split(separator: ".").contains(Substring(name)) }
        var found: [Leftover] = [Leftover(url: app.url, category: .app, needsAdmin: !fm.isDeletableFile(atPath: app.url.path))]

        for loc in locations(library: library, system: systemLibrary) {
            let dir = URL(fileURLWithPath: loc.path)
            for entry in FileUtil.children(of: dir) {
                let entryName = entry.lastPathComponent
                let s = stem(entryName)
                var hit = matchesID(s, id: id, otherIDs: others)
                if !hit, loc.matchesByName, !nameIsShared, name.count >= 3, s == name { hit = true }
                guard hit else { continue }
                found.append(Leftover(url: entry, category: loc.category,
                                      needsAdmin: !fm.isDeletableFile(atPath: entry.path)))
            }
        }
        return found.sorted { ($0.category, $0.url.path) < ($1.category, $1.url.path) }
    }
}
