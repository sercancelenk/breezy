import SwiftUI
import AppModel
import CleanerCore

/// Slack'teki bir mesaj gibi: kare avatar, kalın ad + zaman, gövde metni, tepki rozetleri ve üzerine gelince araç çubuğu.
struct FindingCard: View {
    @Environment(ScanViewModel.self) private var model
    let finding: Finding
    var onAskAI: ((Finding) -> Void)?
    @State private var hovering = false

    private var isOn: Bool { model.selected.contains(finding.id) }

    private var when: String {
        finding.lastModified?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "tr_TR"))) ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CheckBox(on: isOn).padding(.top, 9)

            Image(systemName: finding.category.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(finding.category.tint, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(finding.url.lastPathComponent)
                        .font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if !when.isEmpty {
                        Text(when).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    SizeCode(bytes: finding.size)
                }
                Text((finding.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(finding.reason).font(.system(size: 15)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                if !finding.impact.note.isEmpty {
                    (Text("Silersen: ").bold().foregroundStyle(finding.impact.tint)
                        + Text(finding.impact.note).foregroundStyle(Theme.textPrimary))
                        .font(.system(size: 14)).lineLimit(3)
                }
                HStack(spacing: 6) {
                    ConfidencePill(confidence: finding.confidence)
                    ImpactPill(impact: finding.impact)
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(isOn ? Theme.blue.opacity(0.08) : (hovering ? Theme.card : .clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.blue).frame(width: 3).opacity(isOn ? 1 : 0)
        }
        .overlay(alignment: .topTrailing) { if hovering { toolbar.padding(.trailing, 20).offset(y: -8) } }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if isOn { model.selected.remove(finding.id) } else { model.selected.insert(finding.id) }
        }
        .contextMenu {
            Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
        }
    }

    /// Slack'in mesaj üzerine gelince çıkan eylem çubuğu.
    private var toolbar: some View {
        HStack(spacing: 2) {
            if let ask = onAskAI {
                Button { ask(finding) } label: { Image(systemName: "sparkles").frame(width: 28, height: 26) }
                    .help("AI'a sor: bu öğe için görüş al (önce gönderilecek metni görürsün)")
                    .disabled(model.aiRunning)
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) } label: {
                Image(systemName: "folder").frame(width: 28, height: 26)
            }
            .help("Finder'da göster")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .padding(2)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}
