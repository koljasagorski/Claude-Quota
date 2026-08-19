import SwiftUI

/// The click-through panel. Chooses its layout from the selected design, so a
/// style switch changes the menu bar and the panel together — that pairing is
/// how the design study defines each variant.
public struct UsagePanel: View {

    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @State private var showingSettings = false

    public init(store: UsageStore, settings: AppSettings, launchAtLogin: LaunchAtLogin) {
        self.store = store
        self.settings = settings
        self.launchAtLogin = launchAtLogin
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showingSettings {
                SettingsView(
                    settings: settings,
                    launchAtLogin: launchAtLogin,
                    previewValues: GlyphValues.from(store.state.snapshot, now: store.clock),
                    onBack: { showingSettings = false }
                )
            } else {
                content
                PanelFooter(
                    state: store.state,
                    now: store.clock,
                    onRefresh: { store.refreshNow() },
                    onSettings: { showingSettings = true },
                    onQuit: { NSApplication.shared.terminate(nil) }
                )
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 15)
        .padding(.bottom, 12)
        .frame(width: Theme.panelWidth)
        .background(Theme.panelBackground)
        .environment(\.colorScheme, .dark)
        .onAppear { store.refreshIfStale() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.state.snapshot {
            let data = PanelData(snapshot: snapshot,
                                 now: store.clock,
                                 showAllWindows: settings.showAllWindows)
            switch settings.style {
            case .doppelbalken: DoppelbalkenPanel(data: data)
            case .zahl:         ZahlPanel(data: data)
            case .doppelring:   DoppelringPanel(data: data)
            case .countdown:    CountdownPanel(data: data)
            case .segmente:     SegmentePanel(data: data)
            case .zahlenpaar:   ZahlenpaarPanel(data: data)
            }
        } else {
            PanelEmptyState(state: store.state)
        }
    }
}
