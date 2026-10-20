import Foundation

enum CleanKind: String, CaseIterable, Identifiable {
    case caches, logs, xcode, devTools, iosBackups, trash
    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: String(localized: "Uygulama Önbellekleri")
        case .logs: String(localized: "Günlük Dosyaları")
        case .xcode: String(localized: "Xcode Geçici Dosyaları")
        case .devTools: String(localized: "Geliştirici Önbellekleri")
        case .iosBackups: String(localized: "iOS Yedekleri")
        case .trash: String(localized: "Çöp Kutusu")
        }
    }

    var subtitle: String {
        switch self {
        case .caches: String(localized: "Uygulamaların yeniden üretebildiği geçici veriler")
        case .logs: String(localized: "Eski günlük ve tanılama kayıtları")
        case .xcode: String(localized: "DerivedData, cihaz destek dosyaları, simülatör önbelleği")
        case .devTools: String(localized: "npm, Gradle ve ~/.cache önbellekleri")
        case .iosBackups: String(localized: "iPhone/iPad yedekleri. Geri dönüşü yok, dikkatli seç")
        case .trash: String(localized: "Çöpteki dosyalar kalıcı olarak silinir")
        }
    }

    var symbol: String {
        switch self {
        case .caches: "memorychip"
        case .logs: "doc.text"
        case .xcode: "hammer"
        case .devTools: "terminal"
        case .iosBackups: "iphone"
        case .trash: "trash"
        }
    }

    /// Only regenerable caches are on by default; anything personal or expensive to rebuild is opt-in.
    var defaultOn: Bool { self == .caches || self == .logs || self == .xcode }

    var roots: [URL] {
        let home = FileUtil.home, lib = FileUtil.library
        switch self {
        case .caches: return [lib.appendingPathComponent("Caches")]
        case .logs: return [lib.appendingPathComponent("Logs")]
        case .xcode:
            return ["Developer/Xcode/DerivedData", "Developer/Xcode/iOS DeviceSupport",
                    "Developer/CoreSimulator/Caches"].map { lib.appendingPathComponent($0) }
        case .devTools:
            return [home.appendingPathComponent(".npm/_cacache"), home.appendingPathComponent(".gradle/caches"),
                    home.appendingPathComponent(".cache")]
        case .iosBackups: return [lib.appendingPathComponent("Application Support/MobileSync/Backup")]
        case .trash: return [home.appendingPathComponent(".Trash")]
        }
    }

    /// Items in the categories whose root *is* the cache (npm, gradle) are cleaned as a whole.
    func candidates() -> [URL] {
        switch self {
        case .devTools:
            let fm = FileManager.default
            var out: [URL] = []
            for root in roots where fm.fileExists(atPath: root.path) && !FileUtil.isRedirected(root) {
                if root.lastPathComponent == ".cache" { out += FileUtil.children(of: root) } else { out.append(root) }
            }
            return out
        case .caches:
            guard !FileUtil.isRedirected(roots[0]) else { return [] }
            return FileUtil.children(of: roots[0]).filter {
                !$0.lastPathComponent.hasPrefix("com.apple.") && !$0.lastPathComponent.hasPrefix("local.macerase")
            }
        default:
            return roots.filter { !FileUtil.isRedirected($0) }.flatMap { FileUtil.children(of: $0) }
        }
    }
}

struct CleanItem: Identifiable, Hashable {
    let url: URL
    var size: Int64
    var id: URL { url }
}

struct CleanCategory: Identifiable {
    let kind: CleanKind
    var items: [CleanItem]
    var enabled: Bool
    var id: String { kind.rawValue }
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

@MainActor
final class CleanerModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, ready, cleaning, done(freed: Int64, failed: Int) }

    @Published var phase: Phase = .idle
    @Published var categories: [CleanCategory] = []
    @Published var excluded: Set<URL> = []
    @Published var trashNeedsAccess = false

    private var scanTask: Task<Void, Never>?

    var selectedTotal: Int64 {
        categories.filter(\.enabled).reduce(0) { sum, c in
            sum + c.items.filter { !excluded.contains($0.url) }.reduce(0) { $0 + $1.size }
        }
    }

    func scan() {
        scanTask?.cancel()
        phase = .scanning
        categories = []
        excluded = []
        trashNeedsAccess = false
        scanTask = Task { [weak self] in
            for kind in CleanKind.allCases {
                if Task.isCancelled { return }
                let urls = await Task.detached(priority: .utility) { kind.candidates() }.value
                let sizes = await FileUtil.sizes(of: urls)
                let items = urls.map { CleanItem(url: $0, size: sizes[$0] ?? 0) }
                    .filter { $0.size > 0 }
                    .sorted { $0.size > $1.size }
                guard let self else { return }
                if kind == .trash, items.isEmpty,
                   (try? FileManager.default.contentsOfDirectory(atPath: FileUtil.home.appendingPathComponent(".Trash").path)) == nil {
                    self.trashNeedsAccess = true
                }
                self.categories.append(CleanCategory(kind: kind, items: items, enabled: kind.defaultOn && !items.isEmpty))
            }
            self?.phase = .ready
        }
    }

    func clean() {
        let targets = categories.filter(\.enabled).flatMap { $0.items.filter { !excluded.contains($0.url) } }
        guard !targets.isEmpty else { return }
        phase = .cleaning
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> (Int64, Int) in
                var freed: Int64 = 0, failed = 0
                for item in targets {
                    if FileUtil.remove([item.url]).failed.isEmpty { freed += item.size } else { failed += 1 }
                }
                return (freed, failed)
            }.value
            self?.phase = .done(freed: result.0, failed: result.1)
            self?.categories = []
        }
    }

    func toggle(_ kind: CleanKind, on: Bool) {
        guard let i = categories.firstIndex(where: { $0.kind == kind }) else { return }
        categories[i].enabled = on
    }

    func toggleItem(_ url: URL) {
        if excluded.contains(url) { excluded.remove(url) } else { excluded.insert(url) }
    }
}
