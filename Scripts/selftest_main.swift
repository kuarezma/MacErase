import Foundation
// Read-only check of the scanner against the real system. Nothing is deleted.
let apps = AppScanner.installedApps()
print("apps:", apps.count)
let ids = apps.map(\.bundleID)
var withLeft = 0
for app in apps.prefix(400) {
    let found = AppScanner.findLeftovers(for: app, allBundleIDs: ids).filter { $0.category != .app }
    if !found.isEmpty { withLeft += 1 }
    if ["Safari", "Google Chrome", "Xcode", "Visual Studio Code", "WhatsApp"].contains(app.name) || app.name.hasPrefix("Chrome") {
        print("\n\(app.name) [\(app.bundleID)] -> \(found.count) leftovers")
        for l in found.prefix(8) { print("  \(l.category.title): \(l.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))\(l.needsAdmin ? " [admin]" : "")") }
    }
}
print("\napps with leftovers:", withLeft)
let t0 = Date(); _ = FileUtil.size(of: URL(fileURLWithPath: "/Applications/Utilities")); print("size ok in", String(format: "%.2fs", Date().timeIntervalSince(t0)))
