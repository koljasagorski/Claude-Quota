import XCTest
import AppKit
import SwiftUI
@testable import ClaudeMeterKit

@MainActor
final class BackoffBehaviourTests: XCTestCase {

    private func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            windows: [LimitWindow(id: "session", kind: "session", label: "5 Std.",
                                  percent: 21, resetsAt: nil, group: .session)],
            fetchedAt: Date()
        )
    }

    private func makeStore() -> UsageStore {
        let store = UsageStore()
        // Prevents any real request: performFetch() returns early while asleep.
        store.handleSleep()
        return store
    }

    /// Runbook §7: 5 → 10 → 20 → 30 minutes, then hold at 30.
    func testRateLimitLadderEscalates() {
        let store = makeStore()
        var delays: [TimeInterval] = []
        for _ in 0..<6 {
            store.simulateResultForTesting(.failure(.rateLimited(retryAfter: nil)))
            delays.append(store.lastScheduledDelayForTesting ?? -1)
        }
        XCTAssertEqual(delays, [300, 600, 1200, 1800, 1800, 1800])
    }

    /// The regression this test exists for: `refreshNow()` used to reset the
    /// ladder, so a user checking the panel every minute kept the app pinned to
    /// the 5-minute rung while the server was rate limiting it.
    func testManualRefreshDoesNotResetTheLadder() {
        let store = makeStore()
        store.simulateResultForTesting(.failure(.rateLimited(retryAfter: nil)))
        store.simulateResultForTesting(.failure(.rateLimited(retryAfter: nil)))
        XCTAssertEqual(store.backoffIndexForTesting, 2)

        store.refreshNow()
        XCTAssertEqual(store.backoffIndexForTesting, 2, "manual refresh must not reset the backoff")

        store.refreshIfStale()
        XCTAssertEqual(store.backoffIndexForTesting, 2, "opening the panel must not reset the backoff")

        store.simulateResultForTesting(.failure(.rateLimited(retryAfter: nil)))
        XCTAssertEqual(store.lastScheduledDelayForTesting, 1200, "ladder must keep escalating")
    }

    /// Runbook §7: the ladder resets on HTTP 200 — and only there.
    func testSuccessResetsTheLadder() {
        let store = makeStore()
        store.simulateResultForTesting(.failure(.rateLimited(retryAfter: nil)))
        store.simulateResultForTesting(.failure(.rateLimited(retryAfter: nil)))
        XCTAssertEqual(store.backoffIndexForTesting, 2)

        store.simulateResultForTesting(.success(snapshot()))
        XCTAssertEqual(store.backoffIndexForTesting, 0)
        XCTAssertEqual(store.lastScheduledDelayForTesting, UsageStore.baseInterval)
    }

    /// Criterion 5: the last good value survives a failure, marked stale.
    func testFailureKeepsTheLastGoodSnapshot() {
        let store = makeStore()
        store.simulateResultForTesting(.success(snapshot()))
        store.simulateResultForTesting(.failure(.unauthorized))

        guard case .stale(let kept, let error) = store.state else {
            return XCTFail("expected .stale, got \(store.state)")
        }
        XCTAssertEqual(kept.session?.roundedPercent, 21)
        XCTAssertEqual(error, .unauthorized)
    }

    func testFailureWithoutAnyPriorSnapshotIsFailed() {
        let store = makeStore()
        store.simulateResultForTesting(.failure(.noToken))
        XCTAssertEqual(store.state.error, .noToken)
        XCTAssertNil(store.state.snapshot)
    }

    /// Going to sleep cancels the in-flight request. That cancellation must not
    /// surface as a network error the user never experienced.
    func testSleepCancellationIsNotReportedAsAnError() {
        let store = UsageStore()
        store.simulateResultForTesting(.success(snapshot()))

        let generation = store.fetchGenerationForTesting
        store.handleSleep()   // bumps the generation, cancelling the fetch
        store.finishForTesting(generation: generation,
                               with: .failure(.transient("Vorgang abgebrochen")))

        XCTAssertNil(store.state.error, "a fetch abandoned on sleep must not become a visible error")
        guard case .ready = store.state else {
            return XCTFail("state should still be .ready, got \(store.state)")
        }
    }
}

/// Acceptance criterion 2: the menu bar label must never change width.
/// These measure real glyph advances rather than counting characters.
final class LabelWidthTests: XCTestCase {

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    private func width(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    func testEveryPercentValueRendersAtTheSameWidth() {
        let reference = width("100 %")
        for value in 0...100 {
            XCTAssertEqual(width("\(Formatting.fixedWidthPercent(value)) %"), reference,
                           accuracy: 0.01, "percent \(value) changed the label width")
        }
    }

    /// The regression: the old placeholder used EN DASH (7.002 pt), not a
    /// digit-width glyph (7.559 pt), so the label jumped the moment the first
    /// values arrived.
    func testPlaceholderMatchesTheWidthOfRealValues() {
        XCTAssertEqual(width("\(Formatting.placeholderPercent()) %"), width("100 %"), accuracy: 0.01)
        XCTAssertEqual(width(Formatting.figureDash), width("0"), accuracy: 0.01)
        XCTAssertEqual(width(Formatting.figureSpace), width("0"), accuracy: 0.01)
        XCTAssertNotEqual(width("\u{2013}"), width("0"), accuracy: 0.01,
                          "EN DASH is not digit-width — that is why it must not be used here")
    }

    /// The regression: a two-digit budget silently grew to three at 100 %,
    /// because `fixedWidthPercent` cannot truncate.
    func testZahlenpaarIsStableIncludingAtOneHundredPercent() {
        func pair(_ session: Int, _ weekly: Int) -> String {
            "\(Formatting.fixedWidthPercent(session))·\(Formatting.fixedWidthPercent(weekly))"
        }
        let reference = width(pair(100, 100))
        for session in [0, 7, 21, 73, 99, 100] {
            for weekly in [0, 7, 21, 73, 99, 100] {
                XCTAssertEqual(width(pair(session, weekly)), reference, accuracy: 0.01,
                               "pair \(session)·\(weekly) changed the label width")
            }
        }
        let placeholder = "\(Formatting.placeholderPercent())·\(Formatting.placeholderPercent())"
        XCTAssertEqual(width(placeholder), reference, accuracy: 0.01)
    }

    /// Runbook §13: the label must stay narrow enough for a notch Mac.
    func testLabelStaysWithinSevenCells() {
        XCTAssertEqual(Formatting.fixedWidthPercent(100).count, 3)
        let pair = "\(Formatting.fixedWidthPercent(100))·\(Formatting.fixedWidthPercent(100))"
        XCTAssertEqual(pair.count, 7)
    }
}

/// The panel must satisfy criterion 3 for every window, in every design.
@MainActor
final class PanelCoverageTests: XCTestCase {

    /// Both `resetLabel` and `remainingLabel` must appear for a window — a
    /// clock time alone, or a countdown alone, fails the criterion.
    func testResetIsShownAsBothClockTimeAndRemainingRuntime() throws {
        let now = Date()
        let resetsAt = now.addingTimeInterval(2 * 3600 + 13 * 60)
        let clock = Formatting.resetLabel(resetsAt, now: now)
        let remaining = Formatting.remainingLabel(resetsAt, now: now)

        XCTAssertFalse(clock.isEmpty)
        XCTAssertFalse(remaining.isEmpty)
        XCTAssertNotEqual(clock, remaining)
        XCTAssertTrue(remaining.hasPrefix("in "))
    }

    /// Every design must render without crashing for 1, 2, 3 and 4 windows —
    /// Pro accounts report one weekly window, Max accounts up to three.
    func testAllDesignsRenderForEveryAccountShape() {
        let now = Date()
        let all: [LimitWindow] = [
            LimitWindow(id: "session", kind: "session", label: "5 Std.", percent: 0,
                        resetsAt: now.addingTimeInterval(3600), group: .session),
            LimitWindow(id: "weekly_all", kind: "weekly_all", label: "Woche", percent: 100,
                        resetsAt: now.addingTimeInterval(86400), group: .weekly),
            LimitWindow(id: "weekly_scoped:Sonnet", kind: "weekly_scoped", label: "Woche · Sonnet",
                        percent: 39, resetsAt: now.addingTimeInterval(86400), group: .weekly),
            LimitWindow(id: "monthly_x", kind: "monthly_x", label: "Weekly Oauth Apps",
                        percent: 3, resetsAt: nil, group: .other)
        ]

        for count in 1...4 {
            let snapshot = UsageSnapshot(windows: Array(all.prefix(count)), fetchedAt: now)
            for style in DesignStyle.allCases {
                let view = Preview.StaticPanel(style: style, snapshot: snapshot, now: now)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                XCTAssertNotNil(renderer.nsImage,
                                "\(style.rawValue) failed to render with \(count) window(s)")
            }
        }
    }

    /// Menu bar glyphs must render at every extreme without producing NaN.
    func testGlyphsRenderAtExtremes() {
        for (session, weekly) in [(0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0, 1.0), (0.005, 0.5)] {
            let values = GlyphValues(sessionFraction: session, weeklyFraction: weekly,
                                     countdown: "2:13", hasData: true)
            for colored in [true, false] {
                let palette = colored
                    ? GlyphPalette.colored(sessionWarning: false, weeklyWarning: false)
                    : GlyphPalette.template
                XCTAssertNotNil(GlyphRenderer.image(DoppelbalkenGlyph(values: values, palette: palette),
                                                    size: DoppelbalkenGlyph.size, isTemplate: !colored))
                XCTAssertNotNil(GlyphRenderer.image(DoppelringGlyph(values: values, palette: palette),
                                                    size: DoppelringGlyph.size, isTemplate: !colored))
                XCTAssertNotNil(GlyphRenderer.image(CountdownGlyph(values: values, palette: palette),
                                                    size: CountdownGlyph.size, isTemplate: !colored))
                XCTAssertNotNil(GlyphRenderer.image(SegmenteGlyph(values: values, palette: palette),
                                                    size: SegmenteGlyph.size, isTemplate: !colored))
            }
        }
    }
}
