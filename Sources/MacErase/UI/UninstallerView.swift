import SwiftUI

struct UninstallerView: View {
    @Environment(AppSettings.self) private var settings
    @ObservedObject var model: UninstallerModel
    @FocusState private var searchFocused: Bool
    @State private var confirm = false

    var body: some View {
        HStack(spacing: 0) {
            appList.frame(width: 300)
            Divider()
            detail.frame(maxWidth: .infinity)
        }
        .navigationTitle("Uygulamalar")
        .onAppear { model.load() }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Uygulama ara", text: $model.query).textFieldStyle(.plain).focused($searchFocused)
                Button { searchFocused = true } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: .command).frame(width: 0, height: 0).opacity(0)
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).keyboardShortcut("r", modifiers: .command)
                    .help("Listeyi yenile (⌘R)").disabled(model.loading)
                Picker("", selection: $model.sort) {
                    ForEach(AppSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 100)
            }
            .padding(10)
            Divider()
            if model.loading {
                ProgressView("Uygulamalar taranıyor…").frame(maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { model.selected }, set: { model.select($0) })) {
                    ForEach(model.visibleApps) { app in
                        AppRow(app: app, size: model.sizes[app.url]).tag(app)
                    }
                }
                .listStyle(.sidebar)
                Divider()
                Text("\(model.visibleApps.count) uygulama")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let app = model.selected {
            VStack(spacing: 0) {
                header(app)
                Divider()
                if model.scanningLeftovers && model.leftovers.isEmpty {
                    ProgressView("Kalıntılar aranıyor…").frame(maxHeight: .infinity)
                } else {
                    leftoverList
                }
                Divider()
                footer(app)
            }
        } else if let message = model.message {
            VStack(spacing: 14) {
                EmptyState(symbol: "checkmark.circle.fill", title: String(localized: "Tamamlandı"), detail: message)
                if model.canUndo {
                    Button("Geri Al") { model.undo() }.buttonStyle(PrimaryButtonStyle())
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(symbol: "square.and.arrow.down.on.square", title: String(localized: "Bir uygulama seç ya da buraya sürükle"),
                       detail: String(localized: "Uygulamayı ve tüm kalıntılarını (önbellek, tercihler, günlükler…) tek seferde kaldır."))
        }
    }

    private func header(_ app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            FileIcon(url: app.url, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title2.weight(.semibold))
                Text([app.version.isEmpty ? nil : String(localized: "Sürüm \(app.version)"), app.bundleID.isEmpty ? nil : app.bundleID]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button("Finder'da Göster") { FileUtil.reveal(app.url) }
        }
        .padding(18)
    }

    private var leftoverList: some View {
        List {
            ForEach(LeftoverCategory.allCases, id: \.self) { category in
                let rows = model.leftovers.filter { $0.category == category }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { item in
                            HStack(spacing: 10) {
                                Toggle(item.url.lastPathComponent, isOn: Binding(get: { model.checked.contains(item.url) },
                                                         set: { _ in model.toggle(item.url) }))
                                    .labelsHidden()
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.url.lastPathComponent).lineLimit(1)
                                    Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: FileUtil.home.path, with: "~"))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                                }
                                Spacer()
                                if item.needsAdmin { Image(systemName: "lock.fill").foregroundStyle(.orange).help("Yönetici parolası gerekir") }
                                Text(item.size.map(Fmt.bytes) ?? "…").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .contextMenu { Button("Finder'da Göster") { FileUtil.reveal(item.url) } }
                        }
                    } header: {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            }
        }
    }

    private func footer(_ app: InstalledApp) -> some View {
        HStack {
            if model.scanningLeftovers { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.checked.count) öğe seçili · \(Fmt.bytes(model.selectedBytes))").font(.callout.weight(.medium))
                HStack(spacing: 8) {
                    Text(model.message ?? String(localized: "Öğeler çöp kutusuna taşınır, geri alabilirsin."))
                        .font(.caption).foregroundStyle(.secondary)
                    if model.canUndo { Button("Geri Al") { model.undo() }.buttonStyle(.link).font(.caption) }
                }
            }
            Spacer()
            Button(model.working ? String(localized: "Kaldırılıyor…") : String(localized: "Kaldır")) {
                let hasLocked = model.leftovers.contains { model.checked.contains($0.url) && $0.needsAdmin }
                if settings.confirmBeforeDelete || hasLocked { confirm = true } else { model.uninstall() }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .buttonStyle(PrimaryButtonStyle(destructive: true))
            .disabled(model.checked.isEmpty || model.working || model.scanningLeftovers)
        }
        .padding(14)
        .confirmationDialog("\(app.name) kaldırılsın mı?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Çöpe Taşı (\(Fmt.bytes(model.selectedBytes)))", role: .destructive) { model.uninstall() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            let locked = model.leftovers.filter { model.checked.contains($0.url) && $0.needsAdmin }.count
            Text(String(localized: "Uygulama açıksa kapanması istenir. Seçili \(model.checked.count) öğe çöp kutusuna taşınır.")
                 + (locked > 0 ? String(localized: " Kilitli \(locked) öğe parola ile KALICI silinir.") : ""))
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let size: Int64?
    var body: some View {
        HStack(spacing: 10) {
            FileIcon(url: app.url, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(size.map(Fmt.bytes) ?? "…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
