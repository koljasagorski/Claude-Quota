import Foundation

/// All user-facing date and duration strings.
///
/// `resets_at` arrives in UTC; every formatter here works in the user's own
/// time zone and calendar, which is the whole point of the type.
public enum Formatting {

    public static var calendar: Calendar = {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }()

    public static var locale = Locale(identifier: "de_DE")

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// `16:45` — today. `Do 20:00` — within the coming week.
    /// `24. Aug, 09:00` — further out.
    public static func resetLabel(_ date: Date, now: Date = Date()) -> String {
        let time = formatter("Hmm").string(from: date)

        if calendar.isDate(date, inSameDayAs: now) { return time }

        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days == 1 { return "morgen \(time)" }
        if days > 1 && days < 7 {
            let weekday = formatter("EEE").string(from: date)
            return "\(weekday) \(time)"
        }
        return "\(formatter("ddMMM").string(from: date)), \(time)"
    }

    /// `in 2 Std 13 Min`, `in 3 T 6 Std`, `jetzt`.
    public static func remainingLabel(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "jetzt" }

        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "in \(days) T \(hours) Std" : "in \(days) T"
        }
        if hours > 0 {
            return minutes > 0 ? "in \(hours) Std \(minutes) Min" : "in \(hours) Std"
        }
        return "in \(max(1, minutes)) Min"
    }

    /// `2:13` — compact countdown for the menu bar. Never wider than 5 glyphs.
    public static func compactCountdown(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "–:––" }
        let seconds = max(0, date.timeIntervalSince(now))
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / 1440

        if days >= 1 {
            return "\(days)\u{2009}T"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }

    /// `Aktualisiert vor 2 Min · alle 5 Min`
    public static func freshnessLabel(fetchedAt: Date, now: Date = Date(), intervalMinutes: Int = 5) -> String {
        "\(agoLabel(fetchedAt, now: now)) · alle \(intervalMinutes) Min"
    }

    public static func agoLabel(_ date: Date, now: Date = Date()) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        switch minutes {
        case 0:      return "gerade aktualisiert"
        case 1:      return "aktualisiert vor 1 Min"
        case 2..<60: return "aktualisiert vor \(minutes) Min"
        default:
            let hours = minutes / 60
            return hours == 1 ? "aktualisiert vor 1 Std" : "aktualisiert vor \(hours) Std"
        }
    }

    /// Percentages are padded with FIGURE SPACE (U+2007), which is exactly one
    /// digit wide. Combined with `.monospacedDigit()` this makes the menu-bar
    /// label a fixed width regardless of the value — nothing to its left ever
    /// shifts position.
    public static func fixedWidthPercent(_ value: Int, digits: Int = 3) -> String {
        let text = String(value)
        guard text.count < digits else { return text }
        return String(repeating: "\u{2007}", count: digits - text.count) + text
    }
}
