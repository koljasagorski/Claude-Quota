import AppKit
import SwiftUI
import ClaudeMeterKit

// Renders the shipping SwiftUI views to PNGs for the README, plus the app icon.
//
//   swift run AssetGen
//
// Everything here draws the real views from ClaudeMeterKit, so the screenshots
// cannot drift away from what the app actually looks like.

@MainActor
func render<Content: View>(_ view: Content, scale: CGFloat = 2) -> NSImage? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    return renderer.nsImage
}

@MainActor
func write(_ image: NSImage?, to path: String) {
    guard let image,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: could not render \(path)\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    do {
        try png.write(to: url)
        print("  \(path)  \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}

/// A style shown the way a user meets it: menu bar on top, panel below.
struct StyleCard: View {
    let style: DesignStyle
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(style.code)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.11, green: 0.10, blue: 0.09)))
                    .foregroundColor(Color(red: 0.96, green: 0.955, blue: 0.945))
                Text(style.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(red: 0.106, green: 0.102, blue: 0.094))
                Spacer(minLength: 0)
                Text(style.footprint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 0.106, green: 0.102, blue: 0.094).opacity(0.45))
            }
            .padding(.bottom, 10)

            Text(style.summary)
                .font(.system(size: 13))
                .foregroundColor(Color(red: 0.106, green: 0.102, blue: 0.094).opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)

            Preview.MenuBarStrip(style: style, values: Preview.values(snapshot, now: now), colored: false)
                .frame(width: 344)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.bottom, 18)

            Preview.StaticPanel(style: style, snapshot: snapshot, now: now)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        }
        .padding(22)
        // Fixed height so cards in a row share a baseline; the tallest panel
        // (Reset-Countdown) sets the floor.
        .frame(width: 388, height: 470, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(red: 0.078, green: 0.07, blue: 0.063).opacity(0.09), lineWidth: 1)
                )
        )
    }
}

struct Overview: View {
    let snapshot: UsageSnapshot
    let now: Date
    private let paper = Color(red: 0.957, green: 0.949, blue: 0.933)

    private var rows: [[DesignStyle]] {
        stride(from: 0, to: DesignStyle.allCases.count, by: 3).map {
            Array(DesignStyle.allCases[$0..<min($0 + 3, DesignStyle.allCases.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("SECHS DARSTELLUNGEN · UMSCHALTBAR IN DEN EINSTELLUNGEN")
                    .font(.system(size: 11, design: .monospaced))
                    .kerning(1.5)
                    .foregroundColor(Color(red: 0.106, green: 0.102, blue: 0.094).opacity(0.45))
                Text("ClaudeMeter")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(Color(red: 0.106, green: 0.102, blue: 0.094))
                Text("Jede Variante zeigt dasselbe: das rollierende 5-Std-Fenster, das Wochenlimit und den nächsten Reset. Unterschiedlich ist nur, wie viel davon dauerhaft in der Menüleiste steht.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(red: 0.106, green: 0.102, blue: 0.094).opacity(0.6))
                    .frame(maxWidth: 760, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(row) { StyleCard(style: $0, snapshot: snapshot, now: now) }
                }
            }
        }
        .padding(56)
        .background(paper)
    }
}

@MainActor
func makeIcon() {
    let sizes: [(Int, String)] = [
        (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
        (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
        (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")
    ]
    let iconset = "build/AppIcon.iconset"
    try? FileManager.default.removeItem(atPath: iconset)
    for (pixels, name) in sizes {
        write(render(Preview.AppIcon(size: CGFloat(pixels)), scale: 1), to: "\(iconset)/\(name).png")
    }
    write(render(Preview.AppIcon(size: 512), scale: 2), to: "assets/icon.png")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
    try? process.run()
    process.waitUntilExit()
    print(process.terminationStatus == 0 ? "  Resources/AppIcon.icns" : "  iconutil failed")
}

@MainActor
func generateAssets() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    // Pinned so the mock menu-bar clock ("Mi 19. Aug 14:32") agrees with the
    // rendered reset times, and so regenerating assets produces byte-identical
    // PNGs instead of git churn.
    var components = DateComponents()
    components.year = 2026; components.month = 8; components.day = 19
    components.hour = 14; components.minute = 32
    let now = Formatting.calendar.date(from: components) ?? Date()
    let snapshot = Preview.demoSnapshot(now: now)

    print("Rendering per-style assets…")
    for style in DesignStyle.allCases {
        write(render(Preview.MenuBarStrip(style: style,
                                          values: Preview.values(snapshot, now: now),
                                          colored: false).frame(width: 344)),
              to: "assets/menubar-\(style.rawValue).png")
        write(render(Preview.StaticPanel(style: style, snapshot: snapshot, now: now)),
              to: "assets/panel-\(style.rawValue).png")
    }

    print("Rendering overview…")
    write(render(Overview(snapshot: snapshot, now: now)), to: "assets/styles-overview.png")

    print("Rendering icon…")
    makeIcon()

    print("Done.")
}

MainActor.assumeIsolated { generateAssets() }
