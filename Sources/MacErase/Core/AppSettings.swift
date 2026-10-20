import Foundation
import Observation
import SwiftUI

enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    case cpu, memory, disk, battery, network, clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: String(localized: "İşlemci")
        case .memory: String(localized: "Bellek")
        case .disk: String(localized: "Disk")
        case .battery: String(localized: "Pil")
        case .network: String(localized: "Ağ")
        case .clock: String(localized: "Saat")
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .network: "arrow.up.arrow.down"
        case .clock: "clock"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: .blue
        case .memory: .purple
        case .disk: .orange
        case .battery: .green
        case .network: .teal
        case .clock: .pink
        }
    }
}

@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()
    @ObservationIgnored private let defaults = UserDefaults.standard

    var order: [WidgetKind] { didSet { save() } }
    var enabled: Set<WidgetKind> { didSet { save() } }
    var showMenuBar: Bool { didSet { save() } }
    var menuBarShowsCPU: Bool { didSet { save() } }
    var sampleInterval: Double { didSet { save() } }
    var confirmBeforeDelete: Bool { didSet { save() } }

    private init() {
        let storedOrder = (defaults.stringArray(forKey: "widgetOrder") ?? []).compactMap(WidgetKind.init(rawValue:))
        order = storedOrder + WidgetKind.allCases.filter { !storedOrder.contains($0) }
        if let stored = defaults.stringArray(forKey: "widgetEnabled") {
            enabled = Set(stored.compactMap(WidgetKind.init(rawValue:)))
        } else {
            enabled = [.cpu, .memory, .battery]
        }
        showMenuBar = defaults.bool(forKey: "showMenuBar")
        menuBarShowsCPU = defaults.object(forKey: "menuBarShowsCPU") as? Bool ?? true
        sampleInterval = defaults.object(forKey: "sampleInterval") as? Double ?? 2
        confirmBeforeDelete = defaults.object(forKey: "confirmBeforeDelete") as? Bool ?? true
    }

    var visibleWidgets: [WidgetKind] { order.filter(enabled.contains) }

    func binding(for kind: WidgetKind) -> Binding<Bool> {
        Binding(get: { self.enabled.contains(kind) },
                set: { on in
                    if on { self.enabled.insert(kind) } else { self.enabled.remove(kind) }
                })
    }

    func move(from: IndexSet, to: Int) { order.move(fromOffsets: from, toOffset: to) }

    private func save() {
        defaults.set(order.map(\.rawValue), forKey: "widgetOrder")
        defaults.set(enabled.map(\.rawValue), forKey: "widgetEnabled")
        defaults.set(showMenuBar, forKey: "showMenuBar")
        defaults.set(menuBarShowsCPU, forKey: "menuBarShowsCPU")
        defaults.set(sampleInterval, forKey: "sampleInterval")
        defaults.set(confirmBeforeDelete, forKey: "confirmBeforeDelete")
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("MacErase.settingsChanged")
}
