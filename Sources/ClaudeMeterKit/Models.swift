import Foundation

// MARK: - Limit window

/// One rate-limit window — exactly one row in the panel.
///
/// The app never hard-codes which windows exist. Whatever the API reports is
/// carried through, so a new limit type does not require an app update.
public struct LimitWindow: Identifiable, Equatable, Hashable {

    /// Coarse bucket used for layout and for picking the two menu-bar values.
    public enum Group: String, Equatable, Hashable {
        case session
        case weekly
        case other
    }

    /// Stable identity, e.g. `session`, `weekly_all`, `weekly_scoped:Fable`.
    public let id: String
    /// Raw `kind` from the API (or the flat key it was derived from).
    public let kind: String
    /// Localised row label, e.g. `5 Std.`, `Woche`, `Woche · Fable`.
    public let label: String
    /// Always 0…100. See `DATA-SOURCE.md` for why this is never a 0…1 fraction.
    public let percent: Double
    public let resetsAt: Date?
    public let group: Group
    /// API hint that this window is the one currently being consumed.
    public let isActive: Bool

    public init(id: String,
                kind: String,
                label: String,
                percent: Double,
                resetsAt: Date?,
                group: Group,
                isActive: Bool = false) {
        self.id = id
        self.kind = kind
        self.label = label
        self.percent = LimitWindow.clamp(percent)
        self.resetsAt = resetsAt
        self.group = group
        self.isActive = isActive
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    /// Rounded integer percent used everywhere in the UI.
    public var roundedPercent: Int { Int(percent.rounded()) }
}

// MARK: - Snapshot

public struct UsageSnapshot: Equatable {
    public let windows: [LimitWindow]
    public let fetchedAt: Date

    public init(windows: [LimitWindow], fetchedAt: Date) {
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    /// The rolling 5-hour window (the runbook's terminology correction:
    /// it is 5 hours, not 4).
    public var session: LimitWindow? {
        windows.first { $0.group == .session }
    }

    /// The account-wide weekly window — preferred over model-scoped ones.
    public var weekly: LimitWindow? {
        windows.first { $0.group == .weekly && $0.kind == "weekly_all" }
            ?? windows.first { $0.group == .weekly }
    }

    /// Highest utilisation across all windows — drives the warning state.
    public var peakPercent: Double {
        windows.map(\.percent).max() ?? 0
    }

    public var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
}

// MARK: - Errors

public enum FetchError: Error, Equatable {
    /// No credential found in any of the four sources.
    case noToken
    /// Found a credential, but `expiresAt` is in the past. We deliberately do
    /// not refresh — rotating the refresh token would break Claude Code itself.
    case tokenExpired
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    /// Endpoint answered, but the account has no subscription rate limits
    /// (pure API/console accounts).
    case noSubscription
    case decoding(String)
    case transient(String)

    /// Plain-language text shown in the panel footer.
    public var message: String {
        switch self {
        case .noToken:
            return "Keine Anmeldung gefunden — Claude Code einmal starten."
        case .tokenExpired:
            return "Token abgelaufen — Claude Code einmal starten."
        case .unauthorized:
            return "Nicht autorisiert (401) — Claude Code einmal starten."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Zu viele Anfragen (429) — neuer Versuch in \(Int(retryAfter / 60)) Min."
            }
            return "Zu viele Anfragen (429) — Abfrage wird verlangsamt."
        case .noSubscription:
            return "Dieses Konto hat keine Abo-Limits (API-Konto)."
        case .decoding(let detail):
            return "Antwort nicht lesbar: \(detail)"
        case .transient(let detail):
            return "Netzwerkfehler: \(detail)"
        }
    }

    /// `true` when retrying sooner cannot help.
    public var isTerminal: Bool {
        switch self {
        case .noToken, .tokenExpired, .noSubscription: return true
        default: return false
        }
    }
}

// MARK: - Store state

public enum UsageState: Equatable {
    case loading
    case ready(UsageSnapshot)
    /// Last good data plus the error that stopped us from refreshing it.
    case stale(UsageSnapshot, FetchError)
    case failed(FetchError)

    public var snapshot: UsageSnapshot? {
        switch self {
        case .ready(let s): return s
        case .stale(let s, _): return s
        case .loading, .failed: return nil
        }
    }

    public var error: FetchError? {
        switch self {
        case .stale(_, let e): return e
        case .failed(let e): return e
        case .loading, .ready: return nil
        }
    }
}
