import SwiftUI
import AppModel
import CleanerCore

/// Sohbet listesi satırı gibi bir kart: seçim dairesi, avatar, başlık/alt metin, boyut ve rozetler.
struct FindingCard: View {
    @Environment(ScanViewModel.self) private var model
    let finding: Finding
    var onAskAI: ((Finding) -> Void)?
    @State private var hovering = false

    private var isOn: Bool { model.selected.contains(finding.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CheckCircle(on: isOn).padding(.top, 11)

            Image(systemName: finding.category.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(finding.category.tint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(finding.url.lastPathComponent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text((finding.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                Text(finding.reason)
                    .font(.system(size: 13)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                if !finding.impact.note.isEmpty {
                    Text("\(Text("Silersen: ").bold().foregroundStyle(finding.impact.tint))\(Text(finding.impact.note).foregroundStyle(Theme.textSecondary))")
                        .font(.system(size: 12.5)).lineLimit(3)
                }
                HStack(spacing: 6) {
                    ConfidencePill(confidence: finding.confidence)
                    ImpactPill(impact: finding.impact)
                    if let ask = onAskAI {
                        Button { ask(finding) } label: { Label("AI'a sor", systemImage: "sparkles") }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .disabled(model.aiRunning)
                            .help("Bu öğe için AI görüşü al (önce gönderilecek metni görürsün)")
                    }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 12)
            Text(Format.bytes(finding.size))
                .font(.system(size: 15, weight: .bold)).monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .card(highlighted: hovering || isOn)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.green.opacity(isOn ? 0.6 : 0), lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture {
            if isOn { model.selected.remove(finding.id) } else { model.selected.insert(finding.id) }
        }
        .contextMenu {
            Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
