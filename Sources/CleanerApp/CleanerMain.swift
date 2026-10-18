import SwiftUI
import AppModel
import Preferences

@main
struct CleanerMain: App {
    @State private var model = ScanViewModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 740)
                .tint(Theme.violet)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.violet)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
    }
}

extension AppearanceMode {
    /// nil = sistem görünümünü takip et.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
