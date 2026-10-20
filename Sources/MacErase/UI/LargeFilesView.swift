import SwiftUI

struct LargeFilesView: View {
    @ObservedObject var model: LargeFilesModel
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Minimum boyut", selection: $model.minMB) {
                    Text("50 MB").tag(50); Text("100 MB").tag(100); Text("500 MB").tag(500); Text("1 GB").tag(1000)
                }
                .frame(width: 220)
                Button(model.scanning ? String(localized: "Taranıyor…") : String(localized: "Tara")) { model.scan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .buttonStyle(PrimaryButtonStyle()).disabled(model.scanning)
                Spacer()
                Text("Ev klasörü içindeki Belgeler, İndirilenler, Masaüstü, Filmler vb.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            if model.scanning {
                ProgressView("Büyük dosyalar aranıyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.files.isEmpty {
                EmptyState(symbol: "doc.zipper", title: String(localized: "Henüz sonuç yok"),
                           detail: model.message ?? String(localized: "Tara'ya basarak büyük dosyaları bul."))
            } else {
                List(model.files) { file in
                    HStack(spacing: 10) {
                        Toggle(file.url.lastPathComponent, isOn: Binding(get: { model.checked.contains(file.url) },
                                                 set: { _ in model.toggle(file.url) })).labelsHidden()
                        FileIcon(url: file.url, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.url.lastPathComponent).lineLimit(1)
                            Text(file.url.deletingLastPathComponent().path.replacingOccurrences(of: FileUtil.home.path, with: "~"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        if let date = file.modified {
                            Text(date, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(Fmt.bytes(file.size)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
                    }
                    .contextMenu { Button("Finder'da Göster") { FileUtil.reveal(file.url) } }
                }
                Divider()
                HStack {
                    Text("\(model.checked.count) dosya seçili · \(Fmt.bytes(model.selectedBytes))")
                    Spacer()
                    if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    Button("Çöpe Taşı") { confirm = true }
                        .buttonStyle(PrimaryButtonStyle(destructive: true)).disabled(model.checked.isEmpty)
                }
                .padding(14)
            }
        }
        .navigationTitle("Büyük Dosyalar")
        .confirmationDialog("Seçili dosyalar çöpe taşınsın mı?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Çöpe Taşı", role: .destructive) { model.trashSelected() }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}
