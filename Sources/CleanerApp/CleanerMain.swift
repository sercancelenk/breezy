import SwiftUI
import AppModel
import Preferences
import DiskMonitor

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains(DiskAlert.checkArgument) {
            Task { await DiskAlert.checkAndNotify(); exit(0) }
            dispatchMain()
        }
        CleanerMain.main()
    }
}

struct CleanerMain: App {
    @State private var model = ScanViewModel.live()

    init() { DiskAlert.setUp() }

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
