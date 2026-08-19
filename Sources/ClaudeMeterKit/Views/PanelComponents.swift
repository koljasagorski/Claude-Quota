import SwiftUI

/// Horizontal capsule meter used by several panel layouts.
struct MeterBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 5
    var trackColor: Color = Theme.track

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(color)
                    .frame(width: max(fraction > 0 ? height : 0,
                                      geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// Concentric progress rings — the panel-sized version of glyph 1c.
struct RingPair: View {
    let sessionFraction: Double
    let weeklyFraction: Double
    let sessionColor: Color
    let weeklyColor: Color
    var diameter: CGFloat = 78

    var body: some View {
        ZStack {
            ring(inset: 5, fraction: sessionFraction, color: sessionColor)
            ring(inset: 15, fraction: weeklyFraction, color: weeklyColor)
        }
        .frame(width: diameter, height: diameter)
    }

    private func ring(inset: CGFloat, fraction: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 6)
                .padding(inset)
            Circle()
                .trim(from: 0, to: max(fraction > 0 ? 0.01 : 0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .padding(inset)
                .rotationEffect(.degrees(-90))
        }
    }
}

/// `Reset 16:45 · in 2 Std 13 Min` — or a clear note when no reset is known.
struct ResetCaption: View {
    let window: LimitWindow
    let now: Date
    var font: Font = .system(size: 10.5)

    var body: some View {
        Group {
            if let resetsAt = window.resetsAt {
                Text("Reset \(Formatting.resetLabel(resetsAt, now: now)) · \(Formatting.remainingLabel(resetsAt, now: now))")
            } else {
                Text("Kein Reset-Zeitpunkt gemeldet")
            }
        }
        .font(font)
        .foregroundColor(Theme.tertiaryText)
    }
}

/// Compact row used for any window beyond the two headline ones (model-scoped
/// weekly limits on Max plans). Keeps each design's identity intact while still
/// supporting three or four windows.
struct ExtraWindowRow: View {
    let window: LimitWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.label)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                Spacer(minLength: 8)
                Text("\(window.roundedPercent) %")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Theme.primaryText)
            }
            MeterBar(fraction: window.percent / 100,
                     color: Theme.accent(for: window),
                     height: 4)
            if let resetsAt = window.resetsAt {
                Text(Formatting.remainingLabel(resetsAt, now: now))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
    }
}

/// Footer: freshness, any error, and the three actions.
struct PanelFooter: View {
    let state: UsageState
    let now: Date
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    private var freshness: String {
        guard let snapshot = state.snapshot else {
            if case .loading = state { return "wird geladen …" }
            return "keine Daten"
        }
        return Formatting.freshnessLabel(fetchedAt: snapshot.fetchedAt, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider().overlay(Theme.divider)

            if let error = state.error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.warning)
                    Text(error.message)
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 0) {
                Text(freshness)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.footerText)
                Spacer(minLength: 6)
            }

            HStack(spacing: 6) {
                Button(action: onRefresh) {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundColor(Theme.primaryText.opacity(0.85))

                Spacer(minLength: 4)

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundColor(Theme.primaryText.opacity(0.85))
                .help("Einstellungen")

                Button(action: onQuit) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundColor(Theme.primaryText.opacity(0.85))
                .keyboardShortcut("q")
                .help("Beenden (⌘Q)")
            }
        }
    }
}

/// Shown when there is no snapshot at all.
struct PanelEmptyState: View {
    let state: UsageState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .loading = state {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Verbrauch wird abgefragt …")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
            } else if let error = state.error {
                Text("Keine Daten")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                Text(error.message)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
