import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                WidgetPicker()
            } header: {
                Text("Widget'lar")
            } footer: {
                Text("Seçilen widget'lar pencerenin sağ üst köşesinde görünür.")
            }

            Section("Menü Çubuğu") {
                Toggle("Menü çubuğunda göster", isOn: $settings.showMenuBar)
                Toggle("CPU yüzdesini göster", isOn: $settings.menuBarShowsCPU).disabled(!settings.showMenuBar)
            }

            Section("Performans") {
                Picker("Güncelleme sıklığı", selection: $settings.sampleInterval) {
                    Text("1 saniye").tag(1.0)
                    Text("2 saniye").tag(2.0)
                    Text("5 saniye").tag(5.0)
                }
                Text("Pencere gizliyken örnekleme durur. Menü çubuğu açıksa 5 saniyede bir yenilenir.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Davranış") {
                Toggle("Uygulama kaldırmadan önce onay iste", isOn: $settings.confirmBeforeDelete)
                Toggle("Oturum açıldığında başlat", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }

            Section("Hakkında") {
                LabeledContent("MacErase", value: Self.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 600)
    }
}
