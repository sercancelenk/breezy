import Foundation

public enum AppearanceMode: String, Codable, Sendable, CaseIterable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }
}

public struct SettingsData: Codable, Sendable, Equatable {
    public var profiles: [ProviderProfile]
    public var activeProfileID: UUID?
    public var aiEnabled: Bool
    public var scanRoots: [String]
    public var excludedPaths: [String]
    /// MB; 0 = büyük öğe taraması kapalı.
    public var largeItemThresholdMB: Int
    public var appearance: AppearanceMode

    public init(profiles: [ProviderProfile] = [], activeProfileID: UUID? = nil, aiEnabled: Bool = false,
                scanRoots: [String] = [], excludedPaths: [String] = [], largeItemThresholdMB: Int = 1024,
                appearance: AppearanceMode = .system) {
        self.profiles = profiles; self.activeProfileID = activeProfileID; self.aiEnabled = aiEnabled
        self.scanRoots = scanRoots; self.excludedPaths = excludedPaths
        self.largeItemThresholdMB = largeItemThresholdMB; self.appearance = appearance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decodeIfPresent([ProviderProfile].self, forKey: .profiles) ?? []
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        aiEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? false
        scanRoots = try c.decodeIfPresent([String].self, forKey: .scanRoots) ?? []
        excludedPaths = try c.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        largeItemThresholdMB = try c.decodeIfPresent(Int.self, forKey: .largeItemThresholdMB) ?? 1024
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
    }

    public var activeProfile: ProviderProfile? { profiles.first { $0.id == activeProfileID } }

    public static func defaults(home: URL) -> SettingsData {
        let candidates = ["Developer", "development", "dev", "Projects", "projects",
                          "workspace", "workspaces", "src", "code", "Documents", "Desktop"]
        let roots = candidates.map { home.appendingPathComponent($0).path }
            .filter { FileManager.default.fileExists(atPath: $0) }
        return SettingsData(scanRoots: roots)
    }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static var standard: SettingsStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SettingsStore(fileURL: base.appendingPathComponent("CleanerApp/settings.json"))
    }

    public func load(home: URL) -> SettingsData {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data)
        else { return .defaults(home: home) }
        return decoded
    }

    public func save(_ settings: SettingsData) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(settings).write(to: fileURL, options: .atomic)
    }
}
