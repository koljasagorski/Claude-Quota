import Foundation
import ClaudeMeterKit

// Runs the same token resolution, request and parsing the app performs, and
// reports each stage. Use it when the panel shows an error and you want to know
// which stage failed.
//
//   swift run claudemeter-doctor
//
// The access token is never printed, logged or written anywhere.

func line(_ symbol: String, _ text: String) { print("\(symbol) \(text)") }

let ok = "\u{2713}", bad = "\u{2717}", info = "·"

print("ClaudeMeter Doctor")
print(String(repeating: "─", count: 52))

// 1 — credential
print("\n1. Anmeldung")
let provider = TokenProvider()
let credential: TokenProvider.Credential
do {
    credential = try provider.resolve()
    line(ok, "Quelle: \(credential.sourceDescription)")
    line(info, "Abo: \(credential.subscriptionType ?? "unbekannt") · Tarif: \(credential.rateLimitTier ?? "unbekannt")")
    if let expiresAt = credential.expiresAt {
        let minutes = Int(expiresAt.timeIntervalSinceNow / 60)
        line(info, "Token läuft \(minutes > 0 ? "in \(minutes) Min ab" : "ist abgelaufen")")
    } else {
        line(info, "Kein Ablaufdatum hinterlegt")
    }
    line(info, "Token-Länge: \(credential.accessToken.count) Zeichen (Wert wird nicht ausgegeben)")
} catch let error as FetchError {
    line(bad, error.message)
    if case .noToken = error {
        print("\n  Prüfen:")
        print("    security find-generic-password -s 'Claude Code-credentials' -w | jq '.claudeAiOauth.subscriptionType'")
    }
    exit(1)
} catch {
    line(bad, "\(error)")
    exit(1)
}

// 2 — request
print("\n2. Abfrage")
let client = UsageClient()
let semaphore = DispatchSemaphore(value: 0)
var result: Result<UsageSnapshot, Error>?

Task {
    line(info, "GET \(UsageClient.endpoint.absoluteString)")
    line(info, "anthropic-beta: \(UsageClient.betaHeader)")
    line(info, "User-Agent: \(await client.resolveUserAgent())")
    do { result = .success(try await client.fetch()) }
    catch { result = .failure(error) }
    semaphore.signal()
}

guard semaphore.wait(timeout: .now() + 30) == .success, let result else {
    line(bad, "Zeitüberschreitung nach 30 s")
    exit(1)
}

switch result {
case .failure(let error):
    line(bad, (error as? FetchError)?.message ?? "\(error)")
    exit(1)

case .success(let snapshot):
    line(ok, "HTTP 200, \(snapshot.windows.count) Limit-Fenster erkannt")

    print("\n3. Normalisierte Fenster")
    for window in snapshot.windows {
        let reset = window.resetsAt.map {
            "\(Formatting.resetLabel($0)) (\(Formatting.remainingLabel($0)))"
        } ?? "kein Reset gemeldet"
        let bar = String(repeating: "█", count: Int(window.percent / 100 * 20))
            + String(repeating: "░", count: 20 - Int(window.percent / 100 * 20))
        // String(format:) pads by UTF-16 unit, which mangles labels containing
        // "·" — pad manually instead.
        let label = window.label.padding(toLength: max(16, window.label.count), withPad: " ", startingAt: 0)
        print("   \(label) \(bar) \(String(format: "%3d", window.roundedPercent)) %  ↻ \(reset)")
        print("      kind=\(window.kind) group=\(window.group.rawValue) aktiv=\(window.isActive ? "ja" : "nein")")
    }

    print("\n4. Menüleisten-Werte")
    line(info, "5 Std.: \(snapshot.session.map { "\($0.roundedPercent) %" } ?? "–")")
    line(info, "Woche:  \(snapshot.weekly.map { "\($0.roundedPercent) %" } ?? "–")")
    line(info, "Spitze: \(Int(snapshot.peakPercent.rounded())) %"
              + (snapshot.peakPercent >= 80 ? "  ⚠︎ Warnschwelle erreicht" : ""))

    print("\nAlles in Ordnung.")
}
