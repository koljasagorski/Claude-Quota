import Foundation
import SwiftUI

/// The six interchangeable presentations.
///
/// Cases 1a–1e come straight from the design study; `zahlenpaar` is the compact
/// text label specified in the runbook. Each case drives **both** the menu-bar
/// glyph and the layout of the click panel, because the design study defines
/// them as a pair.
public enum DesignStyle: String, CaseIterable, Identifiable, Codable {
    case doppelbalken   // 1a — two stacked hairline bars
    case zahl           // 1b — dot plus percentage
    case doppelring     // 1c — concentric rings
    case countdown      // 1d — time until reset, fill behind the number
    case segmente       // 1e — five pips plus a weekly hairline
    case zahlenpaar     // runbook — "21·73"

    public var id: String { rawValue }

    public var code: String {
        switch self {
        case .doppelbalken: return "1a"
        case .zahl:         return "1b"
        case .doppelring:   return "1c"
        case .countdown:    return "1d"
        case .segmente:     return "1e"
        case .zahlenpaar:   return "RB"
        }
    }

    public var title: String {
        switch self {
        case .doppelbalken: return "Doppelbalken"
        case .zahl:         return "Nur die Zahl"
        case .doppelring:   return "Doppelring"
        case .countdown:    return "Reset-Countdown"
        case .segmente:     return "Segmente"
        case .zahlenpaar:   return "Zahlenpaar"
        }
    }

    public var summary: String {
        switch self {
        case .doppelbalken:
            return "Zwei feine Balken übereinander — oben 5 Std., unten Woche. Keine Zahl."
        case .zahl:
            return "Punkt plus Prozentwert des laufenden 5-Std-Fensters. Woche nur im Panel."
        case .doppelring:
            return "Die kleinste Variante: außen 5 Std., innen Woche. Größe eines normalen Icons."
        case .countdown:
            return "Zeigt Zeit statt Prozent — der Füllstand liegt hinter der Zahl."
        case .segmente:
            return "Fünf Segmente für das 5-Std-Fenster, darunter eine Linie für die Woche."
        case .zahlenpaar:
            return "Beide Prozentwerte als Text, durch einen Mittelpunkt getrennt."
        }
    }

    /// Rough menu-bar footprint, shown next to each option in the settings list.
    public var footprint: String {
        switch self {
        case .doppelbalken: return "≈ 22 × 9 pt"
        case .zahl:         return "≈ 44 × 13 pt"
        case .doppelring:   return "≈ 15 × 15 pt"
        case .countdown:    return "≈ 38 × 15 pt"
        case .segmente:     return "≈ 23 × 13 pt"
        case .zahlenpaar:   return "≈ 46 × 13 pt"
        }
    }
}

/// User preferences, persisted in `UserDefaults`. Never holds a token.
@MainActor
public final class AppSettings: ObservableObject {

    private enum Key {
        static let style = "designStyle"
        static let colorInMenuBar = "colorInMenuBar"
        static let showAllWindows = "showAllWindows"
    }

    private let defaults: UserDefaults

    @Published public var style: DesignStyle {
        didSet { defaults.set(style.rawValue, forKey: Key.style) }
    }

    /// Menu-bar images are rendered as templates by default so they follow
    /// light/dark mode and tinted menu bars. Colour is opt-in.
    @Published public var colorInMenuBar: Bool {
        didSet { defaults.set(colorInMenuBar, forKey: Key.colorInMenuBar) }
    }

    /// Show model-scoped weekly limits (Max plans) in addition to the main two.
    @Published public var showAllWindows: Bool {
        didSet { defaults.set(showAllWindows, forKey: Key.showAllWindows) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Key.style) ?? DesignStyle.doppelring.rawValue
        self.style = DesignStyle(rawValue: raw) ?? .doppelring
        self.colorInMenuBar = defaults.object(forKey: Key.colorInMenuBar) as? Bool ?? false
        self.showAllWindows = defaults.object(forKey: Key.showAllWindows) as? Bool ?? true
    }
}
