import SwiftUI

/// The pill strip shown in the top-right of the window toolbar.
struct WidgetsBar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemMonitor.self) private var monitor
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(settings.visibleWidgets) { kind in
                WidgetPill(kind: kind)
            }
            Button { showPicker.toggle() } label: {
                Image(systemName: settings.visibleWidgets.isEmpty ? "plus.circle" : "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Widget'ları düzenle")
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                WidgetPicker().frame(width: 280).padding(14)
            }
        }
    }
}

struct WidgetPill: View {
    let kind: WidgetKind
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        HStack(spacing: 6) {
            if let fraction {
                RingGauge(fraction: fraction, tint: tint, lineWidth: 2.5).frame(width: 14, height: 14)
            } else {
                Image(systemName: kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            }
            content
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
        .help(help)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .clock:
            TimelineView(.everyMinute) { ctx in Text(ctx.date, format: .dateTime.hour().minute()) }
        case .network:
            Text("↓\(Fmt.rate(monitor.netDown))  ↑\(Fmt.rate(monitor.netUp))")
        default:
            Text(valueText).contentTransition(.numericText())
        }
    }

    private var tint: Color {
        switch kind {
        case .cpu where monitor.cpu > 85, .memory where monitor.memoryFraction > 0.9: .red
        case .battery:
            if let b = monitor.battery, b.percent <= 20, !b.onAC { .red } else { kind.tint }
        default: kind.tint
        }
    }

    private var fraction: Double? {
        switch kind {
        case .cpu: monitor.cpu / 100
        case .memory: monitor.memoryFraction
        case .disk: monitor.diskUsedFraction
        case .battery: monitor.battery.map { Double($0.percent) / 100 }
        default: nil
        }
    }

    private var valueText: String {
        if !monitor.hasSample, kind != .network, kind != .clock { return "–" }
        return switch kind {
        case .cpu: "\(Int(monitor.cpu))%"
        case .memory: Fmt.bytes(monitor.memoryUsed)
        case .disk: String(localized: "\(Fmt.bytes(monitor.diskFree)) boş")
        case .battery: monitor.battery.map { "\($0.percent)%" + ($0.isCharging ? " ⚡︎" : "") } ?? "AC"
        default: ""
        }
    }

    private var help: String {
        switch kind {
        case .cpu: String(localized: "İşlemci kullanımı: \(Int(monitor.cpu))%")
        case .memory: String(localized: "Bellek: \(Fmt.bytes(monitor.memoryUsed)) / \(Fmt.bytes(monitor.memoryTotal))")
        case .disk: String(localized: "Disk: \(Fmt.bytes(monitor.diskFree)) boş / \(Fmt.bytes(monitor.diskTotal))")
        case .battery:
            if let b = monitor.battery {
                String(localized: "Pil \(b.percent)%") + (b.isCharging ? String(localized: ", şarj oluyor") : b.onAC ? String(localized: ", şarjlı") : "")
                    + (b.minutesRemaining.map { String(localized: ", \($0 / 60) sa \($0 % 60) dk") } ?? "")
            } else { String(localized: "Bu Mac'te pil yok") }
        case .network: String(localized: "Ağ: indirme \(Fmt.rate(monitor.netDown)), yükleme \(Fmt.rate(monitor.netUp))")
        case .clock: String(localized: "Saat")
        }
    }
}

/// Toggle + reorder list, used by both the toolbar popover and the Settings window.
struct WidgetPicker: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Widget'lar").font(.headline)
            Text("Sağ üstte görünecekleri seç, sıralamak için sürükle.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(settings.order) { kind in
                    Toggle(isOn: settings.binding(for: kind)) {
                        Label(kind.title, systemImage: kind.symbol).foregroundStyle(kind.tint)
                    }
                    .toggleStyle(.switch)
                }
                .onMove { settings.move(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .frame(height: CGFloat(settings.order.count) * 34 + 8)
            .scrollDisabled(true)
        }
    }
}
