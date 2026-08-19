import SwiftUI

/// The thing that actually sits in the menu bar.
///
/// Width stability is a hard requirement — anything to the left of us must
/// never shift. Two mechanisms guarantee it: rasterised glyphs have fixed point
/// sizes, and every number is padded with FIGURE SPACE and drawn with
/// `.monospacedDigit()`.
public struct MenuBarLabel: View {

    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    public init(store: UsageStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    private var snapshot: UsageSnapshot? { store.state.snapshot }
    private var values: GlyphValues { GlyphValues.from(snapshot, now: store.clock) }

    private var palette: GlyphPalette {
        guard settings.colorInMenuBar else { return .template }
        return .colored(
            sessionWarning: (snapshot?.session?.percent ?? 0) >= Theme.warningThreshold,
            weeklyWarning: (snapshot?.weekly?.percent ?? 0) >= Theme.warningThreshold
        )
    }

    /// No icon in normal operation — the runbook is explicit that the menu bar
    /// stays quiet until something is actually wrong.
    private var statusSymbol: String? {
        if store.state.error != nil { return "exclamationmark.circle" }
        if case .loading = store.state { return nil }
        let peak = snapshot?.peakPercent ?? 0
        return peak >= Theme.warningThreshold ? "exclamationmark.triangle.fill" : nil
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let statusSymbol {
                Image(systemName: statusSymbol)
            }
            styleContent
        }
    }

    @ViewBuilder
    private var styleContent: some View {
        switch settings.style {
        case .doppelbalken:
            glyph(DoppelbalkenGlyph(values: values, palette: palette), size: DoppelbalkenGlyph.size)

        case .zahl:
            HStack(spacing: 4) {
                glyph(DotGlyph(color: palette.session), size: DotGlyph.size)
                percentText(snapshot?.session?.roundedPercent)
            }

        case .doppelring:
            glyph(DoppelringGlyph(values: values, palette: palette), size: DoppelringGlyph.size)

        case .countdown:
            glyph(CountdownGlyph(values: values, palette: palette), size: CountdownGlyph.size)

        case .segmente:
            glyph(SegmenteGlyph(values: values, palette: palette), size: SegmenteGlyph.size)

        case .zahlenpaar:
            Text(zahlenpaarText)
                .font(.system(size: 12).monospacedDigit())
        }
    }

    @ViewBuilder
    private func glyph<Content: View>(_ content: Content, size: CGSize) -> some View {
        if let image = GlyphRenderer.image(content, size: size, isTemplate: palette.isTemplate) {
            Image(nsImage: image)
        } else {
            // ImageRenderer should never fail, but the menu bar must show
            // *something* rather than an empty hit area.
            Text("··").font(.system(size: 12).monospacedDigit())
        }
    }

    /// The placeholder uses FIGURE DASH, which is exactly one digit wide, so
    /// the label does not shift when the first values arrive.
    private func percentText(_ value: Int?) -> some View {
        let digits = value.map { Formatting.fixedWidthPercent($0) } ?? Formatting.placeholderPercent()
        return Text("\(digits) %")
            .font(.system(size: 12).monospacedDigit())
    }

    /// Runbook format: `21·73`, always seven digit-cells wide.
    ///
    /// Three cells per value, not two: `fixedWidthPercent` cannot truncate, so
    /// a two-cell budget silently grows to three at 100 % and shifts every
    /// status item to the left of us — exactly what this type must never do.
    private var zahlenpaarText: String {
        guard let snapshot else {
            return "\(Formatting.placeholderPercent())·\(Formatting.placeholderPercent())"
        }
        let session = Formatting.fixedWidthPercent(snapshot.session?.roundedPercent ?? 0)
        let weekly = Formatting.fixedWidthPercent(snapshot.weekly?.roundedPercent ?? 0)
        return "\(session)·\(weekly)"
    }
}
