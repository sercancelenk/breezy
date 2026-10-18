// 1024px simge PNG'si üretir (scripts/make-icon.sh çağırır): swift scripts/make-icon.swift out.png
import SwiftUI
import AppKit

struct Icon: View {
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 185, style: .continuous) }

    var body: some View {
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(red: 0.38, green: 0.12, blue: 0.41), Color(red: 0.19, green: 0.04, blue: 0.20)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 824, height: 824)
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 4))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
            Capsule().fill(Color(red: 0.18, green: 0.71, blue: 0.49)).frame(width: 150, height: 34).offset(x: 190, y: 190)
            Capsule().fill(Color(red: 0.93, green: 0.70, blue: 0.18)).frame(width: 90, height: 34).offset(x: 250, y: 250)
            Image(systemName: "wind")
                .font(.system(size: 470, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 8)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render(to out: String) {
    let r = ImageRenderer(content: Icon())
    r.scale = 1
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("render failed") }
    try! png.write(to: URL(fileURLWithPath: out))
}

MainActor.assumeIsolated { render(to: CommandLine.arguments[1]) }
