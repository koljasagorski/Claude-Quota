import SwiftUI
import ClaudeMeterKit

@main
struct ClaudeMeterApp: App {

    @StateObject private var store = UsageStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(store: store, settings: settings, launchAtLogin: launchAtLogin)
        } label: {
            MenuBarLabel(store: store, settings: settings)
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
