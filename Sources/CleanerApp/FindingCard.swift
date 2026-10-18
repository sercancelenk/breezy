import SwiftUI
import AppModel
import CleanerCore

/// Sohbet listesi satırı gibi bir kart: seçim dairesi, avatar, başlık/alt metin, boyut ve güven hapı.
struct FindingCard: View {
    @Environment(ScanViewModel.self) private var model
    let finding: Finding
    @State private var hovering = false

    private var isOn: Bool { model.selected.contains(finding.id) }

    var body: some View {
        HStack(spacing: 14) {
            CheckCircle(on: isOn)

            Image(systemName: finding.category.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(finding.category.tint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(finding.url.lastPathComponent)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text((finding.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                Text(finding.reason)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textSecondary).lineLimit(1)
                if !finding.impact.note.isEmpty {
                    Text("Silersen: \(finding.impact.note)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(finding.impact.tint).lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Format.bytes(finding.size))
                    .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                ConfidencePill(confidence: finding.confidence)
                ImpactPill(impact: finding.impact)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .card(highlighted: hovering || isOn)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.violet.opacity(isOn ? 0.55 : 0), lineWidth: 1.5))
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
