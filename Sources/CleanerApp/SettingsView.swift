import SwiftUI
import AppModel
import Preferences

struct SettingsView: View {
    var body: some View {
        TabView {
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
            ScanSettingsView().tabItem { Label("Tarama", systemImage: "folder.fill") }
        }
        .frame(width: 620, height: 600)
        .padding()
        .background(Theme.canvas)
    }
}

struct AISettingsView: View {
    @Environment(ScanViewModel.self) private var model
    @State private var apiKey = ""
    @State private var testResult = ""

    private var activeIndex: Int? {
        model.settings.profiles.firstIndex { $0.id == model.settings.activeProfileID }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Label("AI kapalıyken uygulama ağa hiç bağlanmaz. Açıkken yalnızca gizlenmiş yol, boyut ve yaş gider ve her gönderimi önceden görüp onaylarsın. Yerel model (Ollama gibi) kullanırsan hiçbir şey Mac'inden çıkmaz.",
                  systemImage: "lock.fill")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Toggle("AI desteğini aç", isOn: $model.settings.aiEnabled)
                Picker("Aktif profil", selection: $model.settings.activeProfileID) {
                    Text("Yok").tag(UUID?.none)
                    ForEach(model.settings.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                HStack {
                    Menu {
                        Button("Claude (Anthropic)") { add(.anthropic()) }
                        Button("OpenAI uyumlu (Ollama, LiteLLM, Azure…)") { add(.openAICompatible()) }
                        Button("Özel HTTP (şirket LLM platformu)") { add(.custom()) }
                    } label: {
                        Label("Profil ekle", systemImage: "plus")
                    }
                    .menuStyle(.button).buttonStyle(SoftButtonStyle()).fixedSize()
                    Button(role: .destructive) { removeActive() } label: {
                        Label("Profili sil", systemImage: "trash")
                    }
                    .buttonStyle(SoftButtonStyle()).disabled(activeIndex == nil)
                }
            }
            if let i = activeIndex {
                ProfileEditor(profile: profileBinding(model.settings.profiles[i].id), apiKey: $apiKey, testResult: $testResult)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: model.settings) { model.saveSettings() }
        .onChange(of: model.settings.activeProfileID, initial: true) {
            apiKey = model.settings.activeProfileID.map { model.apiKey(for: $0) } ?? ""
            testResult = ""
        }
        .onChange(of: apiKey) {
            if let id = model.settings.activeProfileID { model.setAPIKey(apiKey, for: id) }
        }
    }

    private func profileBinding(_ id: UUID) -> Binding<ProviderProfile> {
        Binding(get: { model.settings.profiles.first { $0.id == id } ?? .anthropic() },
                set: { new in
                    if let j = model.settings.profiles.firstIndex(where: { $0.id == id }) { model.settings.profiles[j] = new }
                })
    }

    private func add(_ profile: ProviderProfile) {
        model.settings.profiles.append(profile)
        model.settings.activeProfileID = profile.id
    }

    private func removeActive() {
        guard let i = activeIndex else { return }
        let id = model.settings.profiles[i].id
        model.setAPIKey("", for: id)
        model.settings.profiles.remove(at: i)
        model.settings.activeProfileID = model.settings.profiles.first?.id
    }
}

struct ScanSettingsView: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Büyük öğeler") {
                Picker("Şu boyutun üstündekileri listele", selection: $model.settings.largeItemThresholdMB) {
                    Text("100 MB").tag(100)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                    Text("5 GB").tag(5120)
                }
                Text("Ev dizininde bu boyutun üstündeki klasör ve dosyalar listelenir. Hiçbiri otomatik seçilmez; yalnızca yol ve boyut kullanılır, içerik okunmaz.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            PathListEditor(title: "Taranacak proje kökleri", paths: $model.settings.scanRoots)
            PathListEditor(title: "Hariç tutulan yollar", paths: $model.settings.excludedPaths)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: model.settings) { model.saveSettings() }
    }
}

struct PathListEditor: View {
    let title: String
    @Binding var paths: [String]

    var body: some View {
        Section(title) {
            ForEach(paths, id: \.self) { p in
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.violet)
                    Text(p).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { paths.removeAll { $0 == p } } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(Theme.coral)
                }
            }
            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let u = panel.url, !paths.contains(u.path) { paths.append(u.path) }
            } label: {
                Label("Klasör ekle…", systemImage: "plus")
            }
            .buttonStyle(SoftButtonStyle())
        }
    }
}
