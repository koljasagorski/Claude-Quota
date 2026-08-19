import SwiftUI

/// In-panel settings. Deliberately not a separate `Settings` scene: a
/// `LSUIElement` app on macOS 13 cannot reliably bring one to the front, and
/// keeping everything inside the `MenuBarExtra` window avoids that whole class
/// of problem.
struct SettingsView: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject var launchAtLogin: LaunchAtLogin
    let previewValues: GlyphValues
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundColor(Theme.primaryText.opacity(0.85))

                Text("Einstellungen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Darstellung")
                    .font(.system(size: 10))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundColor(Theme.footerText)

                VStack(spacing: 4) {
                    ForEach(DesignStyle.allCases) { style in
                        StyleOptionRow(
                            style: style,
                            isSelected: settings.style == style,
                            values: previewValues,
                            action: { settings.style = style }
                        )
                    }
                }
            }

            Divider().overlay(Theme.divider)

            VStack(alignment: .leading, spacing: 10) {
                SettingsToggle(
                    title: "Farbe in der Menüleiste",
                    detail: "Aus: folgt Hell/Dunkel und getönten Menüleisten.",
                    isOn: $settings.colorInMenuBar
                )
                SettingsToggle(
                    title: "Alle Limit-Fenster zeigen",
                    detail: "Blendet modellbezogene Wochenlimits ein (Max-Pläne).",
                    isOn: $settings.showAllWindows
                )
                SettingsToggle(
                    title: "Beim Anmelden starten",
                    detail: launchAtLogin.lastErrorMessage ?? "Status: \(launchAtLogin.statusDescription)",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.set($0) }
                    ),
                    isEnabled: launchAtLogin.isSupported
                )
            }
        }
        .onAppear { launchAtLogin.refresh() }
    }
}

/// One selectable design, with a live glyph preview on a menu-bar-like strip.
private struct StyleOptionRow: View {
    let style: DesignStyle
    let isSelected: Bool
    let values: GlyphValues
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Theme.session : Theme.secondaryText)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(style.title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(Theme.primaryText)
                        Text(style.code)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.footerText)
                        Spacer(minLength: 4)
                        Text(style.footprint)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.footerText)
                    }
                    Text(style.summary)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    StylePreviewStrip(style: style, values: values)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.07) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Renders the option exactly as it will appear, on a small mock menu bar.
private struct StylePreviewStrip: View {
    let style: DesignStyle
    let values: GlyphValues

    /// Previews are always in colour so the variants are distinguishable in the
    /// list, regardless of the template setting used in the real menu bar.
    private let palette = GlyphPalette.colored(sessionWarning: false, weeklyWarning: false)

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            content
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.black.opacity(0.5))
        )
        .padding(.top, 3)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .doppelbalken:
            DoppelbalkenGlyph(values: values, palette: palette)
        case .zahl:
            HStack(spacing: 4) {
                DotGlyph(color: palette.session)
                Text("\(Int(values.sessionFraction * 100)) %")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.white.opacity(0.92))
            }
        case .doppelring:
            DoppelringGlyph(values: values, palette: palette)
        case .countdown:
            CountdownGlyph(values: values, palette: palette)
        case .segmente:
            SegmenteGlyph(values: values, palette: palette)
        case .zahlenpaar:
            Text("\(Int((values.sessionFraction * 100).rounded()))·\(Int((values.weeklyFraction * 100).rounded()))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.white.opacity(0.92))
        }
    }
}

private struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.primaryText)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!isEnabled)

            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
