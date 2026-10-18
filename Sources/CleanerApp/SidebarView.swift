import SwiftUI
import AppModel
import CleanerCore

enum SidebarFilter: Hashable {
    case all
    case category(FindingCategory)
}

/// Solda Slack'teki gibi iki sütun: dar çalışma alanı rayı ve kanal listesi.
struct SidebarView: View {
    @Environment(ScanViewModel.self) private var model
    @Binding var filter: SidebarFilter
    let hasFDA: Bool
    @State private var showPrivacy = false

    private let muted = Color.white.opacity(0.7)

    var body: some View {
        HStack(spacing: 0) {
            rail.frame(width: 68)
            channels.frame(width: 264)
        }
        .frame(maxHeight: .infinity)
    }

    private var rail: some View {
        VStack(spacing: 14) {
            Text("C")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.aubergine)
                .frame(width: 40, height: 40)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape.fill").font(.system(size: 17)).foregroundStyle(muted)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain).help("Ayarlar")
        }
        .padding(.top, 38).padding(.bottom, 14)
        .frame(maxHeight: .infinity)
        .background(Theme.rail.ignoresSafeArea())
    }

    private var channels: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Cleaner").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(muted)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 38).padding(.bottom, 12)
            Divider().overlay(Color.white.opacity(0.12))

            row(title: "Genel bakış", icon: "house.fill", count: model.findings.count, value: .all)
                .padding(.top, 10)

            Text("▾  Kategoriler")
                .font(.system(size: 14)).foregroundStyle(muted)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)

            ForEach(FindingCategory.allCases, id: \.self) { c in
                let n = model.findings.filter { $0.category == c }.count
                row(title: c.title, icon: nil, count: n, value: .category(c))
            }

            Spacer()
            Button { showPrivacy = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.mint)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Verilerin bu Mac'ten çıkmaz").font(.system(size: 13, weight: .semibold))
                        Text("Gizlilik ve güvenlik").font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPrivacy) { PrivacySheet() }
            HStack(spacing: 8) {
                Circle().fill(hasFDA ? Theme.mint : Theme.amber).frame(width: 9, height: 9)
                Text(hasFDA ? "Tam Disk Erişimi açık" : "Tam Disk Erişimi gerekli")
                    .font(.system(size: 13)).foregroundStyle(muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar.ignoresSafeArea())
    }

    private func row(title: String, icon: String?, count: Int, value: SidebarFilter) -> some View {
        let selected = filter == value
        let unread = count > 0
        return Button { filter = value } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12)).frame(width: 16)
                } else {
                    Text("#").font(.system(size: 16, weight: .regular)).frame(width: 16)
                }
                Text(title).font(.system(size: 14, weight: unread || selected ? .bold : .regular)).lineLimit(1)
                Spacer()
                if unread {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color(hex: 0xCD2553), in: Capsule())
                }
            }
            .foregroundStyle(selected ? .white : (unread ? .white : muted))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
