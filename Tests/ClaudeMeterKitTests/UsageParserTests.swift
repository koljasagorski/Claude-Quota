import XCTest
@testable import ClaudeMeterKit

final class UsageParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "fixture \(name).json missing"
        )
        return try Data(contentsOf: url)
    }

    // MARK: - The response a real Max account returns today

    /// Both layouts arrive in the same body. `limits[]` must win, because the
    /// server has already filtered it to the windows this account actually has.
    func testHybridResponsePrefersLimitsArray() throws {
        let snapshot = try UsageParser.parse(fixture("usage_hybrid"))

        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertEqual(snapshot.windows.map(\.kind),
                       ["session", "weekly_all", "weekly_scoped"])
        XCTAssertEqual(snapshot.session?.roundedPercent, 21)
        XCTAssertEqual(snapshot.weekly?.roundedPercent, 73)
    }

    /// The codenamed placeholders Anthropic ships (`nimbus_quill`, `tangelo`,
    /// `iguana_necktie`, …) must never reach the UI as bogus 0 % rows.
    func testHybridResponseDropsCodenamePlaceholders() throws {
        let snapshot = try UsageParser.parse(fixture("usage_hybrid"))
        XCTAssertFalse(snapshot.windows.contains { $0.kind.contains("nimbus") })
        XCTAssertFalse(snapshot.windows.contains { $0.kind.contains("tangelo") })
    }

    /// `scope.model.id` is null in the wild; the label has to come from
    /// `display_name`, and must not be hard-coded to "Sonnet".
    func testScopedWeeklyLimitUsesModelDisplayName() throws {
        let snapshot = try UsageParser.parse(fixture("usage_hybrid"))
        let scoped = try XCTUnwrap(snapshot.windows.first { $0.kind == "weekly_scoped" })
        XCTAssertEqual(scoped.label, "Woche · Fable")
        XCTAssertEqual(scoped.id, "weekly_scoped:Fable")
        XCTAssertEqual(scoped.group, .weekly)
    }

    // MARK: - Variant A: flat keys only

    func testFlatOnlyResponse() throws {
        let snapshot = try UsageParser.parse(fixture("usage_flat_only"))

        XCTAssertEqual(snapshot.session?.roundedPercent, 35)
        XCTAssertEqual(snapshot.session?.label, "5 Std.")
        XCTAssertEqual(snapshot.weekly?.roundedPercent, 14)
        XCTAssertEqual(snapshot.weekly?.label, "Woche")

        let sonnet = try XCTUnwrap(snapshot.windows.first { $0.kind == "weekly_sonnet" })
        XCTAssertEqual(sonnet.roundedPercent, 39)
    }

    /// `seven_day_opus: null` must drop the row entirely, not render 0 %.
    func testNullWindowsAreOmittedNotZeroed() throws {
        let snapshot = try UsageParser.parse(fixture("usage_flat_only"))
        XCTAssertFalse(snapshot.windows.contains { $0.kind == "weekly_opus" })
    }

    /// A placeholder with `resets_at: null` is not a window.
    func testFlatFallbackSkipsResetlessUnknownKeys() throws {
        let snapshot = try UsageParser.parse(fixture("usage_flat_only"))
        XCTAssertFalse(snapshot.windows.contains { $0.kind == "nimbus_quill" })
    }

    /// `extra_usage` carries a `utilization` but is spend, not a rate limit.
    func testExtraUsageIsNeverAWindow() throws {
        let snapshot = try UsageParser.parse(fixture("usage_flat_only"))
        XCTAssertFalse(snapshot.windows.contains { $0.kind == "extra_usage" })
    }

    // MARK: - Variant B: limits[] only

    func testLimitsOnlyResponse() throws {
        let snapshot = try UsageParser.parse(fixture("usage_limits_only"))

        XCTAssertEqual(snapshot.session?.roundedPercent, 8)
        XCTAssertEqual(snapshot.weekly?.roundedPercent, 66)
        XCTAssertEqual(snapshot.weekly?.kind, "weekly_all")

        let opus = try XCTUnwrap(snapshot.windows.first { $0.kind == "weekly_scoped" })
        XCTAssertEqual(opus.label, "Woche · Opus")
    }

    /// A limit type that did not exist when this build shipped is carried
    /// through rather than dropped.
    func testUnknownKindSurvives() throws {
        let snapshot = try UsageParser.parse(fixture("usage_limits_only"))
        let unknown = try XCTUnwrap(snapshot.windows.first { $0.kind == "monthly_quantum_flux" })
        XCTAssertEqual(unknown.label, "Monthly Quantum Flux")
        XCTAssertEqual(unknown.group, .other)
        XCTAssertEqual(unknown.roundedPercent, 3)
    }

    // MARK: - Scale

    /// Step 0 proved `utilization` is 0–100. `0.8` therefore means 0.8 %, and
    /// rescaling it to 80 % would be a silent, dangerous lie.
    func testSmallValuesAreNotRescaledToPercent() throws {
        let snapshot = try UsageParser.parse(fixture("usage_fractional_trap"))
        XCTAssertEqual(snapshot.session?.percent ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(snapshot.session?.roundedPercent, 1)
        XCTAssertEqual(snapshot.weekly?.roundedPercent, 100)
    }

    func testPercentIsClamped() {
        XCTAssertEqual(LimitWindow(id: "a", kind: "a", label: "a", percent: 143, resetsAt: nil, group: .other).percent, 100)
        XCTAssertEqual(LimitWindow(id: "a", kind: "a", label: "a", percent: -7, resetsAt: nil, group: .other).percent, 0)
        XCTAssertEqual(LimitWindow(id: "a", kind: "a", label: "a", percent: .nan, resetsAt: nil, group: .other).percent, 0)
    }

    // MARK: - Failure modes

    /// A pure API/console account gets a clean message, never a crash.
    func testAccountWithoutSubscriptionLimits() throws {
        XCTAssertThrowsError(try UsageParser.parse(fixture("usage_no_subscription"))) { error in
            XCTAssertEqual(error as? FetchError, .noSubscription)
        }
    }

    func testGarbageBodyDoesNotCrash() {
        XCTAssertThrowsError(try UsageParser.parse(Data("not json at all".utf8)))
        XCTAssertThrowsError(try UsageParser.parse(Data("[1,2,3]".utf8)))
        XCTAssertThrowsError(try UsageParser.parse(Data()))
    }

    /// Unexpected types must be skipped, not trapped on.
    func testHostileTypesAreSurvived() throws {
        let json = """
        { "limits": [
            { "kind": "session", "percent": "44", "resets_at": "2026-08-19T22:00:00+00:00" },
            { "kind": 99, "percent": 5 },
            { "percent": 5 },
            { "kind": "weekly_all", "percent": null },
            { "kind": "weekly_all", "percent": 12, "resets_at": 12345, "scope": "nonsense" }
        ] }
        """
        let snapshot = try UsageParser.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.session?.roundedPercent, 44)
        XCTAssertEqual(snapshot.weekly?.roundedPercent, 12)
        XCTAssertNil(snapshot.weekly?.resetsAt)
    }

    // MARK: - Dates

    /// `resets_at` is UTC with six fractional digits. Getting this wrong shows
    /// the reset two hours off during German summer time.
    func testResetTimestampParsesAsUTC() throws {
        let date = try XCTUnwrap(DateParsing.parse("2026-08-19T11:20:00.831601+00:00"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(parts.hour, 11)
        XCTAssertEqual(parts.minute, 20)
        XCTAssertEqual(parts.day, 19)
    }

    func testResetTimestampVariants() {
        XCTAssertNotNil(DateParsing.parse("2026-08-19T22:00:00+00:00"))
        XCTAssertNotNil(DateParsing.parse("2026-08-19T22:00:00Z"))
        XCTAssertNotNil(DateParsing.parse("2026-08-19T22:00:00.831Z"))
        XCTAssertNotNil(DateParsing.parse("2026-08-19T22:00:00.831601831Z"))
        XCTAssertNil(DateParsing.parse(nil))
        XCTAssertNil(DateParsing.parse(""))
        XCTAssertNil(DateParsing.parse("gestern"))
        XCTAssertNil(DateParsing.parse(12345))
    }

    /// The whole point of parsing UTC: the UI shows local wall-clock time.
    func testUTCIsRenderedInLocalTime() throws {
        let saved = Formatting.calendar
        defer { Formatting.calendar = saved }

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        berlin.locale = Locale(identifier: "de_DE")
        Formatting.calendar = berlin

        let utcNoon = try XCTUnwrap(DateParsing.parse("2026-08-19T12:00:00+00:00"))
        // CEST is UTC+2 in August.
        XCTAssertEqual(Formatting.resetLabel(utcNoon, now: utcNoon), "14:00")
    }
}
