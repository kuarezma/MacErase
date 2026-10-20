import AppKit
import Foundation

enum Fmt {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func bytes(_ n: Int64) -> String { n <= 0 ? "0 KB" : formatter.string(fromByteCount: n) }
    static func rate(_ n: Double) -> String { bytes(Int64(n)) + "/s" }
}

enum FileUtil {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var library: URL { home.appendingPathComponent("Library") }

    /// Allocated size on disk of a file or a whole directory tree. Symlinks are not followed.
    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        guard isDir.boolValue else { return fileSize(url) }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                         errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in walker {
            if Task.isCancelled { break }
            total += fileSize(item)
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]),
              v.isRegularFile == true else { return 0 }
        return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
    }

    /// True when the path (or any parent) is a symlink, so deleting "inside" it could hit files elsewhere.
    static func isRedirected(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().path != url.standardizedFileURL.path
    }

    static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Sizes for many URLs, computed with bounded parallelism so the CPU (and battery) are not hammered.
    static func sizes(of urls: [URL], maxConcurrent: Int = 3,
                      progress: (@Sendable (URL, Int64) -> Void)? = nil) async -> [URL: Int64] {
        await withTaskGroup(of: (URL, Int64).self) { group in
            var result: [URL: Int64] = [:]
            var iterator = urls.makeIterator()
            func addNext() {
                guard let next = iterator.next() else { return }
                group.addTask(priority: .utility) {
                    if Task.isCancelled { return (next, 0) }
                    return (next, FileUtil.size(of: next))
                }
            }
            for _ in 0..<maxConcurrent { addNext() }
            while let (url, size) = await group.next() {
                result[url] = size
                progress?(url, size)
                addNext()
            }
            return result
        }
    }

    /// Moves items to the Trash (reversible). Returns what succeeded and what failed.
    @MainActor
    static func recycle(_ urls: [URL]) async -> (done: [URL], failed: [URL], moves: [(from: URL, to: URL)]) {
        guard !urls.isEmpty else { return ([], [], []) }
        return await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle(urls) { trashed, _ in
                let ok = Set(trashed.keys.map { $0.path })
                cont.resume(returning: (urls.filter { ok.contains($0.path) }, urls.filter { !ok.contains($0.path) },
                                        trashed.map { (from: $0.key, to: $0.value) }))
            }
        }
    }

    /// Puts trashed items back where they came from. Items that cannot be restored (target exists, parent now
    /// redirected by a symlink, item gone) are returned so the caller can report or retry them.
    static func restore(_ moves: [(from: URL, to: URL)]) -> (restored: Int, remaining: [(from: URL, to: URL)]) {
        let fm = FileManager.default
        var restored = 0
        var remaining: [(from: URL, to: URL)] = []
        for move in moves {
            let parent = move.from.deletingLastPathComponent()
            guard fm.fileExists(atPath: move.to.path), !fm.fileExists(atPath: move.from.path),
                  !isRedirected(parent) else { remaining.append(move); continue }
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if !isRedirected(parent), (try? fm.moveItem(at: move.to, to: move.from)) != nil { restored += 1 } else { remaining.append(move) }
        }
        return (restored, remaining)
    }

    /// Permanently deletes. Used only for caches/logs/trash the user explicitly selected.
    static func remove(_ urls: [URL]) -> (done: [URL], failed: [URL]) {
        var done: [URL] = [], failed: [URL] = []
        for url in urls {
            // A symlinked parent could redirect the delete somewhere the user never selected.
            guard !isRedirected(url.deletingLastPathComponent()) else { failed.append(url); continue }
            do { try FileManager.default.removeItem(at: url); done.append(url) } catch { failed.append(url) }
        }
        return (done, failed)
    }

    /// Only an app bundle in /Applications or an item *inside* a /Library subfolder may go through `rm -rf` as root;
    /// a top-level folder such as /Library/LaunchDaemons or /Applications itself never qualifies.
    static func isAdminRemovable(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.hasPrefix("/"), !parts.contains(".."), !parts.contains("."), !path.hasSuffix("/"),
              !parts.dropFirst().contains(""), !path.contains("\n") else { return false }
        let url = URL(fileURLWithPath: path)
        if isRedirected(url.deletingLastPathComponent()) { return false }
        if parts[1] == "Applications" { return url.pathExtension == "app" && parts.count >= 3 }
        return parts[1] == "Library" && parts.count >= 4
    }

    /// Permanently removes (not Trash) root-owned paths under /Library or /Applications after the user authenticates through the system prompt.
    @MainActor
    static func adminRemove(_ paths: [String]) -> Set<String> {
        let safe = paths.filter(isAdminRemovable)
        guard !safe.isEmpty else { return [] }
        let shell = "rm -rf " + safe.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        // Trust the filesystem, not the script result: report only what is really gone.
        return Set(safe.filter { !FileManager.default.fileExists(atPath: $0) })
    }

    static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
