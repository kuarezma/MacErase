import SwiftUI

struct OverviewView: View {
    @Environment(SystemMonitor.self) private var monitor
    let go: (SidebarItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    stat(String(localized: "Disk"), "internaldrive", diskLow ? .red : .orange, monitor.diskUsedFraction,
                         String(localized: "\(Fmt.bytes(monitor.diskFree)) boş"))
                    stat(String(localized: "Bellek"), "memorychip", .purple, monitor.memoryFraction,
                         "\(Fmt.bytes(monitor.memoryUsed)) / \(Fmt.bytes(monitor.memoryTotal))")
                    stat(String(localized: "İşlemci"), "cpu", .blue, monitor.cpu / 100, String(localized: "\(Int(monitor.cpu))% kullanımda"))
                    if let b = monitor.battery {
                        stat(String(localized: "Pil"), "battery.75percent", .green, Double(b.percent) / 100,
                             b.isCharging ? String(localized: "Şarj oluyor") : b.onAC ? String(localized: "Şarjlı") : String(localized: "Pille çalışıyor"))
                    }
                }
                Text("Hızlı İşlemler").font(.headline).padding(.top, 4)
                HStack(alignment: .top, spacing: 14) {
                    action(String(localized: "Akıllı Temizlik"), "sparkles", String(localized: "Önbellek ve artıkları tara"), .clean)
                    action(String(localized: "Uygulama Kaldır"), "trash", String(localized: "Uygulama ve kalıntılarını sil"), .apps)
                    action(String(localized: "Büyük Dosyalar"), "doc.zipper", String(localized: "Yer kaplayanları bul"), .large)
                    action(String(localized: "Başlangıç Öğeleri"), "power", String(localized: "Açılışta çalışanları yönet"), .startup)
                }
            }
            .padding(24)
        }
        .navigationTitle("Genel Bakış")
    }

    private var diskLow: Bool { monitor.hasSample && monitor.diskUsedFraction > 0.9 }

    private var hero: some View {
        HStack(spacing: 16) {
            Image(systemName: "bolt.shield.fill").font(.system(size: 34)).foregroundStyle(.white)
                .frame(width: 64, height: 64).background(.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(diskLow ? String(localized: "Diskin %\(Int((monitor.diskUsedFraction * 100).rounded())) dolu") : String(localized: "Mac'in bakıma hazır"))
                    .font(.title2.weight(.semibold))
                Text(diskLow
                     ? String(localized: "Yalnızca \(Fmt.bytes(monitor.diskFree)) boş. Akıllı Temizlik ve Büyük Dosyalar ile yer aç.")
                     : String(localized: "Uygulama kaldırma çöp kutusuna taşır, geri alabilirsin. Akıllı Temizlik önbellekleri kalıcı siler ve her seferinde onay ister."))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card(padding: 18)
    }

    private func stat(_ title: String, _ symbol: String, _ tint: Color, _ fraction: Double, _ detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RingGauge(fraction: fraction, tint: tint, lineWidth: 6)
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(monitor.hasSample ? "\(Int((fraction * 100).rounded()))%" : "–")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(monitor.hasSample ? detail : " ").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func action(_ title: String, _ symbol: String, _ detail: String, _ target: SidebarItem) -> some View {
        Button { go(target) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.brand)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .card()
        }
        .buttonStyle(.plain)
    }
}
