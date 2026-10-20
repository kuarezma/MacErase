import Foundation

struct StartupItem: Identifiable, Hashable {
    let url: URL
    let label: String
    let program: String
    let isSystemWide: Bool
    let isDaemon: Bool
    var id: URL { url }
    var removable: Bool { !isSystemWide && FileManager.default.isDeletableFile(atPath: url.path) }
}

@MainActor
final class StartupModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var message: String?
    @Published var loaded = false

    func load() {
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) { Self.scan() }.value
            self?.items = found
            self?.loaded = true
        }
    }

    func remove(_ item: StartupItem) {
        // System-wide agents/daemons belong to root; only the user's own plists may be unloaded and trashed.
        guard item.removable, item.url.pathExtension == "plist" else { return }
        Task { [weak self] in
            // Best effort: stop the job first so it does not respawn until next login.
            let path = item.url.path
            await Task.detached(priority: .utility) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                p.arguments = ["bootout", "gui/\(getuid())", path]
                p.standardError = FileHandle.nullDevice
                p.standardOutput = FileHandle.nullDevice
                try? p.run()
                p.waitUntilExit()
            }.value
            let result = await FileUtil.recycle([item.url])
            guard let self else { return }
            if result.failed.isEmpty {
                self.items.removeAll { $0.url == item.url }
                self.message = String(localized: "\(item.label) başlangıçtan kaldırıldı (çöpte, geri alınabilir).")
            } else {
                self.message = String(localized: "\(item.label) kaldırılamadı.")
            }
        }
    }

    nonisolated private static func scan() -> [StartupItem] {
        let dirs: [(URL, Bool, Bool)] = [
            (FileUtil.library.appendingPathComponent("LaunchAgents"), false, false),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), true, false),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), true, true),
        ]
        var out: [StartupItem] = []
        for (dir, system, daemon) in dirs {
            for url in FileUtil.children(of: dir) where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { continue }
                let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first ?? ""
                out.append(StartupItem(url: url, label: label, program: program, isSystemWide: system, isDaemon: daemon))
            }
        }
        return out.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}
