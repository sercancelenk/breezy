import SwiftUI
import AppModel
import Preferences

struct ProfileEditor: View {
    @Environment(ScanViewModel.self) private var model
    @Binding var profile: ProviderProfile
    @Binding var apiKey: String
    @Binding var testResult: String
    @State private var headersText = ""

    private var authKind: Binding<Int> {
        Binding(
            get: {
                switch profile.auth { case .bearer: 0; case .header: 1; case .query: 2 }
            },
            set: { kind in
                let current = authName.wrappedValue
                switch kind {
                case 0: profile.auth = .bearer
                case 1: profile.auth = .header(current.isEmpty ? "x-api-key" : current)
                default: profile.auth = .query(current.isEmpty ? "key" : current)
                }
            })
    }

    private var authName: Binding<String> {
        Binding(
            get: {
                switch profile.auth { case .bearer: ""; case .header(let n), .query(let n): n }
            },
            set: { name in
                switch profile.auth {
                case .bearer: break
                case .header: profile.auth = .header(name)
                case .query: profile.auth = .query(name)
                }
            })
    }

    var body: some View {
        Section("Profil") {
            TextField("Ad", text: $profile.name)
            Picker("Tür", selection: $profile.kind) {
                ForEach(ProviderKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Host / Base URL", text: $profile.baseURL)
            TextField("Endpoint yolu", text: $profile.path)
            TextField("Model", text: $profile.model)
            Picker("Kimlik doğrulama", selection: authKind) {
                Text("Bearer token").tag(0)
                Text("Özel header").tag(1)
                Text("Query parametresi").tag(2)
            }
            if authKind.wrappedValue != 0 { TextField("Header / parametre adı", text: authName) }
            SecureField("API key (Keychain'de saklanır)", text: $apiKey)
            VStack(alignment: .leading) {
                Text("Ekstra header'lar (Ad: değer)").font(.caption).foregroundStyle(Theme.textSecondary)
                TextEditor(text: $headersText).font(.body.monospaced()).frame(height: 56)
            }
            Stepper("Zaman aşımı: \(Int(profile.timeout)) sn", value: $profile.timeout, in: 5...300, step: 5)
        }
        .onAppear { headersText = profile.extraHeadersText }
        .onChange(of: profile.id) { headersText = profile.extraHeadersText }
        .onChange(of: headersText) { profile.extraHeadersText = headersText }

        if profile.kind == .customHTTP {
            Section("İstek şablonu") {
                VStack(alignment: .leading) {
                    Text("Gövde (JSON). Yer tutucular: {{model}}, {{system}}, {{prompt}}; tırnak içinde yazın.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    TextEditor(text: $profile.bodyTemplate).font(.body.monospaced()).frame(height: 90)
                }
                TextField("Yanıt metni JSON yolu (ör. choices.0.message.content)", text: $profile.responsePath)
            }
        }
        Section {
            HStack {
                Button {
                    testResult = "Test ediliyor…"
                    let p = profile, k = apiKey
                    Task { testResult = await model.testConnection(profile: p, apiKey: k) }
                } label: {
                    Label("Bağlantıyı test et", systemImage: "bolt.fill")
                }
                .buttonStyle(AuroraButtonStyle())
                Text(testResult).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
