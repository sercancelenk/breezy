import SwiftUI
import RunningApps
import CleanerCore

struct RunningAppsView: View {
    @State private var apps: [RunningApp] = []
    @State private var forceTarget: RunningApp?
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Çalışan uygulamalar").font(.system(size: 26, weight: .bold))
                Text("En çok bellek kullananlar. Kapat: uygulamaya nazikçe kapanmasını söyler. Zorla kapat: anında sonlandırır, kaydedilmemiş işler kaybolabilir.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.top, 30)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(apps) { row($0) }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .task { refresh() }
        .onReceive(timer) { _ in refresh() }
        .alert("Zorla kapatılsın mı?", isPresented: Binding(get: { forceTarget != nil }, set: { if !$0 { forceTarget = nil } })) {
            Button("Zorla kapat", role: .destructive) {
                if let app = forceTarget { RunningApps.quit(pid: app.pid, force: true); refreshSoon() }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("\(forceTarget?.name ?? "") anında sonlandırılır; kaydedilmemiş değişiklikler kaybolur.") }
    }

    private func row(_ app: RunningApp) -> some View {
        HStack(spacing: 12) {
            if let icon = NSRunningApplication(processIdentifier: app.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
            }
            Text(app.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Spacer()
            Text(Format.bytes(app.memoryBytes)).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
            Button("Kapat") { RunningApps.quit(pid: app.pid, force: false); refreshSoon() }
            Button("Zorla kapat", role: .destructive) { forceTarget = app }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func refresh() { apps = RunningApps.list() }

    private func refreshSoon() {
        Task { try? await Task.sleep(for: .seconds(1)); refresh() }
    }
}
