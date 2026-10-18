import SwiftUI
import AppModel
import AI
import Cleaning
import CleanerCore

struct RootView: View {
    @Environment(ScanViewModel.self) private var model
    @State private var filter: SidebarFilter = .all
    @State private var showConfirm = false
    @State private var aiPrompt: AIPrompt?
    @State private var aiNotice: String?
    @State private var hasFDA = true

    private var visible: [Finding] {
        switch filter {
        case .all: model.findings
        case .category(let c): model.findings.filter { $0.category == c }
        }
    }

    private var showComposer: Bool {
        (model.phase == .ready || model.phase == .done) && !model.findings.isEmpty
    }

    private var busy: Bool {
        model.phase == .scanning || model.phase == .cleaning || model.categoryScanning != nil
    }

    private var channelTitle: String {
        switch filter {
        case .all: "Genel bakış"
        case .category(let c): c.title
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(filter: $filter, hasFDA: hasFDA)
            VStack(spacing: 0) {
                header
                Divider()
                banners
                content
                if showComposer { composer }
            }
            .background(Theme.canvas.ignoresSafeArea())
        }
        .sheet(isPresented: $showConfirm) { ConfirmSheet() }
        .sheet(item: $aiPrompt) { AIPreviewSheet(prompt: $0) }
        .alert("AI kullanılamıyor", isPresented: Binding(get: { aiNotice != nil }, set: { if !$0 { aiNotice = nil } })) {
            Button("Ayarları aç") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            Button("Tamam", role: .cancel) {}
        } message: { Text(aiNotice ?? "") }
        .task { hasFDA = ScanViewModel.hasFullDiskAccess(home: FileManager.default.homeDirectoryForCurrentUser) }
    }

    /// Profil yoksa/kapalıysa nedenini söyler; uygunsa önizleme penceresini açar.
    private func askAI(_ finding: Finding?) {
        if let reason = model.aiUnavailableReason(single: finding != nil) { aiNotice = reason; return }
        aiPrompt = finding.flatMap { model.aiPrompt(for: $0) } ?? model.aiPrompt()
    }

    // MARK: Kanal başlığı

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("# \(channelTitle)").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.textPrimary)
                Text("\(Format.bytes(model.totalBytes)) geri kazanılabilir • \(model.findings.count) öğe • \(model.selected.count) seçili")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { askAI(nil) } label: { Label("AI ile iyileştir", systemImage: "sparkles") }
                .buttonStyle(SoftButtonStyle()).disabled(model.aiRunning)
                .help(model.aiUnavailableReason ?? "Belirsiz öğeleri AI ile değerlendir")
            Button { model.startLargeScan() } label: { Label("Büyük öğeler", systemImage: "externaldrive") }
                .buttonStyle(SoftButtonStyle())
                .disabled(model.isLargeScanning || model.phase == .scanning || model.phase == .cleaning)
            if case .category(let c) = filter {
                Button { model.startCategoryScan(c) } label: {
                    Label("Sadece bunu tara", systemImage: "magnifyingglass")
                }
                .buttonStyle(AuroraButtonStyle())
                .disabled(busy)
                .help("Yalnızca “\(c.title)” kategorisini tarar; diğer sonuçlar korunur")
            }
            if filter == .all {
                Button { model.startScan() } label: {
                    Label(model.phase == .idle ? "Taramayı başlat" : "Yeniden tara", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AuroraButtonStyle()).disabled(busy)
            } else {
                Button { model.startScan() } label: { Label("Tümünü tara", systemImage: "arrow.clockwise") }
                    .buttonStyle(SoftButtonStyle()).disabled(busy)
            }
        }
        .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 10)
    }

    // MARK: Bantlar

    @ViewBuilder private var banners: some View {
        VStack(spacing: 6) {
            if !hasFDA {
                banner(icon: "lock.shield.fill", tint: Theme.amber,
                       text: "Tam Disk Erişimi verilmedi; bazı klasörler taranamayabilir.") {
                    Button("Ayarları aç") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }.buttonStyle(SoftButtonStyle())
                }
            }
            if let c = model.categoryScanning, c != .large {
                banner(icon: "magnifyingglass", tint: Theme.blue, text: "“\(c.title)” taranıyor…") {
                    ProgressView().controlSize(.small)
                    Button("İptal") { model.cancelCategoryScan() }.buttonStyle(SoftButtonStyle())
                }
            }
            if model.isLargeScanning {
                banner(icon: "externaldrive.fill", tint: Theme.coral,
                       text: "Ev dizininde büyük öğeler aranıyor… (günlük klasörler önce)") {
                    ProgressView().controlSize(.small)
                    Button("İptal") { model.cancelLargeScan() }.buttonStyle(SoftButtonStyle())
                }
            }
            if !model.settings.aiEnabled, model.settings.activeProfile != nil {
                banner(icon: "sparkles", tint: Theme.blue, text: "AI profilin hazır ama AI desteği kapalı.") {
                    Button("AI'yı aç") { model.settings.aiEnabled = true; model.saveSettings() }
                        .buttonStyle(SoftButtonStyle())
                }
            }
            if let status = model.aiStatus {
                banner(icon: "sparkles", tint: Theme.blue, text: status) { EmptyView() }
            }
            if model.phase == .done, let r = model.report {
                banner(icon: r.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                       tint: r.failures.isEmpty ? Theme.mint : Theme.amber,
                       text: "\(r.trashed.count) öğe (\(Format.bytes(r.reclaimedBytes))) Çöp Kutusu'na taşındı."
                            + (r.failures.isEmpty ? "" : " \(r.failures.count) öğe taşınamadı.")
                            + " Alan, Çöp Kutusu'nu boşaltınca açılır.") {
                    Button("Çöp Kutusu'nu aç") {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                    }.buttonStyle(SoftButtonStyle())
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private func banner<Trailing: View>(icon: String, tint: Color, text: String,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 15))
            Text(text).font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }

    // MARK: İçerik

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle where model.findings.isEmpty:
            emptyState(symbol: "externaldrive.badge.checkmark", title: "Henüz taranmadı",
                       message: "Gereksiz dosyaları bulmak için taramayı başlat.") {
                HStack {
                    Button("Taramayı başlat") { model.startScan() }.buttonStyle(AuroraButtonStyle())
                    if case .category(let c) = filter {
                        Button("Sadece “\(c.title)”") { model.startCategoryScan(c) }.buttonStyle(SoftButtonStyle())
                    }
                }
            }
        case .scanning, .cleaning:
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(model.phase == .scanning ? "Taranıyor…" : "Çöp Kutusu'na taşınıyor…")
                    .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                if model.phase == .scanning {
                    Button("İptal") { model.cancelScan() }.buttonStyle(SoftButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            if visible.isEmpty {
                emptyState(symbol: "checkmark.circle.fill", title: "Temiz",
                           message: "Burada önerilecek bir şey bulunamadı.") {
                    if case .category(let c) = filter {
                        Button("Sadece “\(c.title)” kategorisini tara") { model.startCategoryScan(c) }
                            .buttonStyle(SoftButtonStyle()).disabled(busy)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if case .all = filter {
                            ForEach(model.grouped, id: \.category) { group in
                                divider(group.category.title, count: group.items.count)
                                ForEach(group.items) { card($0) }
                            }
                        } else {
                            ForEach(visible) { card($0) }
                        }
                    }
                    .padding(.top, 8).padding(.bottom, 12)
                }
            }
        }
    }

    private func card(_ f: Finding) -> some View { FindingCard(finding: f) { askAI($0) } }

    /// Slack'teki gün ayırıcısı: çizgi + ortada hap.
    private func divider(_ title: String, count: Int) -> some View {
        ZStack {
            Divider()
            Text("\(title) · \(count)")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(Theme.canvas, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func emptyState<Action: View>(symbol: String, title: String, message: String,
                                          @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(Theme.aubergine.opacity(0.8))
            Text(title).font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
            action().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Mesaj kutusu (Slack composer)

    private var composer: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.selected.count) öğe seçili")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                SizeCode(bytes: model.selectedBytes)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            HStack(spacing: 8) {
                Button("Güvenli olanları seç") {
                    model.selected = Set(model.findings.filter { $0.confidence == .high && $0.impact.preselectable }.map(\.id))
                }.buttonStyle(SoftButtonStyle())
                Button("Seçimi temizle") { model.selected = [] }
                    .buttonStyle(SoftButtonStyle()).disabled(model.selected.isEmpty)
                Spacer()
                Button { showConfirm = true } label: { Label("Çöp Kutusu'na taşı", systemImage: "trash.fill") }
                    .buttonStyle(AuroraButtonStyle()).disabled(model.selected.isEmpty)
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.textSecondary.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 6)
    }
}
