import SwiftUI

/// Everything a panel layout needs. Layouts are pure functions of this.
struct PanelData {
    let session: LimitWindow?
    let weekly: LimitWindow?
    let extras: [LimitWindow]
    let now: Date

    init(snapshot: UsageSnapshot, now: Date, showAllWindows: Bool) {
        let session = snapshot.session
        let weekly = snapshot.weekly
        self.session = session
        self.weekly = weekly
        self.now = now
        if showAllWindows {
            // Windows the headline pair does not already cover — e.g. the
            // model-scoped weekly limit that Max plans carry.
            self.extras = snapshot.windows.filter { $0.id != session?.id && $0.id != weekly?.id }
        } else {
            self.extras = []
        }
    }
}

// MARK: - 1a Doppelbalken

struct DoppelbalkenPanel: View {
    let data: PanelData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([data.session, data.weekly].compactMap { $0 }) { window in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(window.label)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                        Spacer(minLength: 8)
                        Text("\(window.roundedPercent) %")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Theme.primaryText)
                    }
                    MeterBar(fraction: window.percent / 100, color: Theme.accent(for: window))
                    ResetCaption(window: window, now: data.now)
                }
            }
            ForEach(data.extras) { ExtraWindowRow(window: $0, now: data.now) }
        }
    }
}

// MARK: - 1b Nur die Zahl

struct ZahlPanel: View {
    let data: PanelData

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 12, alignment: .topLeading),
         GridItem(.flexible(), spacing: 12, alignment: .topLeading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(([data.session, data.weekly].compactMap { $0 }) + data.extras) { window in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(window.roundedPercent) %")
                            .font(.system(size: 26, weight: .semibold).monospacedDigit())
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(window.label)
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                        if let resetsAt = window.resetsAt {
                            Text("Reset \(Formatting.resetLabel(resetsAt, now: data.now))")
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.accent(for: window))
                                .padding(.top, 3)
                            Text(Formatting.remainingLabel(resetsAt, now: data.now))
                                .font(.system(size: 10))
                                .foregroundColor(Theme.tertiaryText)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 1c Doppelring

struct DoppelringPanel: View {
    let data: PanelData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                RingPair(
                    sessionFraction: (data.session?.percent ?? 0) / 100,
                    weeklyFraction: (data.weekly?.percent ?? 0) / 100,
                    sessionColor: data.session.map(Theme.accent(for:)) ?? Theme.session,
                    weeklyColor: data.weekly.map(Theme.accent(for:)) ?? Theme.weekly
                )
                VStack(alignment: .leading, spacing: 11) {
                    ForEach([data.session, data.weekly].compactMap { $0 }) { window in
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent(for: window))
                                .frame(width: 7, height: 7)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(window.roundedPercent) % · \(window.label)")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundColor(Theme.primaryText)
                                if let resetsAt = window.resetsAt {
                                    Text("Reset \(Formatting.resetLabel(resetsAt, now: data.now))")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.tertiaryText)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            ForEach(data.extras) { ExtraWindowRow(window: $0, now: data.now) }
        }
    }
}

// MARK: - 1d Reset-Countdown

struct CountdownPanel: View {
    let data: PanelData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let session = data.session {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.label)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                        Spacer(minLength: 8)
                        Text("\(session.roundedPercent) % verbraucht")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Theme.primaryText)
                    }
                    // Thick bar with a marker at the fill edge, per design 1d.
                    GeometryReader { geometry in
                        let width = geometry.size.width * min(1, max(0, session.percent / 100))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Theme.accent(for: session).opacity(0.75))
                                .frame(width: width)
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 1.5)
                                .offset(x: max(0, width - 1.5))
                        }
                    }
                    .frame(height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    HStack {
                        // The 5-hour window is rolling: its start is simply the
                        // reset time minus five hours.
                        if let resetsAt = session.resetsAt {
                            Text("Start \(Formatting.resetLabel(resetsAt.addingTimeInterval(-5 * 3600), now: data.now))")
                            Spacer(minLength: 8)
                            Text("Reset \(Formatting.resetLabel(resetsAt, now: data.now))")
                        } else {
                            Text("Kein Reset-Zeitpunkt gemeldet")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiaryText)
                }
            }

            if let weekly = data.weekly {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(weekly.label)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                        Spacer(minLength: 8)
                        Text("\(weekly.roundedPercent) % verbraucht")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Theme.primaryText)
                    }
                    MeterBar(fraction: weekly.percent / 100,
                             color: Theme.accent(for: weekly),
                             trackColor: Color.white.opacity(0.12))
                    ResetCaption(window: weekly, now: data.now, font: .system(size: 10))
                }
            }

            ForEach(data.extras) { ExtraWindowRow(window: $0, now: data.now) }
        }
    }
}

// MARK: - 1e Segmente

struct SegmentePanel: View {
    let data: PanelData

    /// Design 1e draws the week as a row of blocks. Per-day history does not
    /// exist yet (runbook stage 2), so the blocks divide the single weekly
    /// figure rather than inventing daily values.
    private func filled(_ percent: Double, of count: Int) -> Int {
        min(count, Int(ceil(percent / 100 * Double(count))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let session = data.session {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(session.label)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                        Spacer(minLength: 8)
                        Text("\(session.roundedPercent) %")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Theme.primaryText)
                    }
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(index < filled(session.percent, of: 5)
                                      ? Theme.accent(for: session)
                                      : Color.white.opacity(0.16))
                                .frame(height: 16)
                        }
                    }
                    ResetCaption(window: session, now: data.now)
                }
            }

            if let weekly = data.weekly {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(weekly.label)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                        Spacer(minLength: 8)
                        Text("\(weekly.roundedPercent) %")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Theme.primaryText)
                    }
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(index < filled(weekly.percent, of: 7)
                                      ? Theme.accent(for: weekly)
                                      : Color.white.opacity(0.16))
                                .frame(height: 16)
                        }
                    }
                    ResetCaption(window: weekly, now: data.now)
                }
            }

            ForEach(data.extras) { ExtraWindowRow(window: $0, now: data.now) }
        }
    }
}

// MARK: - Runbook layout

struct ZahlenpaarPanel: View {
    let data: PanelData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(([data.session, data.weekly].compactMap { $0 }) + data.extras) { window in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(window.label)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                            .frame(width: 74, alignment: .leading)
                        MeterBar(fraction: window.percent / 100,
                                 color: Theme.accent(for: window),
                                 height: 6)
                        Text("\(Formatting.fixedWidthPercent(window.roundedPercent)) %")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Theme.primaryText)
                    }
                    if let resetsAt = window.resetsAt {
                        HStack(spacing: 6) {
                            Text("↻ \(Formatting.resetLabel(resetsAt, now: data.now))")
                            Text("(\(Formatting.remainingLabel(resetsAt, now: data.now)))")
                        }
                        .font(.system(size: 10))
                        .foregroundColor(Theme.tertiaryText)
                        .padding(.leading, 82)
                    }
                }
            }
        }
    }
}
