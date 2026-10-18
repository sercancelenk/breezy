import SwiftUI
import AppKit
import CleanerCore

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Slack renkleri: patlıcan moru zemin, mavi seçim, yeşil birincil, kırmızı/sarı/camgöbeği vurgular.
/// Yerleşim "Aurora" düzenidir: degradeli kenar çubuğu, sohbet kartı satırları, hero kartı, yüzen mesaj kutusu.
enum Theme {
    static let aubergine = Color(hex: 0x3F0E40)
    static let plum = Color(hex: 0x611F69)
    static let green = Color(hex: 0x007A5A)
    static let blue = Color(hex: 0x1264A3)
    static let selection = Color(hex: 0x1164A3)

    // Başka dosyalarda kullanılan vurgu adları
    static let violet = blue
    static let coral = Color(hex: 0xE01E5A)
    static let magenta = Color(hex: 0xE01E5A)
    static let amber = Color(hex: 0xECB22E)
    static let mint = Color(hex: 0x2EB67D)
    static let teal = Color(hex: 0x36C5F0)
    static let indigo = Color(hex: 0x611F69)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    static var canvas: Color { dynamic(light: 0xF8F8F8, dark: 0x1A1D21) }
    static var card: Color { dynamic(light: 0xFFFFFF, dark: 0x222529) }
    static var cardHover: Color { dynamic(light: 0xF1EEF2, dark: 0x2C2E33) }
    static var stroke: Color { dynamic(light: 0xE3E0E4, dark: 0x3A3C41) }
    static var textPrimary: Color { dynamic(light: 0x1D1C1D, dark: 0xD1D2D3) }
    static var textSecondary: Color { dynamic(light: 0x616061, dark: 0xABABAD) }
    static var code: Color { dynamic(light: 0xE01E5A, dark: 0xF2668B) }

    /// Hero kartı ve simge daireleri: patlıcan moru degradesi.
    static var aurora: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x4A154B), plum, Color(hex: 0x7F2F82)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var sidebar: LinearGradient {
        LinearGradient(colors: [dynamic(light: 0x4A154B, dark: 0x1F1B24), dynamic(light: 0x2B0A2C, dark: 0x121016)],
                       startPoint: .top, endPoint: .bottom)
    }
}

extension FindingCategory {
    var symbol: String {
        switch self {
        case .cache: "archivebox.fill"
        case .logs: "doc.text.fill"
        case .homebrew: "cup.and.saucer.fill"
        case .xcode: "hammer.fill"
        case .devArtifact: "shippingbox.fill"
        case .large: "externaldrive.fill"
        case .backup: "iphone.gen3"
        case .installers: "arrow.down.app.fill"
        case .downloads: "arrow.down.circle.fill"
        case .documents: "doc.fill"
        }
    }

    var tint: Color {
        switch self {
        case .cache: Theme.blue
        case .logs: Theme.amber
        case .homebrew: Theme.coral
        case .xcode: Theme.teal
        case .devArtifact: Theme.mint
        case .large: Theme.coral
        case .backup: Theme.indigo
        case .installers: Theme.teal
        case .downloads: Theme.blue
        case .documents: Theme.amber
        }
    }
}

extension Confidence {
    var tint: Color {
        switch self {
        case .high: Theme.mint
        case .medium: Theme.amber
        case .low: Theme.coral
        }
    }
}

// MARK: Buton stilleri

/// Birincil buton: Slack yeşili kapsül, basınca küçülür.
struct AuroraButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(hovering ? Color(hex: 0x148567) : Theme.green, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.35 : 0.15), lineWidth: 1))
            .shadow(color: Theme.green.opacity(isEnabled ? 0.35 : 0), radius: hovering ? 12 : 7, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// İkincil buton: açık/koyu temaya uyumlu yumuşak kapsül.
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(hovering ? Theme.cardHover : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// Degrade üstündeki buton: yarı saydam beyaz cam kapsül.
struct GlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(.white.opacity(hovering ? 0.32 : 0.2), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

// MARK: Parçalar

struct CardBackground: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(highlighted ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .shadow(color: Theme.aubergine.opacity(0.07), radius: 8, y: 3)
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardBackground(highlighted: highlighted)) }
}

struct ConfidencePill: View {
    let confidence: Confidence

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(confidence.tint).frame(width: 7, height: 7)
            Text("Güven: \(confidence.title)")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(confidence.tint.opacity(0.18), in: Capsule())
        .help("Güven: bu öğenin silinmesinin güvenli olduğuna dair kural/AI güveni. Yüksek olanlar varsayılan seçili gelir; Düşük olanları dikkatle incele.")
    }
}

extension Impact {
    var tint: Color {
        if regeneration == .never || risk >= .high || userData { return Theme.coral }
        if regeneration == .manual || risk >= .medium { return Theme.amber }
        return Theme.mint
    }
}

/// "Silersem ne olur?" rozeti: geri gelme durumu ve (AI değerlendirdiyse) ✨.
struct ImpactPill: View {
    let impact: Impact

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: impact.regeneration == .never ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
            Text(impact.userData ? "Kullanıcı verisi olabilir" : impact.regeneration.title)
            if impact.fromAI { Image(systemName: "sparkles") }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(impact.tint.opacity(0.18), in: Capsule())
    }
}

/// Seçim işareti gibi yuvarlak onay.
struct CheckCircle: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Color.clear : Theme.stroke, lineWidth: 2)
            if on {
                Circle().fill(Theme.green)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.spring(duration: 0.2), value: on)
    }
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        n == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
