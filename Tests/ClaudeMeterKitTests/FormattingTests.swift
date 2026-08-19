import XCTest
@testable import ClaudeMeterKit

final class FormattingTests: XCTestCase {

    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }

    override func setUp() {
        super.setUp()
        Formatting.calendar = berlin
    }

    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(DateParsing.parse(iso))
    }

    func testRemainingLabels() throws {
        let now = try date("2026-08-19T12:00:00Z")
        XCTAssertEqual(Formatting.remainingLabel(try date("2026-08-19T14:13:00Z"), now: now), "in 2 Std 13 Min")
        XCTAssertEqual(Formatting.remainingLabel(try date("2026-08-19T15:00:00Z"), now: now), "in 3 Std")
        XCTAssertEqual(Formatting.remainingLabel(try date("2026-08-19T12:30:00Z"), now: now), "in 30 Min")
        XCTAssertEqual(Formatting.remainingLabel(try date("2026-08-22T18:00:00Z"), now: now), "in 3 T 6 Std")
        XCTAssertEqual(Formatting.remainingLabel(try date("2026-08-24T12:00:00Z"), now: now), "in 5 T")
    }

    /// A window that already reset reads "jetzt", never a negative duration.
    func testElapsedWindowReadsAsNow() throws {
        let now = try date("2026-08-19T12:00:00Z")
        XCTAssertEqual(Formatting.remainingLabel(try date("2026-08-19T11:00:00Z"), now: now), "jetzt")
    }

    func testResetLabelSwitchesFormatWithDistance() throws {
        let now = try date("2026-08-19T12:00:00Z")               // Wed, 14:00 Berlin
        XCTAssertEqual(Formatting.resetLabel(try date("2026-08-19T14:45:00Z"), now: now), "16:45")
        XCTAssertTrue(Formatting.resetLabel(try date("2026-08-20T07:00:00Z"), now: now).hasPrefix("morgen"))
        XCTAssertTrue(Formatting.resetLabel(try date("2026-08-21T18:00:00Z"), now: now).contains("20:00"))
        XCTAssertTrue(Formatting.resetLabel(try date("2026-09-24T07:00:00Z"), now: now).contains("24."))
    }

    func testCompactCountdownStaysNarrow() throws {
        let now = try date("2026-08-19T12:00:00Z")
        XCTAssertEqual(Formatting.compactCountdown(try date("2026-08-19T14:13:00Z"), now: now), "2:13")
        XCTAssertEqual(Formatting.compactCountdown(try date("2026-08-19T12:07:00Z"), now: now), "0:07")
        XCTAssertEqual(Formatting.compactCountdown(try date("2026-08-22T18:00:00Z"), now: now), "3\u{2009}T")
        XCTAssertEqual(Formatting.compactCountdown(nil, now: now), "–:––")
        // Never wider than five glyphs, whatever the input.
        for hours in stride(from: 0, through: 24 * 9, by: 7) {
            let target = now.addingTimeInterval(Double(hours) * 3600)
            XCTAssertLessThanOrEqual(Formatting.compactCountdown(target, now: now).count, 5)
        }
    }

    /// Acceptance criterion 2: the label must never change width, or every icon
    /// to its left in the menu bar shifts.
    func testFixedWidthPercentIsAlwaysTheSameLength() {
        for value in 0...100 {
            XCTAssertEqual(Formatting.fixedWidthPercent(value).count, 3, "value \(value)")
            XCTAssertEqual(Formatting.fixedWidthPercent(value, digits: 2).count,
                           value >= 100 ? 3 : 2, "value \(value)")
        }
        XCTAssertEqual(Formatting.fixedWidthPercent(7), "\u{2007}\u{2007}7")
        XCTAssertEqual(Formatting.fixedWidthPercent(100), "100")
    }

    func testAgoLabels() throws {
        let now = try date("2026-08-19T12:00:00Z")
        XCTAssertEqual(Formatting.agoLabel(now, now: now), "gerade aktualisiert")
        XCTAssertEqual(Formatting.agoLabel(now.addingTimeInterval(-60), now: now), "aktualisiert vor 1 Min")
        XCTAssertEqual(Formatting.agoLabel(now.addingTimeInterval(-600), now: now), "aktualisiert vor 10 Min")
        XCTAssertEqual(Formatting.agoLabel(now.addingTimeInterval(-7200), now: now), "aktualisiert vor 2 Std")
        // Clock skew must not produce "vor -3 Min".
        XCTAssertEqual(Formatting.agoLabel(now.addingTimeInterval(180), now: now), "gerade aktualisiert")
    }

    func testFreshnessLabel() throws {
        let now = try date("2026-08-19T12:00:00Z")
        XCTAssertEqual(Formatting.freshnessLabel(fetchedAt: now.addingTimeInterval(-120), now: now),
                       "aktualisiert vor 2 Min · alle 5 Min")
    }
}

final class SnapshotSelectionTests: XCTestCase {

    private func window(_ kind: String, _ group: LimitWindow.Group, _ percent: Double) -> LimitWindow {
        LimitWindow(id: kind, kind: kind, label: kind, percent: percent, resetsAt: nil, group: group)
    }

    /// On Max plans several weekly windows exist. The menu bar must show the
    /// account-wide one, not whichever model-scoped limit happens to come first.
    func testWeeklyPrefersAccountWideWindow() {
        let snapshot = UsageSnapshot(
            windows: [window("weekly_scoped", .weekly, 7),
                      window("weekly_all", .weekly, 73),
                      window("session", .session, 21)],
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.weekly?.kind, "weekly_all")
        XCTAssertEqual(snapshot.session?.roundedPercent, 21)
        XCTAssertEqual(snapshot.peakPercent, 73)
    }

    /// Pro accounts have exactly one weekly window and no scoped one.
    func testProAccountShapeWorks() {
        let snapshot = UsageSnapshot(
            windows: [window("session", .session, 5), window("weekly_all", .weekly, 40)],
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.weekly?.roundedPercent, 40)
    }

    func testFallsBackToScopedWeeklyWhenNoAccountWideWindowExists() {
        let snapshot = UsageSnapshot(windows: [window("weekly_scoped", .weekly, 7)], fetchedAt: Date())
        XCTAssertEqual(snapshot.weekly?.kind, "weekly_scoped")
    }
}

final class DesignStyleTests: XCTestCase {

    /// The settings list is generated from `allCases`; every case needs its
    /// copy, or an option renders blank.
    func testEveryStyleIsFullyDescribed() {
        XCTAssertEqual(DesignStyle.allCases.count, 6)
        for style in DesignStyle.allCases {
            XCTAssertFalse(style.title.isEmpty, "\(style)")
            XCTAssertFalse(style.summary.isEmpty, "\(style)")
            XCTAssertFalse(style.code.isEmpty, "\(style)")
            XCTAssertFalse(style.footprint.isEmpty, "\(style)")
        }
        XCTAssertEqual(Set(DesignStyle.allCases.map(\.code)).count, 6)
    }

    /// Raw values are persisted in UserDefaults — renaming one silently resets
    /// the user's choice.
    func testRawValuesAreStable() {
        XCTAssertEqual(DesignStyle.allCases.map(\.rawValue),
                       ["doppelbalken", "zahl", "doppelring", "countdown", "segmente", "zahlenpaar"])
    }

    func testUnknownStoredStyleFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "de.sagorski.claudemeter.tests")!
        defaults.removePersistentDomain(forName: "de.sagorski.claudemeter.tests")
        defaults.set("nonexistent_style", forKey: "designStyle")
        let settings = MainActor.assumeIsolated { AppSettings(defaults: defaults) }
        XCTAssertEqual(MainActor.assumeIsolated { settings.style }, .doppelring)
    }
}

final class GlyphTests: XCTestCase {

    /// Any usage at all must light the first pip; 100 % must light all five.
    func testSegmentPipsMapSensibly() {
        XCTAssertEqual(SegmenteGlyph.filledPips(0), 0)
        XCTAssertEqual(SegmenteGlyph.filledPips(0.01), 1)
        XCTAssertEqual(SegmenteGlyph.filledPips(0.2), 1)
        XCTAssertEqual(SegmenteGlyph.filledPips(0.21), 2)
        XCTAssertEqual(SegmenteGlyph.filledPips(1.0), 5)
        XCTAssertEqual(SegmenteGlyph.filledPips(1.5), 5)
    }

    /// Fractions are clamped before they ever reach a shape.
    func testGlyphValuesClamp() {
        let values = GlyphValues(sessionFraction: 1.9, weeklyFraction: -0.4, countdown: "1:00", hasData: true)
        XCTAssertEqual(values.sessionFraction, 1)
        XCTAssertEqual(values.weeklyFraction, 0)
    }
}
