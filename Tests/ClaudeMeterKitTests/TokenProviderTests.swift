import XCTest
@testable import ClaudeMeterKit

final class TokenProviderTests: XCTestCase {

    /// The real bug this guards against: a machine carries a dozen keychain
    /// items whose service name starts with "Claude Code-credentials" but which
    /// hold *MCP server* logins under an `mcpOAuth` key. Accepting one of those
    /// produces permanent 401s against /api/oauth/usage.
    func testMCPCredentialIsRejected() {
        let mcp = """
        { "mcpOAuth": { "serverName": "linear", "accessToken": "sk-ant-oat01-mcp",
                        "expiresAt": 9999999999999 } }
        """
        XCTAssertNil(TokenProvider.decode(Data(mcp.utf8), source: "test"))
    }

    func testSubscriptionCredentialIsAccepted() throws {
        let json = """
        { "claudeAiOauth": { "accessToken": "sk-ant-oat01-real",
                             "refreshToken": "sk-ant-ort01-real",
                             "expiresAt": 1787137714002,
                             "subscriptionType": "max",
                             "rateLimitTier": "default_claude_max_5x" } }
        """
        let credential = try XCTUnwrap(TokenProvider.decode(Data(json.utf8), source: "test"))
        XCTAssertEqual(credential.accessToken, "sk-ant-oat01-real")
        XCTAssertEqual(credential.subscriptionType, "max")
        XCTAssertEqual(credential.rateLimitTier, "default_claude_max_5x")
        XCTAssertEqual(credential.expiresAt?.timeIntervalSince1970 ?? 0, 1787137714.002, accuracy: 0.01)
    }

    func testExpiryIsDetected() throws {
        let expired = """
        { "claudeAiOauth": { "accessToken": "t", "expiresAt": 1000000000000 } }
        """
        let credential = try XCTUnwrap(TokenProvider.decode(Data(expired.utf8), source: "test"))
        XCTAssertTrue(credential.isExpired)
    }

    /// A credential without `expiresAt` is treated as usable — better to let the
    /// server answer 401 than to refuse a token that might be fine.
    func testMissingExpiryIsNotTreatedAsExpired() throws {
        let json = #"{ "claudeAiOauth": { "accessToken": "t" } }"#
        let credential = try XCTUnwrap(TokenProvider.decode(Data(json.utf8), source: "test"))
        XCTAssertFalse(credential.isExpired)
    }

    func testMalformedPayloadsAreRejected() {
        XCTAssertNil(TokenProvider.decode(Data("{}".utf8), source: "test"))
        XCTAssertNil(TokenProvider.decode(Data("not json".utf8), source: "test"))
        XCTAssertNil(TokenProvider.decode(Data(#"{"claudeAiOauth":{}}"#.utf8), source: "test"))
        XCTAssertNil(TokenProvider.decode(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8), source: "test"))
        XCTAssertNil(TokenProvider.decode(Data(#"{"claudeAiOauth":{"accessToken":42}}"#.utf8), source: "test"))
    }

    func testEnvironmentOverrideIsTrimmed() {
        setenv(TokenProvider.environmentKey, "  sk-ant-env-token \n", 1)
        defer { unsetenv(TokenProvider.environmentKey) }
        let credential = TokenProvider().fromEnvironment()
        XCTAssertEqual(credential?.accessToken, "sk-ant-env-token")
    }

    func testBlankEnvironmentIsIgnored() {
        setenv(TokenProvider.environmentKey, "   ", 1)
        defer { unsetenv(TokenProvider.environmentKey) }
        XCTAssertNil(TokenProvider().fromEnvironment())
    }
}

final class FetchErrorTests: XCTestCase {

    /// Terminal errors must not trigger retry storms.
    func testTerminalClassification() {
        XCTAssertTrue(FetchError.noToken.isTerminal)
        XCTAssertTrue(FetchError.tokenExpired.isTerminal)
        XCTAssertTrue(FetchError.noSubscription.isTerminal)
        XCTAssertFalse(FetchError.unauthorized.isTerminal)
        XCTAssertFalse(FetchError.rateLimited(retryAfter: nil).isTerminal)
        XCTAssertFalse(FetchError.transient("x").isTerminal)
    }

    func testEveryErrorHasPlainLanguageText() {
        let all: [FetchError] = [
            .noToken, .tokenExpired, .unauthorized, .rateLimited(retryAfter: nil),
            .rateLimited(retryAfter: 600), .noSubscription, .decoding("x"), .transient("y")
        ]
        for error in all {
            XCTAssertFalse(error.message.isEmpty, "\(error) has no message")
        }
    }
}

final class BackoffTests: XCTestCase {

    /// Runbook ladder: 5 → 10 → 20 → 30 minutes, then hold at 30.
    func testBackoffLadderMatchesRunbook() {
        XCTAssertEqual(UsageStore.backoffLadder, [300, 600, 1200, 1800])
    }

    /// The endpoint is aggressively rate limited; nothing may poll faster.
    func testPollingNeverGoesBelowSixtySeconds() {
        XCTAssertGreaterThanOrEqual(UsageStore.baseInterval, 60)
        XCTAssertGreaterThanOrEqual(UsageStore.manualRefreshFloor, 60)
        XCTAssertEqual(UsageStore.baseInterval, 300)
    }
}

final class KeychainSelectionTests: XCTestCase {

    private func payload(token: String, expiresInHours: Double, subscription: String = "max") -> Data {
        let millis = (Date().timeIntervalSince1970 + expiresInHours * 3600) * 1000
        return Data("""
        { "claudeAiOauth": { "accessToken": "\(token)", "expiresAt": \(millis),
                             "subscriptionType": "\(subscription)" } }
        """.utf8)
    }

    private let mcpPayload = Data("""
    { "mcpOAuth": { "serverName": "linear", "accessToken": "sk-ant-oat01-mcp" } }
    """.utf8)

    /// The failure this whole ranking exists to prevent: a machine carrying a
    /// dozen GUID-suffixed MCP entries must still resolve the real credential.
    func testMCPSiblingsAreSkippedInFavourOfTheRealCredential() throws {
        let candidates: [(service: String, data: Data)] = [
            ("Claude Code-credentials-1239e747", mcpPayload),
            ("Claude Code-credentials-2d6aeace", mcpPayload),
            ("Claude Code-credentials", payload(token: "sk-ant-oat01-real", expiresInHours: 4)),
            ("Claude Code-credentials-b105dff1", mcpPayload)
        ]
        let credential = try XCTUnwrap(
            TokenProvider.best(from: candidates, preferredService: "Claude Code-credentials")
        )
        XCTAssertEqual(credential.accessToken, "sk-ant-oat01-real")
    }

    /// An expired sibling must never beat a live one, whatever its name.
    func testUnexpiredWinsOverExpired() throws {
        let candidates: [(service: String, data: Data)] = [
            ("Claude Code-credentials", payload(token: "stale", expiresInHours: -48)),
            ("Claude Code-credentials-91efcd97", payload(token: "fresh", expiresInHours: 3))
        ]
        let credential = try XCTUnwrap(
            TokenProvider.best(from: candidates, preferredService: "Claude Code-credentials")
        )
        XCTAssertEqual(credential.accessToken, "fresh")
    }

    /// Among equally valid entries the canonical service name wins.
    func testExactServiceNameBreaksTies() throws {
        let candidates: [(service: String, data: Data)] = [
            ("Claude Code-credentials-aaaaaaaa", payload(token: "suffixed", expiresInHours: 5)),
            ("Claude Code-credentials", payload(token: "canonical", expiresInHours: 5))
        ]
        let credential = try XCTUnwrap(
            TokenProvider.best(from: candidates, preferredService: "Claude Code-credentials")
        )
        XCTAssertEqual(credential.accessToken, "canonical")
    }

    /// With only expired entries, the newest is returned so the caller can
    /// report `.tokenExpired` rather than `.noToken`.
    func testLatestExpiryWinsAmongExpiredEntries() throws {
        let candidates: [(service: String, data: Data)] = [
            ("Claude Code-credentials-a", payload(token: "older", expiresInHours: -100)),
            ("Claude Code-credentials-b", payload(token: "newer", expiresInHours: -2))
        ]
        let credential = try XCTUnwrap(
            TokenProvider.best(from: candidates, preferredService: "Claude Code-credentials")
        )
        XCTAssertEqual(credential.accessToken, "newer")
        XCTAssertTrue(credential.isExpired)
    }

    func testNoUsableCandidatesReturnsNil() {
        XCTAssertNil(TokenProvider.best(from: [], preferredService: "Claude Code-credentials"))
        XCTAssertNil(TokenProvider.best(
            from: [("Claude Code-credentials-1", mcpPayload), ("Claude Code-credentials-2", mcpPayload)],
            preferredService: "Claude Code-credentials"
        ))
    }

    func testSourceDescriptionNamesTheEntry() throws {
        let credential = try XCTUnwrap(TokenProvider.best(
            from: [("Claude Code-credentials", payload(token: "t", expiresInHours: 1))],
            preferredService: "Claude Code-credentials"
        ))
        XCTAssertEqual(credential.sourceDescription, "Schlüsselbund (Claude Code-credentials)")
    }
}

final class OwnKeychainEntryTests: XCTestCase {

    /// Runbook §6 source 2 exists for a token from `claude setup-token`, which
    /// is a bare string. Requiring a `claudeAiOauth` wrapper made this source
    /// fail silently while the equivalent env var worked.
    func testBareTokenIsAccepted() throws {
        let credential = try XCTUnwrap(TokenProvider.bareToken(
            Data("sk-ant-oat01-AbCdEfGhIjKlMnOpQrStUvWx\n".utf8), source: "test"
        ))
        XCTAssertEqual(credential.accessToken, "sk-ant-oat01-AbCdEfGhIjKlMnOpQrStUvWx")
        XCTAssertNil(credential.expiresAt)
        XCTAssertFalse(credential.isExpired)
    }

    /// A random blob must not be sent to the API as if it were a credential.
    func testNonTokenBlobsAreRejected() {
        XCTAssertNil(TokenProvider.bareToken(Data("hello".utf8), source: "test"))
        XCTAssertNil(TokenProvider.bareToken(Data("".utf8), source: "test"))
        XCTAssertNil(TokenProvider.bareToken(Data("sk-ant-short".utf8), source: "test"))
        XCTAssertNil(TokenProvider.bareToken(Data("not-a-claude-token-but-quite-long".utf8), source: "test"))
        XCTAssertNil(TokenProvider.bareToken(Data("sk-ant-oat01-has space in it here".utf8), source: "test"))
    }

    /// A JSON payload in the same entry must still take the structured path.
    func testJSONPayloadStillPrefersStructuredDecode() throws {
        let json = Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-structured","subscriptionType":"max"}}"#.utf8)
        let credential = try XCTUnwrap(TokenProvider.decode(json, source: "test"))
        XCTAssertEqual(credential.accessToken, "sk-ant-oat01-structured")
        XCTAssertEqual(credential.subscriptionType, "max")
    }
}
