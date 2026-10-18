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

/// "Aurora" paleti: derin indigo zemin, violet → magenta → coral geçişi, sıcak amber ve serin teal vurgular.
enum Theme {
    static let ink = Color(hex: 0x1B1340)
    static let indigo = Color(hex: 0x2A1B5E)
    static let violet = Color(hex: 0x7C3AED)
    static let magenta = Color(hex: 0xEC4899)
    static let coral = Color(hex: 0xFB7185)
    static let amber = Color(hex: 0xF59E0B)
    static let teal = Color(hex: 0x14B8A6)
    static let mint = Color(hex: 0x34D399)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    static var canvas: Color { dynamic(light: 0xF6F3FF, dark: 0x15112B) }
    static var card: Color { dynamic(light: 0xFFFFFF, dark: 0x221B47) }
    static var cardHover: Color { dynamic(light: 0xF0EAFF, dark: 0x2B2358) }
    static var stroke: Color { dynamic(light: 0xE6DFFB, dark: 0x3A3070) }
    static var textPrimary: Color { dynamic(light: 0x1B1340, dark: 0xF4F1FF) }
    static var textSecondary: Color { dynamic(light: 0x6B6490, dark: 0xA9A2D3) }

    static var aurora: LinearGradient {
        LinearGradient(colors: [violet, magenta, coral], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var sidebar: LinearGradient {
        LinearGradient(colors: [indigo, ink], startPoint: .top, endPoint: .bottom)
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
        }
    }

    var tint: Color {
        switch self {
        case .cache: Theme.violet
        case .logs: Theme.amber
        case .homebrew: Theme.coral
        case .xcode: Theme.teal
        case .devArtifact: Theme.magenta
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

/// Birincil buton: aurora gradient kapsül, parlama gölgesi, basınca küçülür.
struct AuroraButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Theme.aurora, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.45 : 0.2), lineWidth: 1))
            .shadow(color: Theme.magenta.opacity(isEnabled ? 0.45 : 0), radius: hovering ? 16 : 10, y: 4)
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
            .font(.system(size: 13, weight: .medium, design: .rounded))
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

/// Gradient üstündeki buton: yarı saydam beyaz cam kapsül.
struct GlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
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
            .shadow(color: Theme.ink.opacity(0.06), radius: 8, y: 3)
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
            Text(confidence.title)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(confidence.tint.opacity(0.18), in: Capsule())
    }
}

/// WhatsApp'taki seçim işareti gibi yuvarlak onay.
struct CheckCircle: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Color.clear : Theme.stroke, lineWidth: 2)
            if on {
                Circle().fill(Theme.aurora)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.spring(duration: 0.2), value: on)
    }
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
