import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { SystemMonitor.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MainActor.assumeIsolated { AppSettings.shared.showMenuBar }
    }
}

@main
struct MacEraseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let settings = AppSettings.shared
    private let monitor = SystemMonitor.shared

    var body: some Scene {
        Window("MacErase", id: "main") {
            RootView()
                .environment(settings)
                .environment(monitor)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 700)

        MenuBarExtra(isInserted: Binding(get: { settings.showMenuBar }, set: { settings.showMenuBar = $0 })) {
            MenuBarPanel()
                .environment(settings)
                .environment(monitor)
        } label: {
            Image(systemName: "bolt.shield.fill")
            if settings.menuBarShowsCPU { Text(verbatim: "\(Int(monitor.cpu))%") }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(settings)
        }
    }
}

private struct MenuBarPanel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "MacErase").font(.headline)
            ForEach(WidgetKind.allCases.filter { $0 != .clock }) { kind in
                WidgetPill(kind: kind)
            }
            Divider()
            Button("Pencereyi Aç") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Button("Çık") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
    }
}
