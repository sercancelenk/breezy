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

/// Slack benzeri palet: patlıcan moru kenar çubuğu, beyaz (koyu modda #1A1D21) ana alan, yeşil birincil buton,
/// mavi seçim, kırmızı/sarı/camgöbeği vurgular.
enum Theme {
    static let aubergine = Color(hex: 0x3F0E40)
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

    static var canvas: Color { dynamic(light: 0xFFFFFF, dark: 0x1A1D21) }
    static var card: Color { dynamic(light: 0xF8F8F8, dark: 0x222529) }
    static var cardHover: Color { dynamic(light: 0xF2F2F2, dark: 0x2C2E33) }
    static var stroke: Color { dynamic(light: 0xDDDDDD, dark: 0x3A3C41) }
    static var textPrimary: Color { dynamic(light: 0x1D1C1D, dark: 0xD1D2D3) }
    static var textSecondary: Color { dynamic(light: 0x616061, dark: 0xABABAD) }
    static var sidebar: Color { dynamic(light: 0x3F0E40, dark: 0x19171D) }
    static var rail: Color { dynamic(light: 0x350D36, dark: 0x121016) }
    static var code: Color { dynamic(light: 0xE01E5A, dark: 0xF2668B) }

    /// Eski adla kullanılan dolgu; artık düz patlıcan moru.
    static var aurora: LinearGradient {
        LinearGradient(colors: [aubergine, indigo], startPoint: .top, endPoint: .bottom)
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

/// Birincil buton: Slack'in yeşil düz butonu.
struct AuroraButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(hovering ? Color(hex: 0x148567) : Theme.green, in: RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .onHover { hovering = $0 }
    }
}

/// İkincil buton: çerçeveli, düz.
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(hovering ? Theme.cardHover : Theme.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.stroke, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .onHover { hovering = $0 }
    }
}

// MARK: Parçalar

struct CardBackground: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(highlighted ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardBackground(highlighted: highlighted)) }
}

/// Slack'teki emoji tepkisi gibi çerçeveli küçük rozet.
struct Chip<Leading: View>: View {
    let text: String
    var tint: Color = Theme.textSecondary
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 5) {
            leading()
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.45), lineWidth: 1))
    }
}

struct ConfidencePill: View {
    let confidence: Confidence

    var body: some View {
        Chip(text: "Güven: \(confidence.title)", tint: confidence.tint) {
            Circle().fill(confidence.tint).frame(width: 7, height: 7)
        }
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
        Chip(text: impact.userData ? "Kullanıcı verisi olabilir" : impact.regeneration.title, tint: impact.tint) {
            Image(systemName: impact.regeneration == .never ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 10)).foregroundStyle(impact.tint)
            if impact.fromAI { Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(Theme.blue) }
        }
    }
}

/// Boyut: Slack'in satır içi kod biçimi.
struct SizeCode: View {
    let bytes: Int64

    var body: some View {
        Text(Format.bytes(bytes))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.code)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct CheckBox: View {
    let on: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(on ? Theme.green : Theme.canvas)
            RoundedRectangle(cornerRadius: 4).strokeBorder(on ? Theme.green : Theme.textSecondary.opacity(0.6), lineWidth: 1.5)
            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white) }
        }
        .frame(width: 18, height: 18)
    }
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
