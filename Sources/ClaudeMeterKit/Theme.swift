import SwiftUI

/// Colours and metrics lifted from the design study.
///
/// The two accents are the study's `oklch(0.76 0.10 84)` and
/// `oklch(0.76 0.10 118)`, converted to sRGB.
public enum Theme {

    public static let session = Color(red: 0.8123, green: 0.6738, blue: 0.3907) // #CFAC64
    public static let weekly  = Color(red: 0.6713, green: 0.7294, blue: 0.4360) // #ABBA6F
    public static let warning = Color(red: 0.8600, green: 0.4200, blue: 0.3400)

    public static let panelBackground = Color(red: 0.149, green: 0.149, blue: 0.161) // #262629
    public static let panelBorder     = Color.white.opacity(0.07)
    public static let track           = Color.white.opacity(0.14)
    public static let primaryText     = Color.white
    public static let secondaryText   = Color.white.opacity(0.55)
    public static let tertiaryText    = Color.white.opacity(0.42)
    public static let footerText      = Color.white.opacity(0.35)
    public static let divider         = Color.white.opacity(0.08)

    public static let panelWidth: CGFloat = 264

    /// Threshold above which the menu bar shows a warning marker.
    public static let warningThreshold: Double = 80

    /// Accent for a window, honouring the runbook's severity ramp above 80 %.
    public static func accent(for window: LimitWindow) -> Color {
        if window.percent >= warningThreshold { return warning }
        return window.group == .session ? session : weekly
    }

    /// Accent by group, ignoring severity — used for legends and swatches.
    public static func groupAccent(_ group: LimitWindow.Group) -> Color {
        group == .session ? session : weekly
    }
}
