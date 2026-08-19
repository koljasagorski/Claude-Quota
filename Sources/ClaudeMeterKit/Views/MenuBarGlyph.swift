import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Colours used while drawing a menu-bar glyph.
///
/// In template mode everything is drawn in black at varying alpha: macOS uses
/// only the alpha channel and tints the result itself, so the glyph stays
/// correct in light mode, dark mode and behind a tinted menu bar. Forcing real
/// colours breaks all three, which is why colour is opt-in.
public struct GlyphPalette {
    public let session: Color
    public let weekly: Color
    public let track: Color
    public let isTemplate: Bool

    public static let template = GlyphPalette(
        session: .black,
        weekly: .black,
        track: .black.opacity(0.26),
        isTemplate: true
    )

    /// Mid-tone colours chosen to stay legible on both light and dark menu bars.
    public static func colored(sessionWarning: Bool, weeklyWarning: Bool) -> GlyphPalette {
        GlyphPalette(
            session: sessionWarning ? Theme.warning : Theme.session,
            weekly: weeklyWarning ? Theme.warning : Theme.weekly,
            track: Color(white: 0.5).opacity(0.45),
            isTemplate: false
        )
    }
}

/// The numbers a glyph needs, already normalised.
public struct GlyphValues {
    public let sessionFraction: Double   // 0…1
    public let weeklyFraction: Double    // 0…1
    public let countdown: String
    public let hasData: Bool

    public init(sessionFraction: Double, weeklyFraction: Double, countdown: String, hasData: Bool) {
        self.sessionFraction = min(1, max(0, sessionFraction))
        self.weeklyFraction = min(1, max(0, weeklyFraction))
        self.countdown = countdown
        self.hasData = hasData
    }

    public static func from(_ snapshot: UsageSnapshot?, now: Date) -> GlyphValues {
        GlyphValues(
            sessionFraction: (snapshot?.session?.percent ?? 0) / 100,
            weeklyFraction: (snapshot?.weekly?.percent ?? 0) / 100,
            countdown: Formatting.compactCountdown(snapshot?.session?.resetsAt, now: now),
            hasData: snapshot != nil
        )
    }
}

// MARK: - 1a Doppelbalken

struct DoppelbalkenGlyph: View {
    let values: GlyphValues
    let palette: GlyphPalette
    static let size = CGSize(width: 22, height: 9)

    var body: some View {
        VStack(spacing: 3) {
            bar(values.sessionFraction, color: palette.session)
            bar(values.weeklyFraction, color: palette.weekly)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func bar(_ fraction: Double, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule().fill(color).frame(width: max(fraction > 0 ? 2 : 0, geometry.size.width * fraction))
            }
        }
        .frame(height: 3)
    }
}

// MARK: - 1b dot (the number itself is drawn natively next to it)

struct DotGlyph: View {
    let color: Color
    static let size = CGSize(width: 6, height: 6)

    var body: some View {
        Circle().fill(color).frame(width: Self.size.width, height: Self.size.height)
    }
}

// MARK: - 1c Doppelring

struct DoppelringGlyph: View {
    let values: GlyphValues
    let palette: GlyphPalette
    static let size = CGSize(width: 15, height: 15)

    var body: some View {
        ZStack {
            ring(radius: 6.2, lineWidth: 1.6, fraction: values.sessionFraction, color: palette.session)
            ring(radius: 3.4, lineWidth: 1.6, fraction: values.weeklyFraction, color: palette.weekly)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func ring(radius: CGFloat, lineWidth: CGFloat, fraction: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(palette.track, lineWidth: lineWidth)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: max(fraction > 0 ? 0.02 : 0, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - 1d Reset-Countdown

struct CountdownGlyph: View {
    let values: GlyphValues
    let palette: GlyphPalette
    static let size = CGSize(width: 38, height: 15)

    /// This is the only glyph that puts text *on top* of the accent colours.
    /// In template mode alpha does the work and macOS tints it. In colour mode
    /// the pill must supply its own dark ground: the shared mid-tone track is
    /// only ~1.7:1 against white text over a light menu bar, so the countdown —
    /// the sole information this style carries — would be unreadable.
    private var pillTrack: Color {
        palette.isTemplate ? palette.track : Color(white: 0.14).opacity(0.88)
    }

    private var pillFill: Color {
        palette.session.opacity(palette.isTemplate ? 0.55 : 0.85)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(pillTrack)
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(pillFill)
                    .frame(width: geometry.size.width * values.sessionFraction)
            }
            Text(values.countdown)
                .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                .foregroundColor(palette.isTemplate ? .black : .white)
                .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - 1e Segmente

struct SegmenteGlyph: View {
    let values: GlyphValues
    let palette: GlyphPalette
    static let size = CGSize(width: 23, height: 13)
    static let pipCount = 5

    /// Ceil so that any usage at all lights the first pip.
    static func filledPips(_ fraction: Double) -> Int {
        min(pipCount, Int(ceil(fraction * Double(pipCount))))
    }

    var body: some View {
        VStack(spacing: 2.5) {
            HStack(spacing: 2) {
                ForEach(0..<Self.pipCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(index < Self.filledPips(values.sessionFraction) ? palette.session : palette.track)
                        .frame(width: 3, height: 9)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule().fill(palette.weekly)
                        .frame(width: max(values.weeklyFraction > 0 ? 1.5 : 0,
                                          geometry.size.width * values.weeklyFraction))
                }
            }
            .frame(width: Self.size.width, height: 1.5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

// MARK: - Rasterisation

public enum GlyphRenderer {

    /// Rasterises a glyph into an `NSImage` sized in points.
    ///
    /// `MenuBarExtra` renders `Image` and `Text` reliably but not arbitrary
    /// shapes, so every custom glyph goes through `ImageRenderer` first.
    @MainActor
    public static func image<Content: View>(_ content: Content,
                                            size: CGSize,
                                            isTemplate: Bool) -> NSImage? {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = 3
        guard let image = renderer.nsImage else { return nil }
        image.size = size
        image.isTemplate = isTemplate
        return image
    }
}
