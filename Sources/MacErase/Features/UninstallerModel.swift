import AppKit
import Foundation

enum AppSort: String, CaseIterable, Identifiable {
    case name = "Ad", size = "Boyut"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: String(localized: "Ad")
        case .size: String(localized: "Boyut")
        }
    }
}

@MainActor
final class UninstallerModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var sizes: [URL: Int64] = [:]
    @Published var loading = false
    @Published var selected: InstalledApp?
    @Published var leftovers: [Leftover] = []
    @Published var checked: Set<URL> = []
    @Published var scanningLeftovers = false
    @Published var working = false
    @Published var message: String?
    /// The detail pane shows `message` as a warning instead of a "Done" screen when this is set.
    @Published var messageIsError = false
    @Published var query = ""
    @Published var sort: AppSort = .name

    @Published var canUndo = false
    private var loadedOnce = false
    private var lastMoves: [(from: URL, to: URL)] = []
    private var sizeTask: Task<Void, Never>?
    private var leftoverTask: Task<Void, Never>?

    var visibleApps: [InstalledApp] {
        let filtered = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
        guard sort == .size else { return filtered }
        return filtered.sorted { (sizes[$0.url] ?? 0) > (sizes[$1.url] ?? 0) }
    }

    var selectedBytes: Int64 { leftovers.filter { checked.contains($0.url) }.reduce(0) { $0 + ($1.size ?? 0) } }

    func load() {
        guard !loading, !loadedOnce else { return }
        loadedOnce = true
        loading = true
        sizeTask?.cancel()
        sizeTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { AppScanner.installedApps() }.value
            guard let self, !Task.isCancelled else { return }
            self.apps = found
            self.loading = false
            // One batched publish at the end keeps the list from re-rendering once per app.
            if let name = ProcessInfo.processInfo.environment["MACERASE_SELECT"],
               let app = found.first(where: { $0.name == name }) { self.select(app) }  // screenshot/debug hook
            let measured = await FileUtil.sizes(of: found.map(\.url))
            // A cancelled (superseded) scan returns partial sizes; never publish them.
            guard !Task.isCancelled else { return }
            self.sizes = measured
        }
    }

    func reload() {
        loadedOnce = false
        select(nil)
        load()
    }

    /// Opens an .app that was dropped on the window, even if it lives outside /Applications.
    func open(url: URL) {
        if url.pathExtension == "app", AppScanner.isSystemApp(url) {
            report(String(localized: "macOS ile gelen uygulamalar kaldırılamaz."), isError: true)
            return
        }
        guard !working else { return }
        guard let app = AppScanner.app(at: url) else { report(String(localized: "Bu bir uygulama değil."), isError: true); return }
        // A dropped bundle that claims the id of a different installed app could make us touch that app's data.
        if !app.bundleID.isEmpty,
           let clash = apps.first(where: { $0.bundleID == app.bundleID && $0.url.resolvingSymlinksInPath() != app.url.resolvingSymlinksInPath() }) {
            report(String(localized: "Aynı kimliğe sahip başka bir uygulama zaten kurulu: \(clash.name). Önce onu seç."), isError: true)
            return
        }
        if !apps.contains(where: { $0.url == app.url }) {
            apps.append(app)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        select(app)
    }

    func undo() {
        guard !working else { return }
        let result = FileUtil.restore(lastMoves)
        lastMoves = result.remaining
        canUndo = !result.remaining.isEmpty
        reload()
        report(result.remaining.isEmpty
               ? String(localized: "\(result.restored) öğe geri konuldu.")
               : String(localized: "\(result.restored) öğe geri konuldu, \(result.remaining.count) öğe geri konamadı (aynı ad var ya da klasör değişti)."),
               isError: !result.remaining.isEmpty)
    }

    private func report(_ text: String, isError: Bool = false) {
        message = text
        messageIsError = isError
    }

    func select(_ app: InstalledApp?) {
        // Switching apps mid-uninstall would mix the running job's results into another app's list.
        guard !working else { return }
        leftoverTask?.cancel()
        selected = app
        leftovers = []
        checked = []
        message = nil
        messageIsError = false
        scanningLeftovers = false
        guard let app else { return }
        scanningLeftovers = true
        let ids = apps.map(\.bundleID)
        leftoverTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                AppScanner.findLeftovers(for: app, allBundleIDs: ids)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.leftovers = found
            self.checked = Set(found.filter { !$0.needsAdmin }.map(\.url))
            let measured = await FileUtil.sizes(of: found.map(\.url))
            guard !Task.isCancelled else { return }
            self.leftovers = self.leftovers.map { var l = $0; l.size = measured[l.url] ?? 0; return l }
            self.scanningLeftovers = false
        }
    }

    func toggle(_ url: URL) {
        if checked.contains(url) { checked.remove(url) } else { checked.insert(url) }
    }

    func uninstall() {
        guard let app = selected, !working else { return }
        let chosen = leftovers.filter { checked.contains($0.url) }
        guard !chosen.isEmpty else { return }
        working = true
        let removedAppBundle = chosen.contains { $0.category == .app }
        Task { [weak self] in
            guard let self else { return }
            guard await Self.quit(app) else {
                self.working = false
                self.report(String(localized: "\(app.name) kapanmadı. Kaydedilmemiş verin olabilir; önce uygulamayı kendin kapatıp tekrar dene."),
                            isError: true)
                return
            }
            let userItems = chosen.filter { !$0.needsAdmin }
            let adminItems = chosen.filter(\.needsAdmin)
            let trashed = await FileUtil.recycle(userItems.map(\.url))
            let adminDone = adminItems.isEmpty ? [] : FileUtil.adminRemove(adminItems.map(\.url.path))

            self.lastMoves = trashed.moves
            self.canUndo = !trashed.moves.isEmpty
            let doneURLs = Set(trashed.done.map(\.path)).union(adminDone)
            let freed = chosen.filter { doneURLs.contains($0.url.path) }.reduce(0) { $0 + ($1.size ?? 0) }
            let failed = chosen.count - doneURLs.count
            self.working = false
            self.sizes.removeValue(forKey: app.url)
            if removedAppBundle, doneURLs.contains(app.url.path) {
                self.apps.removeAll { $0.url == app.url }
                self.select(nil)
            } else {
                self.leftovers.removeAll { doneURLs.contains($0.url.path) }
                self.checked.subtract(chosen.filter { doneURLs.contains($0.url.path) }.map(\.url))
            }
            let permanent = adminDone.isEmpty ? "" : String(localized: " Yönetici öğeleri (\(adminDone.count)) kalıcı silindi.")
            self.messageIsError = false
            self.message = failed == 0
                ? String(localized: "\(app.name) kaldırıldı. \(Fmt.bytes(freed)) boşaldı.") + (adminDone.isEmpty ? String(localized: " Çöp kutusundan geri alınabilir.") : permanent)
                : String(localized: "\(doneURLs.count) öğe kaldırıldı, \(failed) öğe kaldırılamadı (izin gerekebilir).")
        }
    }

    /// Asks the app to quit and waits. Never force-kills: that could discard unsaved work.
    private static func quit(_ app: InstalledApp) async -> Bool {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.path == app.url.standardizedFileURL.path
                || (!app.bundleID.isEmpty && $0.bundleIdentifier == app.bundleID)
        }
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        for _ in 0..<40 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(150))
        }
        return running.allSatisfy(\.isTerminated)
    }
}
