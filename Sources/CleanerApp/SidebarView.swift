import SwiftUI
import AppModel
import CleanerCore

enum SidebarFilter: Hashable {
    case all
    case category(FindingCategory)
    case large
    case apps
}

struct SidebarView: View {
    @Environment(ScanViewModel.self) private var model
    @Binding var filter: SidebarFilter
    let hasFDA: Bool
    @State private var showPrivacy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            brand.padding(.top, 30).padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    row(title: "Genel bakış", symbol: "sparkles", tint: Theme.coral,
                        count: model.smartFindings.count, bytes: model.totalBytes, value: .all)

                    ForEach(Self.groups, id: \.title) { g in
                        header(g.title)
                        ForEach(g.categories, id: \.self) { c in
                            let items = model.smartFindings.filter { $0.category == c }
                            row(title: c.title, symbol: c.symbol, tint: c.tint, count: items.count,
                                bytes: items.reduce(0) { $0 + $1.size }, value: .category(c))
                        }
                        if g.title == Self.filesGroup {
                            row(title: "Büyük öğeler", symbol: FindingCategory.large.symbol, tint: FindingCategory.large.tint,
                                count: model.largeFindings.count, bytes: model.largeBytes, value: .large,
                                busy: model.isLargeScanning)
                        }
                    }

                    header("ARAÇLAR")
                    row(title: "Çalışan uygulamalar", symbol: "memorychip", tint: Theme.teal,
                        count: 0, bytes: 0, value: .apps)
                }
            }

            footer
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
        .frame(width: 296)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar.ignoresSafeArea())
    }

    private static let filesGroup = "DOSYALARIM"
    private static let groups: [(title: String, categories: [FindingCategory])] = [
        ("SİSTEM VE UYGULAMALAR", [.cache, .logs, .backup]),
        ("GELİŞTİRİCİ", [.xcode, .devArtifact, .homebrew]),
        (filesGroup, [.installers, .downloads, .documents]),
    ]

    private func header(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(.white.opacity(0.15))
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.leading, 12)
        }
        .padding(.top, 12)
    }

    private var brand: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                Image(systemName: "wind").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.aubergine)
            }
            .frame(width: 40, height: 40)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Breezy").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Text("Mac'ini ferah tut").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.leading, 6)
    }

    private func row(title: String, symbol: String, tint: Color, count: Int, bytes: Int64,
                     value: SidebarFilter, busy: Bool = false) -> some View {
        let selected = filter == value
        return Button { filter = value } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if count > 0 {
                        Text(Format.bytes(bytes)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                if busy { ProgressView().controlSize(.small).tint(.white) }
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color(hex: 0xCD2553), in: Capsule())
                }
            }
            .foregroundStyle(.white.opacity(count > 0 || value == .all || value == .apps ? 1 : 0.5))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showPrivacy = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.mint)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Verilerin bu Mac'ten çıkmaz").font(.system(size: 12, weight: .semibold))
                        Text("Gizlilik ve güvenlik").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPrivacy) { PrivacySheet() }
            HStack(spacing: 8) {
                Circle().fill(hasFDA ? Theme.mint : Theme.amber).frame(width: 8, height: 8)
                Text(hasFDA ? "Tam Disk Erişimi açık" : "Tam Disk Erişimi gerekli")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.leading, 6)
            SettingsLink {
                Label("Ayarlar", systemImage: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }
}
