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

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(filter: $filter, hasFDA: hasFDA).frame(width: 260)
            ZStack(alignment: .bottom) {
                Theme.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    hero.padding(.horizontal, 24).padding(.top, 30)
                    banners.padding(.horizontal, 24)
                    content
                }
                if showComposer { composer.padding(.horizontal, 24).padding(.bottom, 18) }
            }
        }
        .sheet(isPresented: $showConfirm) { ConfirmSheet() }
        .sheet(item: $aiPrompt) { AIPreviewSheet(prompt: $0) }
        .task { hasFDA = ScanViewModel.hasFullDiskAccess(home: FileManager.default.homeDirectoryForCurrentUser) }
        .animation(.easeOut(duration: 0.2), value: model.phase)
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.aurora)
            Circle().fill(.white.opacity(0.14)).frame(width: 220).offset(x: 430, y: -70)
            Circle().fill(.white.opacity(0.10)).frame(width: 140).offset(x: 330, y: 70)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Geri kazanılabilir alan")
                        .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                    Text(Format.bytes(model.totalBytes))
                        .font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    Text("\(model.findings.count) öğe • \(model.selected.count) seçili • \(Format.bytes(model.selectedBytes))")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Button { model.startScan() } label: {
                        Label(model.phase == .idle ? "Taramayı başlat" : "Yeniden tara", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(model.phase == .scanning || model.phase == .cleaning)
                    Button { aiPrompt = model.aiPrompt() } label: {
                        Label("AI ile iyileştir", systemImage: "sparkles")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(model.aiRunning || model.aiPrompt() == nil)
                    .help(model.aiUnavailableReason ?? "Belirsiz öğeleri AI ile değerlendir")
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 22)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.magenta.opacity(0.35), radius: 22, y: 10)
    }

    // MARK: Bantlar

    @ViewBuilder private var banners: some View {
        VStack(spacing: 8) {
            if !hasFDA {
                banner(icon: "lock.shield.fill", tint: Theme.amber,
                       text: "Tam Disk Erişimi verilmedi; bazı klasörler taranamayabilir.") {
                    Button("Ayarları aç") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }.buttonStyle(SoftButtonStyle())
                }
            }
            if model.phase != .scanning && model.phase != .cleaning {
                let mb = model.settings.largeItemThresholdMB
                let limit = mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB"
                if model.isLargeScanning {
                    banner(icon: "externaldrive.fill", tint: Theme.coral,
                           text: "Ev dizininde büyük öğeler aranıyor… (günlük klasörler önce)") {
                        ProgressView().controlSize(.small)
                        Button("İptal") { model.cancelLargeScan() }.buttonStyle(SoftButtonStyle())
                    }
                } else {
                    let found = model.findings.contains { $0.category == .large }
                    banner(icon: "externaldrive.fill", tint: Theme.coral,
                           text: "Kural bilmediği büyük klasör ve dosyalar (\(limit)+) ayrı taranır; hiçbiri seçili gelmez.") {
                        Button(found ? "Yeniden tara" : "Büyük öğeleri tara") { model.startLargeScan() }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            }
            if !model.settings.aiEnabled, model.settings.activeProfile != nil {
                banner(icon: "sparkles", tint: Theme.violet, text: "AI profilin hazır ama AI desteği kapalı.") {
                    Button("AI'yı aç") { model.settings.aiEnabled = true; model.saveSettings() }
                        .buttonStyle(SoftButtonStyle())
                }
            }
            if let status = model.aiStatus {
                banner(icon: "sparkles", tint: Theme.violet, text: status) { EmptyView() }
            }
            if model.phase == .done, let r = model.report {
                banner(icon: r.failures.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
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
        .padding(.top, 12)
    }

    private func banner<Trailing: View>(icon: String, tint: Color, text: String,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 16, weight: .semibold))
            Text(text).font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: İçerik

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            emptyState(symbol: "externaldrive.badge.checkmark", title: "Henüz taranmadı",
                       message: "Gereksiz dosyaları bulmak için taramayı başlat.") {
                Button("Taramayı başlat") { model.startScan() }.buttonStyle(AuroraButtonStyle())
            }
        case .scanning, .cleaning:
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Theme.violet)
                Text(model.phase == .scanning ? "Taranıyor…" : "Çöp Kutusu'na taşınıyor…")
                    .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
                if model.phase == .scanning {
                    Button("İptal") { model.cancelScan() }.buttonStyle(SoftButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready, .done:
            if visible.isEmpty {
                emptyState(symbol: "checkmark.seal.fill", title: "Temiz",
                           message: "Burada önerilecek bir şey bulunamadı.") { EmptyView() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if case .all = filter {
                            ForEach(model.grouped, id: \.category) { group in
                                sectionHeader(group.category.title)
                                ForEach(group.items) { FindingCard(finding: $0) }
                            }
                        } else {
                            ForEach(visible) { FindingCard(finding: $0) }
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 110)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 10).padding(.leading, 4)
    }

    private func emptyState<Action: View>(symbol: String, title: String, message: String,
                                          @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 92, height: 92).background(Theme.aurora, in: Circle())
                .shadow(color: Theme.magenta.opacity(0.4), radius: 18, y: 6)
            Text(title).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.textSecondary)
            action().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Composer (Slack mesaj kutusu gibi yüzen çubuk)

    private var composer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.selected.count) öğe seçili")
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                Text(Format.bytes(model.selectedBytes))
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Güvenli olanları seç") {
                model.selected = Set(model.findings.filter { $0.confidence == .high }.map(\.id))
            }.buttonStyle(SoftButtonStyle())
            Button("Seçimi temizle") { model.selected = [] }
                .buttonStyle(SoftButtonStyle()).disabled(model.selected.isEmpty)
            Button { showConfirm = true } label: { Label("Çöp Kutusu'na taşı", systemImage: "trash.fill") }
                .buttonStyle(AuroraButtonStyle()).disabled(model.selected.isEmpty)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: Theme.ink.opacity(0.18), radius: 18, y: 8)
    }
}
