import AppKit
import SwiftUI

struct CleanerView: View {
    @ObservedObject var model: CleanerModel
    @State private var confirm = false
    @State private var expanded: Set<CleanKind> = []

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle: intro
            case .scanning, .ready: results
            case .cleaning: ProgressView("Temizleniyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .done(freed, failed): done(freed: freed, failed: failed)
            }
        }
        .navigationTitle("Akıllı Temizlik")
        .task { // screenshot/debug hook
            if ProcessInfo.processInfo.environment["MACERASE_AUTOSCAN"] == "1", model.phase == .idle { model.scan() }
        }
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles").font(.system(size: 54, weight: .light)).foregroundStyle(.brand)
            Text("Akıllı Temizlik").font(.largeTitle.weight(.bold))
            Text("Önbellekleri, günlükleri ve geliştirici artıklarını tara; neyin silineceğini sen seç.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("Taramayı Başlat") { model.scan() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.categories) { category in categoryCard(category) }
                    if model.phase == .scanning {
                        HStack { ProgressView().controlSize(.small); Text("Taranıyor…").foregroundStyle(.secondary) }.padding()
                    }
                }
                .padding(18)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.bytes(model.selectedTotal)).font(.title3.weight(.semibold).monospacedDigit())
                    Text("temizlenmeye hazır").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Yeniden Tara") { model.scan() }
                    .keyboardShortcut("r", modifiers: .command).disabled(model.phase == .scanning)
                Button("Temizle") { confirm = true }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.selectedTotal == 0 || model.phase == .scanning)
            }
            .padding(14)
        }
        .confirmationDialog("Seçili öğeler silinsin mi?", isPresented: $confirm, titleVisibility: .visible) {
            Button("\(Fmt.bytes(model.selectedTotal)) Temizle", role: .destructive) { model.clean() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu öğeler Çöp Kutusu'na gitmeden KALICI olarak silinir ve geri alınamaz.")
        }
    }

    private func categoryCard(_ category: CleanCategory) -> some View {
        let kind = category.kind
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { category.enabled }, set: { model.toggle(kind, on: $0) }))
                    .labelsHidden().disabled(category.items.isEmpty)
                Image(systemName: kind.symbol).font(.title3).foregroundStyle(.brand).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.headline)
                    Text(kind.subtitle).font(.caption).foregroundStyle(.secondary)
                    if kind == .trash && model.trashNeedsAccess {
                        Button("Tam Disk Erişimi ayarını aç: Çöp Kutusu'nu okumak için gerekli") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        }
                        .buttonStyle(.link).font(.caption)
                    }
                }
                Spacer()
                Text(category.items.isEmpty ? "–" : Fmt.bytes(category.total)).font(.headline.monospacedDigit())
                if !category.items.isEmpty {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded.contains(kind) ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !category.items.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    if expanded.contains(kind) { expanded.remove(kind) } else { expanded.insert(kind) }
                }
            }
            if expanded.contains(kind) {
                Divider().padding(.vertical, 8)
                ForEach(category.items) { item in
                    HStack {
                        Toggle(item.url.lastPathComponent, isOn: Binding(get: { !model.excluded.contains(item.url) },
                                                                         set: { _ in model.toggleItem(item.url) }))
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.url.lastPathComponent).lineLimit(1).font(.callout)
                            Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: FileUtil.home.path, with: "~"))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Text(Fmt.bytes(item.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .contextMenu { Button("Finder'da Göster") { FileUtil.reveal(item.url) } }
                }
            }
        }
        .card()
    }

    private func done(freed: Int64, failed: Int) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(.green)
            Text("\(Fmt.bytes(freed)) boşaltıldı").font(.largeTitle.weight(.bold))
            if failed > 0 {
                Text("\(failed) öğe silinemedi (kullanımda veya izin yok).").foregroundStyle(.secondary)
            }
            Button("Tamam") { model.phase = .idle }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
