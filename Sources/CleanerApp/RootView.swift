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
        case .all: model.smartFindings
        case .category(let c): model.smartFindings.filter { $0.category == c }
        case .large: model.largeFindings
        case .apps: []
        }
    }

    private var showComposer: Bool {
        (model.phase == .ready || model.phase == .done) && !model.smartFindings.isEmpty
    }

    private var busy: Bool {
        model.phase == .scanning || model.phase == .cleaning || model.categoryScanning != nil
    }

    private var channelTitle: String {
        switch filter {
        case .all: "Genel bakış"
        case .category(let c): c.title
        case .large: "Büyük öğeler"
        case .apps: "Çalışan uygulamalar"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(filter: $filter, hasFDA: hasFDA)
            ZStack(alignment: .bottom) {
                Theme.canvas.ignoresSafeArea()
                if filter == .apps {
                    RunningAppsView()
                } else if filter == .large {
                    VStack(spacing: 0) {
                        largeHero.padding(.horizontal, 24).padding(.top, 30)
                        banners.padding(.horizontal, 24)
                        largeContent
                    }
                    if !model.selectedLargeFindings.isEmpty || !model.largeFindings.isEmpty {
                        composer(scope: .large).padding(.horizontal, 24).padding(.bottom, 18)
                    }
                } else {
                    VStack(spacing: 0) {
                        hero.padding(.horizontal, 24).padding(.top, 30)
                        banners.padding(.horizontal, 24)
                        content
                    }
                    if showComposer { composer(scope: .smart).padding(.horizontal, 24).padding(.bottom, 18) }
                }
            }
        }
        .sheet(isPresented: $showConfirm) { ConfirmSheet(scope: filter == .large ? .large : .smart) }
        .onChange(of: model.settings.largeItemThresholdMB) { model.saveSettings() }
        .sheet(item: $aiPrompt) { AIPreviewSheet(prompt: $0) }
        .alert("AI kullanılamıyor", isPresented: Binding(get: { aiNotice != nil }, set: { if !$0 { aiNotice = nil } })) {
            Button("Ayarları aç") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            Button("Tamam", role: .cancel) {}
        } message: { Text(aiNotice ?? "") }
        .task { refreshFDA() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshFDA() }
        .animation(.easeOut(duration: 0.2), value: model.phase)
    }

    private func refreshFDA() {
        hasFDA = ScanViewModel.hasFullDiskAccess(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Profil yoksa/kapalıysa nedenini söyler; uygunsa önizleme penceresini açar.
    private func askAI(_ finding: Finding?) {
        let scope: ScanViewModel.Scope = filter == .large ? .large : .smart
        if let reason = model.aiUnavailableReason(single: finding != nil, scope: scope) { aiNotice = reason; return }
        aiPrompt = finding.flatMap { model.aiPrompt(for: $0) } ?? model.aiPrompt(in: scope)
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.aurora)
            Circle().fill(Theme.teal.opacity(0.22)).frame(width: 230).offset(x: 430, y: -80)
            Circle().fill(Theme.mint.opacity(0.18)).frame(width: 150).offset(x: 320, y: 70)
            Circle().fill(Theme.amber.opacity(0.16)).frame(width: 90).offset(x: 540, y: 60)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(filter == .all ? "Bulunan toplam alan" : channelTitle)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    Text(Format.bytes(visible.reduce(0) { $0 + $1.size }))
                        .font(.system(size: 44, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
                    Text(filter == .all ? "\(visible.count) öğe bulundu • Önerilen seçim: \(model.selected.count) öğe, \(Format.bytes(model.selectedBytes))" : "\(visible.count) öğe • \(model.selected.count) seçili • \(Format.bytes(model.selectedBytes))")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    if case .category(let c) = filter {
                        Button { model.startCategoryScan(c) } label: {
                            Label("Bu kategoriyi tara", systemImage: "magnifyingglass").lineLimit(1).fixedSize()
                        }
                        .buttonStyle(GlassButtonStyle()).disabled(busy)
                        .help("Yalnızca “\(c.title)” kategorisini tarar; diğer sonuçlar korunur")
                    }
                    if case .category = filter {} else {
                        Button { model.startScan() } label: {
                            Label(model.phase == .idle ? "Taramayı başlat" : "Yeniden tara",
                                  systemImage: "arrow.clockwise").lineLimit(1).fixedSize()
                        }
                        .buttonStyle(GlassButtonStyle()).disabled(busy)
                    }
                    HStack(spacing: 8) {
                        Button { askAI(nil) } label: { Label("AI ile iyileştir", systemImage: "sparkles").lineLimit(1).fixedSize() }
                            .buttonStyle(GlassButtonStyle()).disabled(model.aiRunning)
                            .help(model.aiUnavailableReason ?? "Belirsiz öğeleri AI ile değerlendir")
                    }
                }
            }
            .padding(.horizontal, 26)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.aubergine.opacity(0.35), radius: 22, y: 10)
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
        .padding(.top, 12)
    }

    private func banner<Trailing: View>(icon: String, tint: Color, text: String,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 16, weight: .semibold))
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: İçerik

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle where model.smartFindings.isEmpty:
            emptyState(symbol: "externaldrive.badge.checkmark", title: "Henüz taranmadı",
                       message: "Gereksiz dosyaları bulmak için taramayı başlat.") {
                if case .category(let c) = filter {
                    Button("“\(c.title)” kategorisini tara") { model.startCategoryScan(c) }.buttonStyle(AuroraButtonStyle())
                } else {
                    Button("Taramayı başlat") { model.startScan() }.buttonStyle(AuroraButtonStyle())
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
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if case .all = filter {
                            categoryPills
                            ForEach(model.grouped, id: \.category) { group in
                                sectionHeader(group.category.title)
                                ForEach(group.items) { card($0) }
                            }
                        } else {
                            ForEach(visible) { card($0) }
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 130)
                }
            }
        }
    }

    private var categoryPills: some View {
        FlowLayout(spacing: 8) {
                ForEach(model.grouped, id: \.category) { group in
                    let c = group.category
                    Button { filter = .category(c) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: c.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(c.tint)
                            Text(c.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(Format.bytes(group.items.reduce(0) { $0 + $1.size }))
                                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.stroke))
                    }
                    .buttonStyle(.plain)
                }
        }
    }

    private func card(_ f: Finding) -> some View { FindingCard(finding: f) { askAI($0) } }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 10).padding(.leading, 4)
    }

    private func emptyState<Action: View>(symbol: String, title: String, message: String,
                                          @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 92, height: 92).background(Theme.aurora, in: Circle())
                .shadow(color: Theme.aubergine.opacity(0.4), radius: 18, y: 6)
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            action().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Mesaj kutusu (yüzen çubuk)

    private func composer(scope: ScanViewModel.Scope) -> some View {
        let count = scope == .smart ? model.selectedFindings.count : model.selectedLargeFindings.count
        let bytes = scope == .smart ? model.selectedBytes : model.selectedLargeBytes
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) öğe seçili")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(Format.bytes(bytes))
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if scope == .smart {
                Button("Güvenli olanları seç") {
                    model.selected = Set(model.smartFindings.filter { $0.confidence == .high && $0.impact.preselectable }.map(\.id))
                        .union(model.selectedLargeFindings.map(\.id))
                }.buttonStyle(SoftButtonStyle())
            }
            Button("Seçimi temizle") {
                let mine = Set((scope == .smart ? model.smartFindings : model.largeFindings).map(\.id))
                model.selected.subtract(mine)
            }
            .buttonStyle(SoftButtonStyle()).disabled(count == 0)
            Button { showConfirm = true } label: { Label("Çöp Kutusu'na taşı", systemImage: "trash.fill") }
                .buttonStyle(AuroraButtonStyle()).disabled(count == 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: Theme.aubergine.opacity(0.18), radius: 18, y: 8)
    }

    // MARK: Büyük öğeler (ayrı kapsam)

    private var thresholdLabel: String {
        let mb = model.settings.largeItemThresholdMB
        return mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB"
    }

    private var largeHero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.aurora)
            Circle().fill(Theme.coral.opacity(0.22)).frame(width: 230).offset(x: 430, y: -80)
            Circle().fill(Theme.amber.opacity(0.16)).frame(width: 150).offset(x: 320, y: 70)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Büyük öğeler • \(thresholdLabel) ve üzeri")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    Text(Format.bytes(model.largeBytes))
                        .font(.system(size: 44, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
                    Text("\(model.largeFindings.count) öğe • \(model.selectedLargeFindings.count) seçili • \(Format.bytes(model.selectedLargeBytes))")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    if model.isLargeScanning {
                        Button { model.cancelLargeScan() } label: { Label("İptal", systemImage: "xmark").lineLimit(1).fixedSize() }
                            .buttonStyle(GlassButtonStyle())
                    } else {
                        Button { model.startLargeScan() } label: {
                            Label(model.largeScanned ? "Yeniden tara" : "Taramayı başlat", systemImage: "arrow.clockwise").lineLimit(1).fixedSize()
                        }
                        .buttonStyle(GlassButtonStyle()).disabled(model.phase == .cleaning)
                    }
                    HStack(spacing: 8) {
                        Menu {
                            Picker("Eşik", selection: Bindable(model).settings.largeItemThresholdMB) {
                                Text("100 MB").tag(100); Text("500 MB").tag(500)
                                Text("1 GB").tag(1024); Text("5 GB").tag(5120)
                            }
                        } label: { Label("Eşik: \(thresholdLabel)", systemImage: "slider.horizontal.3").lineLimit(1).fixedSize() }
                            .menuStyle(.button).buttonStyle(GlassButtonStyle()).fixedSize()
                            .disabled(model.isLargeScanning)
                        Button { askAI(nil) } label: { Label("AI ile iyileştir", systemImage: "sparkles").lineLimit(1).fixedSize() }
                            .buttonStyle(GlassButtonStyle()).disabled(model.aiRunning)
                    }
                }
            }
            .padding(.horizontal, 26)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.aubergine.opacity(0.35), radius: 22, y: 10)
    }

    @ViewBuilder private var largeContent: some View {
        if model.isLargeScanning {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Ev dizininde büyük öğeler aranıyor… (günlük klasörler önce, Library en son)")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.largeFindings.isEmpty {
            emptyState(symbol: model.largeScanned ? "checkmark.circle.fill" : "externaldrive.badge.magnifyingglass",
                       title: model.largeScanned ? "Eşiğin üzerinde öğe yok" : "Henüz taranmadı",
                       message: model.largeScanned
                            ? "\(thresholdLabel) üzerinde klasör veya dosya bulunamadı."
                            : "Ev dizininde \(thresholdLabel) üzerindeki klasör ve dosyaları bulur. Yaklaşık bir dakika sürebilir.") {
                Button(model.largeScanned ? "Yeniden tara" : "Taramayı başlat") { model.startLargeScan() }
                    .buttonStyle(AuroraButtonStyle())
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Label("Hiçbiri otomatik seçilmez. Buradakiler kendi dosyaların olabilir; Çöp Kutusu'na taşıdıkların geri alınabilir.",
                          systemImage: "hand.raised.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).padding(.leading, 4)
                    ForEach(model.largeFindings) { card($0) }
                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 130)
            }
        }
    }
}
