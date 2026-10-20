import Foundation

struct LargeFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date?
    var id: URL { url }
}

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var checked: Set<URL> = []
    @Published var scanning = false
    @Published var minMB = 100
    @Published var message: String?

    private var task: Task<Void, Never>?

    var selectedBytes: Int64 { files.filter { checked.contains($0.url) }.reduce(0) { $0 + $1.size } }

    func scan() {
        task?.cancel()
        scanning = true
        files = []
        checked = []
        message = nil
        let threshold = Int64(minMB) * 1_000_000
        task = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { Self.find(minBytes: threshold) }.value
            guard let self, !Task.isCancelled else { return }
            self.files = found
            self.scanning = false
        }
    }

    func toggle(_ url: URL) {
        if checked.contains(url) { checked.remove(url) } else { checked.insert(url) }
    }

    func trashSelected() {
        let urls = files.filter { checked.contains($0.url) }.map(\.url)
        guard !urls.isEmpty else { return }
        Task { [weak self] in
            let result = await FileUtil.recycle(urls)
            guard let self else { return }
            let gone = Set(result.done.map(\.path))
            let freed = self.files.filter { gone.contains($0.url.path) }.reduce(0) { $0 + $1.size }
            self.files.removeAll { gone.contains($0.url.path) }
            self.checked.subtract(result.done)
            self.message = String(localized: "\(result.done.count) dosya çöpe taşındı (\(Fmt.bytes(freed))). Geri alınabilir.")
                + (result.failed.isEmpty ? "" : String(localized: " \(result.failed.count) dosya taşınamadı."))
        }
    }

    nonisolated private static func find(minBytes: Int64) -> [LargeFile] {
        let fm = FileManager.default
        let roots = ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures", "Developer", "Projects"]
            .map { FileUtil.home.appendingPathComponent($0) }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey, .contentModificationDateKey]
        var out: [LargeFile] = []
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                if Task.isCancelled { return out }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let size = v.totalFileAllocatedSize, Int64(size) >= minBytes else { continue }
                out.append(LargeFile(url: url, size: Int64(size), modified: v.contentModificationDate))
            }
        }
        return Array(out.sorted { $0.size > $1.size }.prefix(200))
    }
}
