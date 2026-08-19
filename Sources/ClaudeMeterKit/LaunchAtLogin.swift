import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` (macOS 13+).
///
/// No hand-written LaunchAgent plist. Registration only works for an app bundle
/// macOS trusts, which in practice means `/Applications` — the UI says so when
/// registration is refused.
@MainActor
public final class LaunchAtLogin: ObservableObject {

    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    public init() {
        refresh()
    }

    public var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    public func refresh() {
        guard isSupported else { isEnabled = false; return }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    public func set(_ enabled: Bool) {
        guard isSupported else {
            lastErrorMessage = "Nur möglich, wenn ClaudeMeter als App läuft."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Autostart fehlgeschlagen: \(error.localizedDescription). App nach /Programme verschieben."
        }
        refresh()
    }

    public var statusDescription: String {
        guard isSupported else { return "Nur im App-Bundle verfügbar" }
        switch SMAppService.mainApp.status {
        case .enabled:        return "aktiv"
        case .notRegistered:  return "nicht registriert"
        case .notFound:       return "App nicht gefunden — nach /Programme verschieben"
        case .requiresApproval: return "Freigabe nötig: Systemeinstellungen › Allgemein › Anmeldeobjekte"
        @unknown default:     return "unbekannt"
        }
    }
}
