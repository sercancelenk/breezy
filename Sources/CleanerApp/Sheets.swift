import SwiftUI
import AppModel
import AI
import CleanerCore

struct ConfirmSheet: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let run = model.dryRun()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(Theme.aurora, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Çöp Kutusu'na taşı").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("\(run.allowed.count) öğe • \(Format.bytes(run.totalBytes))")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textSecondary)
                }
            }
            Text("Öğeler silinmez, Çöp Kutusu'na taşınır ve oradan geri alınabilir. Alan, Çöp Kutusu'nu boşaltınca açılır.")
                .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textSecondary)
            if !run.rejected.isEmpty {
                Text("Güvenlik nedeniyle atlanacak: \(run.rejected.count) öğe")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.coral)
            }
            let risky = run.allowed.filter { $0.impact.regeneration == .never || $0.impact.risk >= .medium }
            if !risky.isEmpty {
                Label("\(risky.count) öğe geri gelmeyebilir veya uygulamayı etkileyebilir; listede işaretli.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.amber)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(run.allowed) { f in
                        HStack {
                            if f.impact.regeneration == .never || f.impact.risk >= .medium {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(f.impact.tint)
                            }
                            Image(systemName: f.category.symbol).foregroundStyle(f.category.tint)
                            Text(f.url.lastPathComponent).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(f.size)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                        .font(.system(size: 13, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .card()
                    }
                }
                .padding(2)
            }
            .frame(height: 200)
            HStack {
                Spacer()
                Button("İptal") { dismiss() }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Çöp Kutusu'na taşı") {
                    dismiss()
                    Task { await model.clean() }
                }
                .buttonStyle(AuroraButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(run.allowed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(Theme.canvas)
    }
}

struct AIPreviewSheet: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: AIPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(Theme.aurora, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI'a gönderilecek veri").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Yalnızca metadata gider; dosya içeriği gönderilmez.")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textSecondary)
                }
            }
            ScrollView {
                Text(prompt.preview)
                    .font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            .frame(height: 280)
            .card()
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Gönder") {
                    dismiss()
                    Task { await model.runAI(prompt) }
                }
                .buttonStyle(AuroraButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(Theme.canvas)
    }
}
