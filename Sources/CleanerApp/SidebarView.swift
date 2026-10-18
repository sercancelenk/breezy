import SwiftUI
import AppModel
import CleanerCore

enum SidebarFilter: Hashable {
    case all
    case category(FindingCategory)
}

struct SidebarView: View {
    @Environment(ScanViewModel.self) private var model
    @Binding var filter: SidebarFilter
    let hasFDA: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            brand.padding(.top, 34).padding(.bottom, 14)

            row(title: "Genel bakış", symbol: "sparkles", tint: Theme.coral,
                count: model.findings.count, bytes: model.totalBytes, value: .all)

            Text("KATEGORİLER")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 14).padding(.leading, 12)

            ForEach(FindingCategory.allCases, id: \.self) { c in
                let items = model.findings.filter { $0.category == c }
                row(title: c.title, symbol: c.symbol, tint: c.tint, count: items.count,
                    bytes: items.reduce(0) { $0 + $1.size }, value: .category(c))
            }

            Spacer()
            footer
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar.ignoresSafeArea())
    }

    private var brand: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.aurora)
                Image(systemName: "wind").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .shadow(color: Theme.magenta.opacity(0.5), radius: 10, y: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Cleaner").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("Disk temizleyici").font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.leading, 6)
    }

    private func row(title: String, symbol: String, tint: Color, count: Int, bytes: Int64,
                     value: SidebarFilter) -> some View {
        let selected = filter == value
        return Button { filter = value } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                    if count > 0 {
                        Text(Format.bytes(bytes)).font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.magenta, in: Capsule())
                }
            }
            .foregroundStyle(.white.opacity(count > 0 || value == .all ? 1 : 0.5))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(hasFDA ? Theme.mint : Theme.amber).frame(width: 8, height: 8)
                Text(hasFDA ? "Tam Disk Erişimi açık" : "Tam Disk Erişimi gerekli")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.leading, 6)
            SettingsLink {
                Label("Ayarlar", systemImage: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }
}
