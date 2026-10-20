import SwiftUI

struct StartupView: View {
    @ObservedObject var model: StartupModel
    @State private var pending: StartupItem?

    var body: some View {
        VStack(spacing: 0) {
            if !model.loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty {
                EmptyState(symbol: "power", title: String(localized: "Başlangıç öğesi yok"),
                           detail: String(localized: "Oturum açıldığında kendiliğinden çalışan arka plan öğeleri burada listelenir."))
            } else {
                List(model.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isDaemon ? "gearshape.2.fill" : "power.circle.fill")
                            .foregroundStyle(item.isSystemWide ? Color.secondary : Color.brandA).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label).lineLimit(1)
                            Text(item.program.isEmpty ? item.url.path : item.program)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(item.isDaemon ? String(localized: "Sistem servisi") : item.isSystemWide ? String(localized: "Tüm kullanıcılar") : String(localized: "Kullanıcı"))
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Finder") { FileUtil.reveal(item.url) }.buttonStyle(.borderless)
                        Button("Kaldır") { pending = item }
                            .buttonStyle(.borderless).foregroundStyle(.red).disabled(!item.removable)
                            .help(item.removable ? String(localized: "Başlangıçtan kaldır (çöpe taşır)") : String(localized: "Sistem öğeleri buradan kaldırılamaz"))
                    }
                }
                if let message = model.message {
                    Divider()
                    Text(message).font(.caption).foregroundStyle(.secondary).padding(10)
                }
            }
        }
        .navigationTitle("Başlangıç Öğeleri")
        .onAppear { if !model.loaded { model.load() } }
        .confirmationDialog("\(pending?.label ?? "") başlangıçtan kaldırılsın mı?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Çöpe Taşı", role: .destructive) { if let item = pending { model.remove(item) }; pending = nil }
            Button("Vazgeç", role: .cancel) { pending = nil }
        } message: { Text("Dosya çöp kutusuna taşınır, geri alabilirsin.") }
    }
}
