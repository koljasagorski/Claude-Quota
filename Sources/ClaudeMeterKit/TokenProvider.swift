import Foundation
import Security

/// Read-only resolution of the Claude Code OAuth access token.
///
/// **This type never writes.** It does not refresh, rotate or store anything.
/// Triggering a refresh would rotate Claude Code's refresh token and break the
/// user's actual CLI login, so an expired credential is reported as
/// `.tokenExpired` and nothing else happens.
public struct TokenProvider {

    public struct Credential: Equatable {
        public let accessToken: String
        public let expiresAt: Date?
        public let subscriptionType: String?
        public let rateLimitTier: String?
        public let sourceDescription: String

        public var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt <= Date()
        }
    }

    /// Service name Claude Code uses for the subscription credential.
    static let keychainService = "Claude Code-credentials"
    /// Optional service name for a token the user supplied themselves via
    /// `claude setup-token` (see README).
    static let ownKeychainService = "de.sagorski.claudemeter.token"
    static let environmentKey = "CLAUDEMETER_TOKEN"

    public init() {}

    /// First successful source wins. Deliberately re-read on **every** poll:
    /// Claude Code rotates the access token roughly hourly, and a cached copy
    /// turns into permanent 401s after that.
    public func resolve() throws -> Credential {
        if let credential = fromEnvironment() { return try validated(credential) }
        if let credential = fromOwnKeychain() { return try validated(credential) }
        if let credential = fromKeychain(service: Self.keychainService, exactMatch: false) {
            return try validated(credential)
        }
        if let credential = fromFile() { return try validated(credential) }
        throw FetchError.noToken
    }

    private func validated(_ credential: Credential) throws -> Credential {
        if credential.isExpired { throw FetchError.tokenExpired }
        return credential
    }

    // MARK: - Sources

    func fromEnvironment() -> Credential? {
        guard let raw = ProcessInfo.processInfo.environment[Self.environmentKey],
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Credential(
            accessToken: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil,
            sourceDescription: "Umgebungsvariable"
        )
    }

    /// The user's own entry, for a token obtained with `claude setup-token`.
    ///
    /// Unlike Claude Code's entry this may hold a **bare token string** — that
    /// is what `security add-generic-password -s de.sagorski.claudemeter.token
    /// -w sk-ant-oat01-…` stores, and what the environment-variable source
    /// already accepts. Requiring a `claudeAiOauth` wrapper here would make the
    /// two documented "bring your own token" paths behave differently and fail
    /// silently.
    func fromOwnKeychain() -> Credential? {
        guard let data = readItem(service: Self.ownKeychainService) else { return nil }
        let source = "Schlüsselbund (\(Self.ownKeychainService))"

        if let credential = Self.decode(data, source: source) { return credential }
        return Self.bareToken(data, source: source)
    }

    /// Accepts a raw token string. Deliberately strict about shape so a random
    /// blob is not sent to the API as if it were a credential.
    static func bareToken(_ data: Data, source: String) -> Credential? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 20,
              !token.contains(where: { $0.isWhitespace }),
              token.hasPrefix("sk-ant-") else { return nil }

        // No expiry is knowable for a bare token; let the server answer instead
        // of refusing a credential that may well be fine.
        return Credential(accessToken: token,
                          expiresAt: nil,
                          subscriptionType: nil,
                          rateLimitTier: nil,
                          sourceDescription: source)
    }

    /// Reads generic-password items and picks the best usable credential.
    ///
    /// Two passes, because a single one cannot work: on macOS, combining
    /// `kSecReturnData` with `kSecMatchLimitAll` fails with `errSecParam`
    /// (-50). So pass 1 enumerates service names with attributes only, and
    /// pass 2 reads each candidate's payload individually.
    ///
    /// Candidate filtering matters just as much. The naive "first service
    /// starting with `Claude Code-credentials`" rule is wrong in practice: a
    /// real machine carries a dozen sibling entries with GUID suffixes
    /// (`Claude Code-credentials-1239e747`, …) holding **MCP server** OAuth
    /// tokens under an `mcpOAuth` key, plus older expired subscription
    /// credentials. Picking one of those yields permanent 401s.
    func fromKeychain(service: String, exactMatch: Bool) -> Credential? {
        let services = exactMatch ? [service] : matchingServiceNames(prefix: service)
        guard !services.isEmpty else { return nil }

        let candidates = services.compactMap { name -> (service: String, data: Data)? in
            guard let data = readItem(service: name) else { return nil }
            return (name, data)
        }

        return Self.best(from: candidates, preferredService: service)
    }

    /// Pass 1 — attributes only. Claude Code writes to the file-based keychain,
    /// so the data-protection keychain is explicitly excluded.
    private func matchingServiceNames(prefix: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: false
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }

        var seen = Set<String>()
        return items.compactMap { $0[kSecAttrService as String] as? String }
            .filter { $0.hasPrefix(prefix) }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    /// Pass 2 — one item, with its data.
    private func readItem(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: false
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Ranking, split out so it can be tested without touching the keychain:
    /// unexpired beats expired, the exact service name beats a GUID-suffixed
    /// sibling, and a later expiry beats an earlier one.
    static func best(from candidates: [(service: String, data: Data)],
                     preferredService: String,
                     now: Date = Date()) -> Credential? {
        let decoded = candidates.compactMap { candidate -> (Credential, Bool)? in
            guard let credential = decode(candidate.data,
                                          source: "Schlüsselbund (\(candidate.service))") else { return nil }
            return (credential, candidate.service == preferredService)
        }

        return decoded.sorted { lhs, rhs in
            let lhsValid = (lhs.0.expiresAt ?? .distantFuture) > now
            let rhsValid = (rhs.0.expiresAt ?? .distantFuture) > now
            if lhsValid != rhsValid { return lhsValid }
            if lhs.1 != rhs.1 { return lhs.1 }
            return (lhs.0.expiresAt ?? .distantPast) > (rhs.0.expiresAt ?? .distantPast)
        }.first?.0
    }

    func fromFile() -> Credential? {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let url = base.appendingPathComponent(".credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.decode(data, source: "~/.claude/.credentials.json")
    }

    // MARK: - Decoding

    /// Accepts only payloads carrying `claudeAiOauth`. Anything shaped like
    /// `{ "mcpOAuth": … }` is an MCP server login and is rejected outright.
    static func decode(_ data: Data, source: String) -> Credential? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }

        var expiresAt: Date?
        if let millis = oauth["expiresAt"] as? Double, millis > 0 {
            expiresAt = Date(timeIntervalSince1970: millis / 1000)
        } else if let millis = oauth["expiresAt"] as? NSNumber, millis.doubleValue > 0 {
            expiresAt = Date(timeIntervalSince1970: millis.doubleValue / 1000)
        }

        return Credential(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String,
            sourceDescription: source
        )
    }
}
