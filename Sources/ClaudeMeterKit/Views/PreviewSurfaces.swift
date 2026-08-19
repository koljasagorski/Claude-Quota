import SwiftUI

/// Public, store-free renderings of the real UI.
///
/// The README screenshots and the app icon are produced from these, so the
/// documentation cannot drift away from the shipping views — they *are* the
/// shipping views.
public enum Preview {

    /// Values matching a live Max account, used for every screenshot.
    public static func demoSnapshot(now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            windows: [
                LimitWindow(id: "session", kind: "session", label: "5 Std.",
                            percent: 21, resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60),
                            group: .session, isActive: true),
                LimitWindow(id: "weekly_all", kind: "weekly_all", label: "Woche",
                            percent: 73, resetsAt: now.addingTimeInterval(2 * 86400 + 6 * 3600),
                            group: .weekly, isActive: true),
                LimitWindow(id: "weekly_scoped:Fable", kind: "weekly_scoped", label: "Woche · Fable",
                            percent: 7, resetsAt: now.addingTimeInterval(2 * 86400 + 6 * 3600),
                            group: .weekly, isActive: false)
            ],
            fetchedAt: now.addingTimeInterval(-120)
        )
    }

    public static func values(_ snapshot: UsageSnapshot, now: Date = Date()) -> GlyphValues {
        GlyphValues.from(snapshot, now: now)
    }

    // MARK: - Menu bar

    /// A realistic macOS menu bar with the chosen glyph sitting in it, so the
    /// screenshots show the actual footprint rather than an isolated icon.
    public struct MenuBarStrip: View {
        let style: DesignStyle
        let values: GlyphValues
        let colored: Bool

        public init(style: DesignStyle, values: GlyphValues, colored: Bool) {
            self.style = style
            self.values = values
            self.colored = colored
        }

        private var palette: GlyphPalette {
            colored ? .colored(sessionWarning: false, weeklyWarning: false)
                    : GlyphPalette(session: .white.opacity(0.92),
                                   weekly: .white.opacity(0.92),
                                   track: .white.opacity(0.24),
                                   isTemplate: false)
        }

        public var body: some View {
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                glyph
                Image(systemName: "wifi").font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                Image(systemName: "battery.75").font(.system(size: 13)).foregroundColor(.white.opacity(0.75))
                Text("Mi 19. Aug  14:32")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.92))
            }
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.86))
        }

        @ViewBuilder
        private var glyph: some View {
            switch style {
            case .doppelbalken: DoppelbalkenGlyph(values: values, palette: palette)
            case .doppelring:   DoppelringGlyph(values: values, palette: palette)
            case .countdown:    CountdownGlyph(values: values, palette: palette)
            case .segmente:     SegmenteGlyph(values: values, palette: palette)
            case .zahl:
                HStack(spacing: 4) {
                    DotGlyph(color: palette.session)
                    Text("\(Int((values.sessionFraction * 100).rounded())) %")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundColor(.white.opacity(0.92))
                }
            case .zahlenpaar:
                Text("\(Int((values.sessionFraction * 100).rounded()))·\(Int((values.weeklyFraction * 100).rounded()))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.white.opacity(0.92))
            }
        }
    }

    // MARK: - Panel

    /// The click panel for one style, rendered from a fixed snapshot.
    public struct StaticPanel: View {
        let style: DesignStyle
        let snapshot: UsageSnapshot
        let now: Date
        let showAllWindows: Bool

        public init(style: DesignStyle, snapshot: UsageSnapshot, now: Date, showAllWindows: Bool = true) {
            self.style = style
            self.snapshot = snapshot
            self.now = now
            self.showAllWindows = showAllWindows
        }

        public var body: some View {
            let data = PanelData(snapshot: snapshot, now: now, showAllWindows: showAllWindows)
            VStack(alignment: .leading, spacing: 14) {
                switch style {
                case .doppelbalken: DoppelbalkenPanel(data: data)
                case .zahl:         ZahlPanel(data: data)
                case .doppelring:   DoppelringPanel(data: data)
                case .countdown:    CountdownPanel(data: data)
                case .segmente:     SegmentePanel(data: data)
                case .zahlenpaar:   ZahlenpaarPanel(data: data)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Divider().overlay(Theme.divider)
                    Text(Formatting.freshnessLabel(fetchedAt: snapshot.fetchedAt, now: now))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.footerText)
                    HStack(spacing: 6) {
                        Label("Aktualisieren", systemImage: "arrow.clockwise").font(.system(size: 11))
                        Spacer(minLength: 4)
                        Image(systemName: "gearshape").font(.system(size: 11))
                        Image(systemName: "power").font(.system(size: 11))
                    }
                    .foregroundColor(Theme.primaryText.opacity(0.85))
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 15)
            .padding(.bottom, 12)
            .frame(width: Theme.panelWidth)
            .background(Theme.panelBackground)
            .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - App icon

    /// Double rings on a dark ground — the `doppelring` glyph at icon scale.
    ///
    /// Laid out on Apple's macOS icon grid: the squircle occupies 824 of the
    /// 1024 pt canvas, leaving the transparent margin the Dock expects.
    public struct AppIcon: View {
        let size: CGFloat
        public init(size: CGFloat) { self.size = size }

        public var body: some View {
            let unit = size / 1024
            let plate = 824 * unit

            ZStack {
                RoundedRectangle(cornerRadius: 185 * unit, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.19, green: 0.185, blue: 0.175),
                                     Color(red: 0.085, green: 0.085, blue: 0.095)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: plate, height: plate)
                    .overlay(
                        RoundedRectangle(cornerRadius: 185 * unit, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 3 * unit)
                            .frame(width: plate, height: plate)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 22 * unit, y: 10 * unit)

                ring(diameter: 496 * unit, lineWidth: 68 * unit, fraction: 0.21, color: Theme.session)
                ring(diameter: 300 * unit, lineWidth: 68 * unit, fraction: 0.73, color: Theme.weekly)
            }
            .frame(width: size, height: size)
        }

        private func ring(diameter: CGFloat, lineWidth: CGFloat, fraction: Double, color: Color) -> some View {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
