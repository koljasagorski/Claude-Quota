import Foundation

/// Turns the raw `/api/oauth/usage` body into `[LimitWindow]`.
///
/// The endpoint is undocumented and its shape has already changed once. Three
/// layouts are handled, in this priority order:
///
/// 1. **`limits[]`** — the structured, newer form. Authoritative when present:
///    the server has already filtered it down to the windows that apply to this
///    account, so unreleased feature placeholders never reach the UI.
/// 2. **Flat keys** (`five_hour`, `seven_day`, `seven_day_sonnet`, …) — the
///    older form, still emitted alongside `limits[]` today.
/// 3. Neither → the account has no subscription limits at all.
///
/// Unknown `kind` values are passed through rather than dropped, so a new limit
/// type shows up without an app update.
public enum UsageParser {

    public static func parse(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FetchError.decoding("kein JSON-Objekt")
            }
            root = object
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.decoding(error.localizedDescription)
        }

        if let structured = parseLimitsArray(root), !structured.isEmpty {
            return UsageSnapshot(windows: structured, fetchedAt: now)
        }

        let flat = parseFlatKeys(root)
        if !flat.isEmpty {
            return UsageSnapshot(windows: flat, fetchedAt: now)
        }

        // A 200 with no windows at all means this token belongs to an account
        // without subscription rate limits (console/API key style).
        throw FetchError.noSubscription
    }

    // MARK: - Variant B: limits[]

    static func parseLimitsArray(_ root: [String: Any]) -> [LimitWindow]? {
        guard let raw = root["limits"] as? [[String: Any]] else { return nil }

        return raw.compactMap { entry -> LimitWindow? in
            guard let kind = entry["kind"] as? String else { return nil }
            guard let percent = number(entry["percent"]) else { return nil }

            let scopeName = scopeLabel(entry["scope"])
            let group = groupFor(kind: kind, rawGroup: entry["group"] as? String)
            let identifier = scopeName.map { "\(kind):\($0)" } ?? kind

            return LimitWindow(
                id: identifier,
                kind: kind,
                label: label(kind: kind, scope: scopeName),
                percent: percent,
                resetsAt: DateParsing.parse(entry["resets_at"]),
                group: group,
                isActive: entry["is_active"] as? Bool ?? false
            )
        }
    }

    /// `scope.model.display_name` names the model a scoped weekly limit covers.
    /// `scope.model.id` is frequently `null`, so the display name is the only
    /// reliable source — and it is never assumed to be "Sonnet".
    static func scopeLabel(_ scope: Any?) -> String? {
        guard let scope = scope as? [String: Any] else { return nil }
        if let model = scope["model"] as? [String: Any] {
            if let display = model["display_name"] as? String, !display.isEmpty { return display }
            if let id = model["id"] as? String, !id.isEmpty { return id }
        }
        if let surface = scope["surface"] as? String, !surface.isEmpty { return surface }
        return nil
    }

    // MARK: - Variant A: flat keys

    /// Flat keys known to be real limit windows, in display order.
    static let knownFlatKeys: [(key: String, kind: String, label: String, group: LimitWindow.Group)] = [
        ("five_hour",            "session",            "5 Std.",         .session),
        ("seven_day",            "weekly_all",         "Woche",          .weekly),
        ("seven_day_opus",       "weekly_opus",        "Woche · Opus",   .weekly),
        ("seven_day_sonnet",     "weekly_sonnet",      "Woche · Sonnet", .weekly),
        ("seven_day_cowork",     "weekly_cowork",      "Woche · Cowork", .weekly),
        ("seven_day_oauth_apps", "weekly_oauth_apps",  "Woche · Apps",   .weekly)
    ]

    /// Keys that are never limit windows even though they carry a `utilization`.
    static let flatKeyDenyList: Set<String> = ["extra_usage", "spend"]

    static func parseFlatKeys(_ root: [String: Any]) -> [LimitWindow] {
        var windows: [LimitWindow] = []
        var consumed = flatKeyDenyList

        for entry in knownFlatKeys {
            consumed.insert(entry.key)
            guard let dict = root[entry.key] as? [String: Any],
                  let percent = number(dict["utilization"]) else { continue }
            windows.append(
                LimitWindow(
                    id: entry.kind,
                    kind: entry.kind,
                    label: entry.label,
                    percent: percent,
                    resetsAt: DateParsing.parse(dict["resets_at"]),
                    group: entry.group,
                    isActive: dict["is_active"] as? Bool ?? false
                )
            )
        }

        // Forward compatibility: an unrecognised key is only treated as a real
        // window when it carries a reset time. Anthropic ships codenamed
        // placeholders (`nimbus_quill`, `tangelo`, `iguana_necktie`, …) that
        // have `utilization: 0` and `resets_at: null`; without this guard they
        // would render as bogus 0 % rows.
        for key in root.keys.sorted() where !consumed.contains(key) {
            guard let dict = root[key] as? [String: Any],
                  let percent = number(dict["utilization"]),
                  let resetsAt = DateParsing.parse(dict["resets_at"]) else { continue }
            windows.append(
                LimitWindow(
                    id: key,
                    kind: key,
                    label: humanize(key),
                    percent: percent,
                    resetsAt: resetsAt,
                    group: groupFor(kind: key, rawGroup: nil),
                    isActive: dict["is_active"] as? Bool ?? false
                )
            )
        }

        return windows
    }

    // MARK: - Shared helpers

    static func groupFor(kind: String, rawGroup: String?) -> LimitWindow.Group {
        switch rawGroup {
        case "session": return .session
        case "weekly":  return .weekly
        default: break
        }
        if kind == "session" || kind.hasPrefix("five_hour") { return .session }
        if kind.hasPrefix("weekly") || kind.hasPrefix("seven_day") { return .weekly }
        return .other
    }

    static func label(kind: String, scope: String?) -> String {
        let base: String
        switch kind {
        case "session":       base = "5 Std."
        case "weekly_all":    base = "Woche"
        case "weekly_scoped": base = "Woche"
        default:              base = humanize(kind)
        }
        guard let scope, !scope.isEmpty else { return base }
        return "\(base) · \(scope)"
    }

    /// `weekly_oauth_apps` → `Weekly Oauth Apps`. Only ever reached for limit
    /// types that did not exist when this build shipped.
    static func humanize(_ key: String) -> String {
        key.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Percent values are always 0…100.
    ///
    /// Step 0 against a live Max account confirmed this: `five_hour.utilization`
    /// was `21.0` while `limits[kind=session].percent` was `21` — the same
    /// number in both representations. A value of `0.8` therefore means 0.8 %,
    /// not 80 %, and is never rescaled.
    static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

// MARK: - Dates

public enum DateParsing {

    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// `resets_at` arrives as UTC with six fractional digits, e.g.
    /// `2026-08-19T11:20:00.831601+00:00`. Everything downstream formats it in
    /// the user's local time zone.
    public static func parse(_ value: Any?) -> Date? {
        guard let string = value as? String, !string.isEmpty else { return nil }

        if let date = withFractional.date(from: string) { return date }
        if let date = plain.date(from: string) { return date }

        // Some formatters choke on more than three fractional digits — trim and
        // retry before giving up.
        if let dot = string.firstIndex(of: "."),
           let offset = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = string[string.index(after: dot)..<offset]
            if fraction.count > 3 {
                let trimmed = string.replacingCharacters(
                    in: string.index(after: dot)..<offset,
                    with: fraction.prefix(3)
                )
                if let date = withFractional.date(from: trimmed) { return date }
            }
            let withoutFraction = string.replacingCharacters(in: dot..<offset, with: "")
            if let date = plain.date(from: withoutFraction) { return date }
        }

        return nil
    }
}
