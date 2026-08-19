import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// Owns the polling loop and the single source of truth for the UI.
@MainActor
public final class UsageStore: ObservableObject {

    @Published public private(set) var state: UsageState = .loading
    /// Ticks once a minute so relative labels ("in 2 Std 13 Min") stay honest
    /// without refetching.
    @Published public private(set) var clock: Date = Date()

    /// Runbook default. Never goes below 60 s.
    public static let baseInterval: TimeInterval = 300
    /// Backoff ladder used on 429, in minutes.
    static let backoffLadder: [TimeInterval] = [300, 600, 1200, 1800]
    /// Opening the panel refreshes, but not more often than this.
    static let manualRefreshFloor: TimeInterval = 60

    private let client: UsageClient
    private var pollTimer: Timer?
    private var clockTimer: Timer?
    private var inFlight: Task<Void, Never>?
    fileprivate var backoffIndexStorage: Int = 0
    private var isAsleep = false
    private var lastAttempt: Date?
    /// When the next scheduled poll is due. Used to honour an active backoff
    /// instead of the 60 s floor when the panel is opened.
    private var nextPollAt: Date?
    /// Identifies the fetch currently allowed to publish a result. Bumped when
    /// a fetch is abandoned (sleep), so its cancellation cannot land as a
    /// user-visible "network error".
    fileprivate var fetchGenerationStorage: UInt64 = 0
    private var observers: [NSObjectProtocol] = []
    fileprivate var lastScheduledDelayStorage: TimeInterval?

    public init(client: UsageClient = UsageClient()) {
        self.client = client
    }

    deinit {
        pollTimer?.invalidate()
        clockTimer?.invalidate()
    }

    // MARK: - Lifecycle

    public func start() {
        installSleepWakeObservers()
        scheduleClock()
        schedulePoll(after: 0)
    }

    public func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        clockTimer?.invalidate(); clockTimer = nil
        inFlight?.cancel(); inFlight = nil
        #if canImport(AppKit)
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        #endif
        observers.removeAll()
    }

    // MARK: - Refresh triggers

    /// Called when the panel opens. Click-spam must not provoke a 429, so this
    /// is a no-op if the last attempt was under a minute ago — and while the
    /// backoff ladder is active it defers to the ladder instead, otherwise
    /// checking the panel would pin the app to its fastest cadence at exactly
    /// the moment the server is asking it to slow down.
    public func refreshIfStale() {
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.manualRefreshFloor { return }
        if case .rateLimited = state.error, let nextPollAt, Date() < nextPollAt { return }
        performFetch()
    }

    /// "Jetzt aktualisieren".
    ///
    /// Deliberately does *not* reset the backoff ladder: per runbook §7 the
    /// ladder resets on HTTP 200 only. Resetting it here would let a user who
    /// keeps checking the panel hold the app at the 5-minute rung forever.
    public func refreshNow() {
        performFetch()
    }

    // MARK: - Fetching

    private func performFetch() {
        // Exactly one request in flight; parallel triggers are dropped, not queued.
        guard inFlight == nil else { return }
        guard !isAsleep else { return }

        lastAttempt = Date()
        fetchGenerationStorage &+= 1
        let generation = fetchGenerationStorage

        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.client.fetch()
                self.finishEntryPoint(generation: generation, with: .success(snapshot))
            } catch let error as FetchError {
                self.finishEntryPoint(generation: generation, with: .failure(error))
            } catch {
                self.finishEntryPoint(generation: generation, with: .failure(.transient(error.localizedDescription)))
            }
        }
    }

    fileprivate func finishEntryPoint(generation: UInt64, with result: Result<UsageSnapshot, FetchError>) {
        // A fetch abandoned on sleep must not surface its own cancellation as a
        // network error the user never experienced.
        guard generation == fetchGenerationStorage else { return }
        inFlight = nil

        switch result {
        case .success(let snapshot):
            backoffIndexStorage = 0
            state = .ready(snapshot)
            schedulePoll(after: Self.baseInterval)

        case .failure(let error):
            // Never silently show yesterday's numbers: keep the last good
            // snapshot but mark it stale so the UI can age it.
            if let previous = state.snapshot {
                state = .stale(previous, error)
            } else {
                state = .failed(error)
            }

            if case .rateLimited = error {
                let delay = Self.backoffLadder[min(backoffIndexStorage, Self.backoffLadder.count - 1)]
                backoffIndexStorage = min(backoffIndexStorage + 1, Self.backoffLadder.count - 1)
                schedulePoll(after: delay)
            } else if error.isTerminal {
                // No point hammering: recheck at the normal cadence only.
                schedulePoll(after: Self.baseInterval)
            } else {
                schedulePoll(after: Self.baseInterval)
            }
        }
    }

    // MARK: - Timers

    private func schedulePoll(after delay: TimeInterval) {
        pollTimer?.invalidate()
        let interval = max(0, delay)
        lastScheduledDelayStorage = interval

        if interval == 0 {
            nextPollAt = Date()
            performFetch()
            return
        }

        nextPollAt = Date().addingTimeInterval(interval)

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.performFetch() }
        }
        // Lets macOS coalesce wake-ups instead of firing on the exact second.
        timer.tolerance = min(30, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func scheduleClock() {
        clockTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.clock = Date() }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    // MARK: - Sleep / wake

    private func installSleepWakeObservers() {
        #if canImport(AppKit)
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
        #endif
    }

    func handleSleep() {
        isAsleep = true
        pollTimer?.invalidate(); pollTimer = nil
        nextPollAt = nil
        // Bump first: the cancellation below makes the in-flight request throw,
        // and the stale generation stops that from becoming a visible error.
        fetchGenerationStorage &+= 1
        inFlight?.cancel(); inFlight = nil
    }

    func handleWake() {
        isAsleep = false
        clock = Date()
        // After any sleep the numbers are guaranteed stale.
        refreshNow()
    }
}

#if DEBUG
extension UsageStore {

    /// Test hooks. These drive the state machine directly so the polling and
    /// backoff behaviour can be asserted without a network round trip.
    var backoffIndexForTesting: Int { backoffIndexStorage }
    var lastScheduledDelayForTesting: TimeInterval? { lastScheduledDelayStorage }
    var fetchGenerationForTesting: UInt64 { fetchGenerationStorage }

    func simulateResultForTesting(_ result: Result<UsageSnapshot, FetchError>) {
        fetchGenerationStorage &+= 1
        finishForTesting(generation: fetchGenerationStorage, with: result)
    }

    func finishForTesting(generation: UInt64, with result: Result<UsageSnapshot, FetchError>) {
        finishEntryPoint(generation: generation, with: result)
    }
}
#endif
