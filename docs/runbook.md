# Runbook: Menüleisten-App für Claude-Abo-Verbrauch (macOS)

Arbeitsname: **ClaudeMeter**
Zielplattform: macOS 13+ (Apple Silicon & Intel)
Adressat: Claude Code

---

## 0. Auftrag in einem Satz

Eine dauerhaft laufende, dock-lose macOS-App, die in der Menüleiste rechts neben der Uhr die
aktuelle Auslastung des Claude-Abos anzeigt (5-Stunden-Session-Fenster und Wochenlimit),
alle 5 Minuten aktualisiert und beim Anklicken die Reset-Zeitpunkte zeigt.

**Terminologie-Korrektur:** Das kurze Fenster ist ein **rollierendes 5-Stunden-Fenster**, kein
4-Stunden-Fenster. Das Wochenlimit resettet zu einem kontoindividuellen festen Zeitpunkt; auf
Max-Plänen existiert zusätzlich ein modellspezifisches (Sonnet-)Wochenlimit. Die App muss alle
gelieferten Fenster darstellen können, nicht nur zwei fest verdrahtete.

---

## 1. Wichtig vorab — Risikohinweis, der ins README gehört

Die Verbrauchsdaten stammen von einem **undokumentierten, inoffiziellen Endpoint**
(`/api/oauth/usage`), den Claude Code intern nutzt. Konsequenzen, die die Architektur bestimmen:

- Das Antwortschema hat sich in der Vergangenheit geändert (flache Keys → strukturiertes
  `limits`-Array). **Der Parser muss tolerant sein und darf bei unbekannten Feldern nicht
  crashen.**
- Der Endpoint wird aggressiv ratenbegrenzt (HTTP 429). **Polling-Intervall nie unter 60 s,
  Default 5 min, Backoff bei 429 zwingend.**
- Der Beta-Header trägt ein Datum im Namen. Ändert Anthropic ihn, bricht die App **still**.
  Deshalb: sichtbarer Fehlerzustand in der UI, keine stille Anzeige veralteter Werte.
- Die App darf **niemals** die OAuth-Credentials von Claude Code überschreiben oder einen
  Token-Refresh auslösen, der das Refresh-Token rotiert — das würde die Anmeldung von Claude
  Code selbst kaputt machen. **Nur lesender Zugriff.**

---

## 2. Akzeptanzkriterien (Definition of Done)

1. App startet ohne Dock-Icon und ohne Fenster, erscheint nur in der Menüleiste.
2. Menüleisten-Label ist maximal ~7 Zeichen breit und **springt nicht** in der Breite.
3. Klick öffnet ein kompaktes Panel mit: pro Limit-Fenster ein Balken, Prozentwert,
   Reset-Zeitpunkt als Uhrzeit **und** als Restlaufzeit.
4. Auto-Refresh alle 5 min; zusätzlich sofortiger Refresh beim Öffnen des Panels und nach
   Aufwachen aus dem Ruhezustand.
5. Bei Fehler (401/429/Netz/Parsing) bleibt der letzte bekannte Wert sichtbar, wird aber als
   veraltet markiert (Alter in Minuten), und das Panel nennt den konkreten Fehler.
6. `codesign -dv` läuft sauber durch; App startet nach Neustart automatisch (optional zuschaltbar).
7. Ruhezustand-Verbrauch: keine Netzwerkaufrufe, wenn der Deckel zu ist / System schläft.

---

## 3. Schritt 0 — Datenquelle verifizieren, BEVOR eine Zeile Swift geschrieben wird

**Diese Phase nicht überspringen.** Die exakte Antwortstruktur muss aus dem echten Konto
kommen, nicht aus Annahmen dieses Runbooks.

### 3.1 Token finden

Claude Code legt die Credentials auf macOS **bevorzugt im Schlüsselbund** ab, nicht als Datei.
Beide Wege prüfen:

```bash
# a) Schlüsselbund — Dienstname kann eine Installations-GUID als Suffix tragen
security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | head -c 40; echo
security dump-keychain 2>/dev/null | grep -i "Claude Code-credentials"

# b) Datei-Fallback
cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" | jq '.claudeAiOauth | {subscriptionType, rateLimitTier, expiresAt}'
```

Erwartete Struktur in beiden Fällen:

```json
{ "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-…",
    "refreshToken": "sk-ant-ort01-…",
    "expiresAt": 1770412938485,
    "subscriptionType": "max",
    "rateLimitTier": "default_claude_max_5x" } }
```

### 3.2 Endpoint einmal manuell abfragen

```bash
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
        | jq -r '.claudeAiOauth.accessToken')
[ -z "$TOKEN" ] && TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$HOME/.claude/.credentials.json")

curl -s --max-time 10 https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "User-Agent: claude-code/$(claude --version | awk '{print $1}')" \
  -H "Content-Type: application/json" | jq .
```

**Der `User-Agent: claude-code/<version>` ist nicht optional.** Ohne ihn landet die Anfrage in
einem deutlich schärferen Rate-Limit-Bucket und liefert dauerhaft 429.

### 3.3 Antwort dokumentieren

Rohantwort nach `docs/usage-schema-sample.json` schreiben (Token vorher entfernen) und die
tatsächlich vorhandenen Felder in `docs/DATA-SOURCE.md` festhalten. Zwei Schemata sind in freier
Wildbahn belegt — **die App muss beide lesen können**:

*Variante A (flach):*
```json
{ "five_hour":  { "utilization": 35.0, "resets_at": "2026-08-19T22:00:00+00:00" },
  "seven_day":  { "utilization": 14.0, "resets_at": "2026-08-22T20:00:00+00:00" },
  "seven_day_sonnet": { "utilization": 39.0, "resets_at": "…" },
  "seven_day_opus": null,
  "extra_usage": { "is_enabled": true, "monthly_limit": 100000, "used_credits": 0.0 } }
```

*Variante B (strukturiert, neuer):* die flachen `seven_day_*`-Keys sind `null`, die echten Daten
liegen in einem `limits`-Array mit Einträgen der Form `{ kind, percent, resets_at, scope }`,
wobei `kind` u. a. `session`, `weekly_all`, `weekly_scoped` annimmt.

**Zu klärender Punkt in Schritt 0:** Ist `utilization` 0–100 oder 0–1? Quellen widersprechen sich.
Aus der realen Antwort ableiten und in `DATA-SOURCE.md` notieren. Defensiv implementieren:
Werte > 1.0 als Prozent behandeln, Werte ≤ 1.0 nur dann als Bruch, wenn Schritt 0 das bestätigt
— sonst wird 0.8 % fälschlich zu 80 %.

### 3.4 Alternative Token-Quelle prüfen

`claude setup-token` erzeugt ein langlebiges OAuth-Token (für CI gedacht). Falls es gegen
`/api/oauth/usage` funktioniert, ist es die **sauberere Quelle**: kein Zugriff auf den
Schlüsselbund-Eintrag von Claude Code, kein stündliches Ablaufen. In Schritt 0 gegentesten und
das Ergebnis in `DATA-SOURCE.md` festhalten. Wenn es funktioniert → als primäre Quelle
implementieren, Schlüsselbund/Datei als Fallback.

---

## 4. Technologieentscheidung

**Swift + SwiftUI `MenuBarExtra`, gebaut mit SwiftPM, ohne Xcode-Projektdatei.**

Begründung: keine Runtime-Abhängigkeit (kein Node, kein Python), ~2 MB Binary, natives Verhalten
bei Dark Mode / Notch / Sonoma-Menüleiste, und der ganze Build läuft headless über
`swift build` — für dich als Agent vollständig automatisierbar.

Nicht wählen: xbar/SwiftBar-Plugin (Fremd-App als Voraussetzung), Electron (absurd für 40 Zeichen
Text), Python + rumps (Runtime-Ballast, Signierung umständlich).

Abhängigkeiten: **keine.** `Foundation`, `SwiftUI`, `Security`, `AppKit` reichen. Kein Alamofire,
kein KeychainAccess.

---

## 5. Projektstruktur

```
ClaudeMeter/
├─ Package.swift                 # swift-tools-version:5.9, platforms: [.macOS(.v13)]
├─ Sources/ClaudeMeter/
│  ├─ ClaudeMeterApp.swift       # @main, MenuBarExtra
│  ├─ TokenProvider.swift        # Modul A
│  ├─ UsageClient.swift          # Modul B
│  ├─ UsageStore.swift           # Modul C (ObservableObject)
│  ├─ Models.swift               # UsageSnapshot, LimitWindow, FetchError
│  └─ Views/
│     ├─ MenuBarLabel.swift
│     └─ UsagePanel.swift
├─ Resources/Info.plist
├─ scripts/bundle.sh             # Binary → .app
├─ docs/DATA-SOURCE.md           # Ergebnis aus Schritt 0
└─ README.md
```

---

## 6. Modul A — `TokenProvider`

Auflösungsreihenfolge, erste erfolgreiche Quelle gewinnt:

1. `CLAUDEMETER_TOKEN` (Umgebungsvariable, für Tests)
2. Eigener Schlüsselbund-Eintrag `de.sagorski.claudemeter.token` (falls `setup-token` genutzt wird)
3. Claude-Code-Schlüsselbund: `SecItemCopyMatching` mit `kSecClassGenericPassword`.
   **Achtung:** Der Dienstname kann eine Installations-GUID als Suffix haben
   (`Claude Code-credentials-6248605b`). Also **alle** generischen Passwörter listen und den
   ersten Eintrag nehmen, dessen `kSecAttrService` mit `Claude Code-credentials` beginnt —
   nicht auf exakte Gleichheit prüfen.
4. Datei: `${CLAUDE_CONFIG_DIR:-~/.claude}/.credentials.json`

Anforderungen:

- Token bei **jedem** Poll neu einlesen, nie im Speicher cachen. Claude Code erneuert es
  regelmäßig; ein gecachtes Token führt nach ~1 h zu dauerhaften 401ern.
- `expiresAt` prüfen. Ist es abgelaufen: **keinen Refresh durchführen**, sondern Zustand
  `.tokenExpired` melden. Das Panel zeigt dann „Token abgelaufen — Claude Code einmal starten".
- Token niemals loggen, nie in Crash-Reports, nie in `UserDefaults`.

**Erwarteter Fallstrick:** Der Zugriff auf den Schlüsselbund-Eintrag einer fremden App löst beim
ersten Mal einen Systemdialog aus („ClaudeMeter möchte auf … zugreifen"). Das ist korrekt und
erwartet — im README dokumentieren, dass „Immer erlauben" gewählt werden muss. Jeder Rebuild
ändert die Code-Signatur und löst den Dialog erneut aus (siehe Abschnitt 10).

---

## 7. Modul B — `UsageClient`

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <token>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-code/<version>
Content-Type: application/json
```

- Timeout: 10 s. `URLSession` mit `ephemeral`-Konfiguration, `waitsForConnectivity = false`.
- Version für den User-Agent: einmalig beim Start via `claude --version` ermitteln und cachen;
  schlägt das fehl, hart kodierten Fallback nutzen und das in `DATA-SOURCE.md` vermerken.
- Antwort in ein **normalisiertes** Modell mappen:

```swift
struct LimitWindow {          // ein Balken in der UI
    let id: String            // "session", "weekly_all", "weekly_sonnet", …
    let label: String         // "5 Std.", "Woche", "Woche (Sonnet)"
    let percent: Double       // 0…100
    let resetsAt: Date?
}
struct UsageSnapshot {
    let windows: [LimitWindow]
    let fetchedAt: Date
}
```

Der Parser liest zuerst `limits[]` (Variante B); ist es leer oder nicht vorhanden, fällt er auf
die flachen Keys zurück (Variante A). Unbekannte `kind`-Werte werden **durchgereicht**, nicht
verworfen — so überlebt die App neue Limit-Typen ohne Update.

Fehlerbehandlung:

| HTTP | Verhalten |
|---|---|
| 200 | Snapshot ersetzen, Backoff zurücksetzen |
| 401 | `.unauthorized` — Token neu auflösen, genau **einen** Retry, dann Fehlerzustand |
| 429 | `.rateLimited` — Backoff: 5 → 10 → 20 → 30 min (Deckel). Kein `Retry-After` erwartet. |
| 5xx / Netz | `.transient` — nächster regulärer Tick, kein Sonderweg |

Bei jedem Fehler: letzten erfolgreichen Snapshot behalten und dessen Alter anzeigen.

---

## 8. Modul C — `UsageStore`

`@MainActor final class UsageStore: ObservableObject` mit `@Published var state: State`
(`.loading`, `.ready(UsageSnapshot)`, `.stale(UsageSnapshot, FetchError)`, `.failed(FetchError)`).

Refresh-Auslöser:

- **Timer:** 300 s, `Timer.scheduledTimer` auf dem Main-RunLoop, `tolerance = 30` (spart Energie,
  macOS darf Wakeups bündeln).
- **Panel geöffnet:** sofortiger Refresh, aber nur wenn letzter Fetch > 60 s her ist
  (Klick-Spam darf kein 429 provozieren).
- **Aufwachen:** `NSWorkspace.shared.notificationCenter` auf `didWakeNotification` — nach
  längerem Schlaf sind die Werte garantiert veraltet.
- **Kein Fetch**, wenn `NSWorkspace.shared.notificationCenter` zuvor `willSleepNotification`
  gemeldet hat und noch kein Wake kam.

Ein einziger In-Flight-Request gleichzeitig; parallele Auslöser werden verworfen, nicht gequeued.

---

## 9. Modul D — UI

### 9.1 Menüleisten-Label — hier entscheidet sich „so klein wie möglich"

```swift
MenuBarExtra { UsagePanel() } label: { MenuBarLabel() }
    .menuBarExtraStyle(.window)
```

Regeln:

- Format: `35·14` — Session-Prozent, Mittelpunkt-Trenner, Wochen-Prozent. Kein `%`, keine
  Emoji (Emoji sind breit und wirken in der Menüleiste unruhig).
- `.monospacedDigit()` ist **Pflicht**, sonst wackelt die Breite bei jedem Wert.
- Prozent auf ganze Zahlen runden, dreistellig nur bei 100.
- Führendes SF Symbol nur im Warnfall: ab 80 % `exclamationmark.triangle.fill`, bei
  Fehler/Veraltet `exclamationmark.circle`. Im Normalbetrieb **kein** Icon.
- **Farbe in der Menüleiste vermeiden.** Menüleisten-Bilder werden als Template gerendert und
  automatisch getönt; erzwungene Farben brechen bei hellem/dunklem Modus und bei getönten
  Hintergründen. Farbcodierung gehört ins Panel.
- Existiert ein drittes Fenster (Sonnet-Wochenlimit auf Max), erscheint es **nicht** im Label —
  nur im Panel. Label bleibt zweistellig-zweistellig.

### 9.2 Panel

Breite 240 pt, keine Scrollbereiche. Pro Fenster eine Zeile:

```
5 Std.     ████████░░░░░░░  35 %   ↻ 22:00  (in 2 h 14 m)
Woche      ███░░░░░░░░░░░░  14 %   ↻ Do 20:00  (in 3 T 6 h)
```

- Balken: `Capsule()` im `ZStack`, 6 pt hoch. Farbe: `.green` < 50 %, `.orange` 50–79 %,
  `.red` ≥ 80 %.
- Reset: **Uhrzeit in lokaler Zeitzone** (`resets_at` kommt in UTC — konvertieren!) plus
  Restlaufzeit. Bei > 24 h Tage mitführen.
- Fußzeile: „Aktualisiert vor X min" + Fehlermeldung im Klartext, falls vorhanden.
- Zwei Buttons: „Jetzt aktualisieren" und „Beenden" (⌘Q). Mehr nicht.

---

## 10. Bundling zur `.app`

`scripts/bundle.sh` erzeugt:

```
ClaudeMeter.app/Contents/
├─ Info.plist
├─ MacOS/ClaudeMeter        # aus .build/release/
└─ Resources/AppIcon.icns   # optional
```

`Info.plist` — Pflichtschlüssel:

| Key | Wert |
|---|---|
| `LSUIElement` | `true` ← ohne das erscheint ein Dock-Icon |
| `CFBundleIdentifier` | `de.sagorski.claudemeter` |
| `CFBundleExecutable` | `ClaudeMeter` |
| `CFBundlePackageType` | `APPL` |
| `LSMinimumSystemVersion` | `13.0` |
| `CFBundleShortVersionString` | `1.0.0` |

Signierung:

```bash
codesign --force --options runtime --sign - "ClaudeMeter.app"
codesign -dv --verbose=2 "ClaudeMeter.app"
```

**Fallstrick:** Ad-hoc-Signatur (`-`) ändert sich mit jedem Build → der Schlüsselbund-Dialog
erscheint nach jedem Rebuild erneut. Für den Dauerbetrieb ein **selbstsigniertes Zertifikat**
im Schlüsselbund anlegen (Schlüsselbundverwaltung → Zertifikatsassistent, Typ „Codesignatur")
und damit signieren — dann ist die Identität stabil und der Dialog erscheint genau einmal.
Diesen Schritt im README als manuelle Einmalaktion dokumentieren.

Als zusätzlichen Sicherheitsgurt vorschlagen (nicht ohne Rückfrage aktivieren): App Sandbox ist
hier **nicht** praktikabel, da der Zugriff auf den fremden Schlüsselbund-Eintrag und auf
`~/.claude` benötigt wird.

---

## 11. Autostart

`SMAppService.mainApp.register()` (macOS 13+), ausgelöst über einen Umschalter im Panel.
Kein LaunchAgent-Plist von Hand schreiben. Voraussetzung: App liegt in `/Applications`.
Registrierungsstatus im Panel spiegeln (`SMAppService.mainApp.status`).

---

## 12. Verifikation vor Abgabe

Diese Prüfungen ausführen und die Ergebnisse berichten:

1. `swift build -c release` ohne Warnungen.
2. `scripts/bundle.sh` erzeugt eine `.app`, die per Doppelklick startet — kein Dock-Icon,
   kein Fenster.
3. Label-Stabilität: Werte künstlich auf `0·0`, `9·9`, `100·100` setzen (Debug-Flag) und prüfen,
   dass die Menüleisten-Position der Nachbarelemente nicht springt.
4. Fehlerpfade simulieren: Token unbrauchbar machen (falsches Env-Token) → Panel zeigt 401-Text,
   Label zeigt Warnsymbol, letzter Wert bleibt sichtbar.
5. 429-Pfad: `UsageClient` mit erzwungenem 429 testen → Backoff-Kette 5/10/20/30 min im Log.
6. Zeitzonen: `resets_at` mit UTC-Wert füttern, prüfen dass die Anzeige die lokale Uhrzeit zeigt.
7. Schlaf/Wachen: Mac in den Ruhezustand, aufwecken → sofortiger Refresh im Log.
8. Netzwerkverkehr über 30 min mitschneiden: **genau 6 Requests**, nicht mehr.

---

## 13. Bekannte Fallstricke — Kurzliste

- `resets_at` ist UTC. Ohne Konvertierung zeigt die App im Sommer 2 h daneben.
- `seven_day_opus` / `seven_day_sonnet` können `null` sein → nicht als 0 % rendern, sondern
  die Zeile weglassen.
- `utilization` kann 0 sein, wenn gar kein Fenster aktiv ist — das ist kein Fehler.
- Auf Pro-Konten existiert nur ein Wochenlimit, auf Max zwei. Layout muss 2–4 Zeilen tragen.
- API-Konten (kein Abo) liefern keine Rate-Limit-Daten → sauberer Hinweistext statt Absturz.
- Menüleisten-Platz ist auf Notch-Macs knapp; das Label darf deshalb nie länger als ~7 Zeichen
  werden, auch nicht bei dreistelligen Werten.

---

## 14. Ausbaustufe 2 (erst nach Abnahme von Stufe 1)

- Benachrichtigung bei Überschreiten von 80 % / 95 % (`UNUserNotificationCenter`), einmal pro
  Fenster, nicht bei jedem Tick.
- Kleine Verlaufskurve der letzten 24 h im Panel (SwiftUI `Chart`, Daten in einer lokalen
  JSON-Datei unter `~/Library/Application Support/ClaudeMeter/`).
- Umschaltbares Label-Format: nur Session / nur Woche / beides.

---

## 15. Reihenfolge der Umsetzung

```
Schritt 0 (Datenquelle verifizieren)  →  ANHALTEN und Ergebnis berichten
   ↓
Modul A + B + Unit-Tests gegen die gespeicherte Beispielantwort
   ↓
Modul C
   ↓
Modul D (Label zuerst, Panel danach)
   ↓
Bundling + Signierung
   ↓
Verifikation nach Abschnitt 12
```

Nach Schritt 0 **anhalten** und die tatsächliche Antwortstruktur zur Bestätigung vorlegen,
bevor der Parser gebaut wird. Alles danach kann durchlaufen.
