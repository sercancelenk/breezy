import SwiftUI
import AppModel

@main
struct CleanerMain: App {
    @State private var model = ScanViewModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 600)
                .tint(Theme.violet)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.violet)
        }
    }
}
