import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, apps, clean, large, startup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Genel Bakış")
        case .apps: String(localized: "Uygulamalar")
        case .clean: String(localized: "Akıllı Temizlik")
        case .large: String(localized: "Büyük Dosyalar")
        case .startup: String(localized: "Başlangıç Öğeleri")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .apps: "square.grid.2x2"
        case .clean: "sparkles"
        case .large: "doc.zipper"
        case .startup: "power"
        }
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemMonitor.self) private var monitor
    @State private var selection: SidebarItem? = SidebarItem(rawValue: ProcessInfo.processInfo.environment["MACERASE_SECTION"] ?? "") ?? .overview
    @StateObject private var cleaner = CleanerModel()
    @StateObject private var large = LargeFilesModel()
    @StateObject private var uninstaller = UninstallerModel()
    @StateObject private var startup = StartupModel()
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .background {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.offset) { index, item in
                    Button("") { selection = item }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                        .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                }
            }
        } detail: {
            // ⌘1…⌘5 switch sections.
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView { selection = $0 }
                case .apps: UninstallerView(model: uninstaller)
                case .clean: CleanerView(model: cleaner)
                case .large: LargeFilesView(model: large)
                case .startup: StartupView(model: startup)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { WidgetsBar() }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let app = urls.first(where: { $0.pathExtension == "app" }) else { return false }
                selection = .apps
                uninstaller.open(url: app)
                return true
            } isTargeted: { dropTargeted = $0 }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.brand, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .background(Color.brandA.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { Label("Kaldırmak için uygulamayı bırak", systemImage: "trash").font(.title3.weight(.semibold)) }
                        .padding(10).allowsHitTesting(false)
                }
            }
        }
    }
}
