<div align="center">

<img src="assets/icon.png" alt="ClaudeMeter App-Icon — konzentrische Ringe für Claude-Session- und Wochenverbrauch" width="128">

# ClaudeMeter — Claude-Verbrauch in der macOS-Menüleiste

**Eine winzige, native macOS-Menüleisten-App, die zeigt, wie viel deines Claude-Abos verbraucht ist — das rollierende 5-Stunden-Fenster, das Wochenlimit und wann genau beides zurückgesetzt wird.**

[![Plattform](https://img.shields.io/badge/Plattform-macOS%2013%2B-000000?logo=apple&logoColor=white)](#voraussetzungen)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](#selbst-bauen)
[![Abhängigkeiten](https://img.shields.io/badge/Abh%C3%A4ngigkeiten-keine-success)](#warum-keine-abhängigkeiten)
[![Tests](https://img.shields.io/badge/Tests-65%20gr%C3%BCn-success)](#tests)
[![Lizenz](https://img.shields.io/badge/Lizenz-MIT-blue)](LICENSE)

🇬🇧 **[English version of this page →](README.md)**

</div>

---

## Worum geht es?

Wer **Claude Code** oder ein **Claude-Pro-/Max-Abo** intensiv nutzt, ist vermutlich schon mitten in
einer Aufgabe in ein Limit gelaufen. Claude erzwingt zwei Limits gleichzeitig — ein **rollierendes
5-Stunden-Fenster** und ein **Wochenkontingent** (auf Max-Plänen zusätzlich ein modellbezogenes
Wochenlimit) — und keines davon ist während der Arbeit sichtbar.

ClaudeMeter bringt alle in die Menüleiste. Aktualisierung alle 5 Minuten, rund 1 MB groß,
**keine Abhängigkeiten**, und es wird **nie** in die Anmeldedaten von Claude Code geschrieben.

![Alle sechs ClaudeMeter-Designs — Doppelbalken, Nur die Zahl, Doppelring, Reset-Countdown, Segmente und Zahlenpaar — jeweils als Menüleisten-Element mit Klick-Panel](assets/styles-overview.png)

---

## Funktionen

| | |
|---|---|
| 📊 **Alle Limits auf einen Blick** | Rollierendes 5-Std-Fenster, Wochenkontingent und modellbezogene Wochenlimits |
| ⏱ **Reset-Zeiten statt Schätzungen** | Jedes Fenster zeigt lokale Uhrzeit **und** Restlaufzeit (`16:45 · in 2 Std 13 Min`) |
| 🎨 **Sechs umschaltbare Designs** | Vom 15 × 15 pt Doppelring bis zum Prozent-Paar — in den Einstellungen, ohne Neubau |
| 🪶 **Wirklich klein** | ~1 MB Binary, kein Node, kein Python, kein Electron, keine Fremdpakete |
| 🌓 **Natives Menüleisten-Verhalten** | Template-Rendering folgt Hell-/Dunkelmodus und getönten Menüleisten automatisch |
| 🔒 **Nur lesender Zugriff** | Erneuert, rotiert oder überschreibt nie deine Claude-Code-Anmeldung |
| 🔋 **Schlaf-bewusst** | Keinerlei Netzwerkverkehr im Ruhezustand, sofortiger Refresh beim Aufwachen |
| ⚠️ **Fällt laut aus, nicht still** | Bei Fehler bleibt der letzte Wert sichtbar, aber als veraltet markiert |
| 🚫 **Kein Dock-Icon** | `LSUIElement` — nur Menüleiste, kein Fenster, kein App-Umschalter |
| 🩺 **Eingebauter Doctor** | `swift run claudemeter-doctor` prüft die ganze Kette und meldet jede Stufe |

---

## Sechs Designs — jederzeit umschaltbar

Der Wunsch, der diese App geprägt hat: *alle* Designvorschläge waren gut — also sind **alle**
umgesetzt. Auswahl in den Einstellungen; sie ändert Menüleisten-Glyph **und** Klick-Panel.

| | Design | Platzbedarf | Was dauerhaft in der Menüleiste steht |
|---|---|---|---|
| **1a** | **Doppelbalken** | ≈ 22 × 9 pt | Zwei feine Balken — oben 5 Std., unten Woche. Keine Zahl. |
| **1b** | **Nur die Zahl** | ≈ 44 × 13 pt | Punkt plus Session-Prozentwert. Die Woche steht nur im Panel. |
| **1c** | **Doppelring** — *Standard* | ≈ 15 × 15 pt | Konzentrische Ringe, so groß wie ein normales Menüleisten-Icon. |
| **1d** | **Reset-Countdown** | ≈ 38 × 15 pt | Zeit bis zum Reset, Füllstand liegt hinter der Zahl. |
| **1e** | **Segmente** | ≈ 23 × 13 pt | Fünf Segmente für die Session, eine Linie für die Woche. |
| **RB** | **Zahlenpaar** | ≈ 46 × 13 pt | Beide Prozentwerte als Text, `21·73`. |

<details>
<summary><b>Jedes Design einzeln ansehen</b> (Menüleiste + Panel)</summary>

### 1a · Doppelbalken
![ClaudeMeter Doppelbalken in der Menüleiste](assets/menubar-doppelbalken.png)
![ClaudeMeter Doppelbalken-Panel mit Claude-Verbrauchsbalken und Reset-Zeiten](assets/panel-doppelbalken.png)

### 1b · Nur die Zahl
![ClaudeMeter Nur die Zahl in der Menüleiste](assets/menubar-zahl.png)
![ClaudeMeter Panel mit großen Prozentwerten](assets/panel-zahl.png)

### 1c · Doppelring *(Standard)*
![ClaudeMeter Doppelring in der Menüleiste](assets/menubar-doppelring.png)
![ClaudeMeter Doppelring-Panel mit konzentrischen Ringen und Legende](assets/panel-doppelring.png)

### 1d · Reset-Countdown
![ClaudeMeter Reset-Countdown in der Menüleiste](assets/menubar-countdown.png)
![ClaudeMeter Countdown-Panel mit breitem Session-Balken, Start- und Reset-Zeit](assets/panel-countdown.png)

### 1e · Segmente
![ClaudeMeter Segmente in der Menüleiste](assets/menubar-segmente.png)
![ClaudeMeter Segmente-Panel mit Segmentanzeigen](assets/panel-segmente.png)

### RB · Zahlenpaar
![ClaudeMeter Zahlenpaar in der Menüleiste](assets/menubar-zahlenpaar.png)
![ClaudeMeter Zahlenpaar-Panel mit beschrifteten Balken](assets/panel-zahlenpaar.png)

</details>

> Alle Screenshots werden mit `swift run AssetGen` direkt aus den echten SwiftUI-Views gerendert —
> die Dokumentation kann also nicht von der App abweichen.

---

## Installation

### Voraussetzungen

- macOS **13 Ventura** oder neuer (Apple Silicon oder Intel)
- **Claude Code** installiert und mit Pro- oder Max-Abo angemeldet
- Xcode Command Line Tools (nur zum Bauen — `xcode-select --install`)

### Bauen und installieren

```bash
git clone https://github.com/koljasagorski/Claude-Quota.git
cd Claude-Quota
./scripts/bundle.sh
cp -R build/ClaudeMeter.app /Applications/
open /Applications/ClaudeMeter.app
```

Mehr ist nicht nötig. Kein Paketmanager, keine Runtime, keine Konfigurationsdatei.

### Erster Start: der Schlüsselbund-Dialog

ClaudeMeter liest das OAuth-Token von Claude Code aus dem Schlüsselbund, deshalb fragt macOS einmal:

> *„ClaudeMeter möchte auf den Schlüssel ‚Claude Code-credentials' im Schlüsselbund zugreifen."*

**„Immer erlauben"** wählen. Das ist erwartet und dokumentiert — die App liest ausschließlich.

<details>
<summary><b>Dialog nach jedem Neubau vermeiden</b> (empfohlen für den Dauerbetrieb)</summary>

Eine Ad-hoc-Signatur (`codesign --sign -`) ändert sich mit jedem Build, macOS hält jeden Build für
eine andere App und fragt erneut. Einmalig ein stabiles selbstsigniertes Zertifikat anlegen:

1. **Schlüsselbundverwaltung** öffnen → Menü **Schlüsselbundverwaltung › Zertifikatsassistent › Zertifikat erstellen…**
2. Name: `ClaudeMeter Dev` · Identitätstyp: **Selbstsigniertes Root-Zertifikat** · Zertifikatstyp: **Codesignatur**
3. Danach damit bauen:

```bash
SIGN_IDENTITY="ClaudeMeter Dev" ./scripts/bundle.sh
```

Der Dialog erscheint dann genau einmal.

</details>

### Autostart

Schalter **„Beim Anmelden starten"** in den Einstellungen. Nutzt `SMAppService` (macOS 13+) — kein
handgeschriebenes LaunchAgent-Plist. Die App muss dafür in `/Programme` liegen.

---

## Einstellungen

Menüleisten-Element anklicken, dann das ⚙️-Symbol.

| Einstellung | Standard | Wirkung |
|---|---|---|
| **Darstellung** | Doppelring | Wechselt zwischen allen sechs Designs, mit Live-Vorschau |
| **Farbe in der Menüleiste** | aus | Aus: Template-Bild, folgt Hell/Dunkel und getönten Menüleisten. An: Akzentfarben des Designs. |
| **Alle Limit-Fenster zeigen** | an | Blendet modellbezogene Wochenlimits ein (Max-Pläne) |
| **Beim Anmelden starten** | aus | Registriert die App über `SMAppService` |

---

## Wie es funktioniert

```
Schlüsselbund / Env / Datei ──▶ TokenProvider ──▶ UsageClient ──▶ UsageParser ──▶ UsageStore ──▶ SwiftUI
      (nur lesend)                            GET /api/oauth/usage   normalisieren   Zustand + Polling
```

ClaudeMeter ruft denselben undokumentierten Endpoint auf, den Claude Code selbst nutzt:

```http
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <Token aus dem Schlüsselbund>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-code/<erkannte Version>
```

Alle Ergebnisse der Verifikation gegen ein echtes Konto — exakte Antwortstruktur, die Frage nach der
Prozentskala und zwei Schlüsselbund-Fallen — stehen in
**[`docs/DATA-SOURCE.md`](docs/DATA-SOURCE.md)**, mit echter (geheimnisfreier) Antwort in
[`docs/usage-schema-sample.json`](docs/usage-schema-sample.json).

### Polling und Rate Limits

| Auslöser | Verhalten |
|---|---|
| Timer | Alle **5 Minuten**, 30 s Toleranz, damit macOS Wakeups bündeln kann |
| Panel geöffnet | Sofortiger Refresh, höchstens einmal pro 60 s (Klick-Spam darf kein 429 auslösen) |
| Aufwachen | Sofortiger Refresh — nach Schlaf sind Werte garantiert veraltet |
| Ruhezustand | **Keine Anfragen** |
| HTTP 429 | Backoff **5 → 10 → 20 → 30 Minuten** |
| HTTP 401 | Token neu auflösen, genau **ein** Retry, dann sichtbarer Fehler |

Es ist immer nur eine Anfrage unterwegs; parallele Auslöser werden verworfen, nicht gequeued.
In 30 Minuten Normalbetrieb sind das **6 Anfragen**.

### Warum keine Abhängigkeiten?

`Foundation`, `SwiftUI`, `Security`, `ServiceManagement` und `AppKit` reichen vollständig. Kein
Alamofire, kein KeychainAccess, kein Sparkle. Ergebnis: ~1 MB Binary, headless baubar mit
`swift build` — ohne Xcode-Projektdatei im Repository.

### Deine Anmeldedaten bleiben unangetastet

- ClaudeMeter schreibt **nie** in den Schlüsselbund, erneuert **nie** ein Token und rotiert **nie**
  ein Refresh-Token. Ein Refresh würde die Anmeldung von Claude Code selbst zerstören.
- Ein abgelaufenes Token führt zu einer klaren Meldung („Claude Code einmal starten"), nicht zu
  einem Refresh-Versuch.
- Das Token wird bei jedem Poll neu gelesen und nie gecacht, geloggt oder in `UserDefaults` abgelegt.
- Keine Telemetrie, keine Analytics, kein Netzwerkverkehr außer der einen Verbrauchsabfrage.

---

## Fehlersuche

```bash
swift run claudemeter-doctor
```

Läuft exakt den Pfad der App und meldet jede Stufe einzeln. Das Token wird nie ausgegeben.

| Symptom | Ursache | Lösung |
|---|---|---|
| *„Keine Anmeldung gefunden"* | Kein Claude-Code-Login auf diesem Mac | Einmal `claude` starten und anmelden |
| *„Token abgelaufen"* | Access-Token über `expiresAt` hinaus | Claude Code einmal starten, es erneuert selbst |
| *„Nicht autorisiert (401)"* | Token abgelehnt | Bei Claude Code neu anmelden |
| *„Zu viele Anfragen (429)"* | Rate Limit | Nichts zu tun — der Backoff regelt das |
| *„Dieses Konto hat keine Abo-Limits"* | API-/Console-Konto statt Abo | Erwartet; es gibt keine Verbrauchsdaten |
| Menüleisten-Element fehlt | Menüleiste voll (Notch-Macs) | Anderes Element ausblenden oder Doppelring (15 × 15 pt) wählen |

---

## Selbst bauen

```bash
swift build -c release        # warnungsfrei
swift test                    # 65 Tests
./scripts/bundle.sh           # → build/ClaudeMeter.app, signiert
swift run claudemeter-doctor  # Live-Datenpfad prüfen
swift run AssetGen            # Screenshots + AppIcon.icns neu erzeugen
```

### Tests

65 Tests, ohne Netzwerk. Sie decken das ab, was während der Entwicklung tatsächlich kaputt war:

- Beide Antwortschemata und die Mischform, die die API real liefert
- Codename-Platzhalter (`nimbus_quill`, `tangelo`, …) werden nie zu falschen 0-%-Zeilen
- `0.8` bedeutet 0,8 %, niemals 80 %
- UTC-`resets_at` wird als lokale Uhrzeit dargestellt
- MCP-Schlüsselbund-Einträge werden nie mit der Abo-Anmeldung verwechselt
- Das Menüleisten-Label ist für jeden Wert von 0 bis 100 exakt gleich breit
- Fehlerhafte, feindselige und abgeschnittene Antworten stürzen nichts ab

---

## Bekannte Einschränkungen

Bitte vor dem produktiven Einsatz lesen:

- **Die Datenquelle ist inoffiziell.** `/api/oauth/usage` ist undokumentiert, wird intern von Claude
  Code genutzt, und Anthropic kann sie jederzeit ändern oder entfernen.
- **Der `anthropic-beta`-Header trägt ein Datum.** Wird `oauth-2025-04-20` zurückgezogen, schlagen
  Anfragen fehl. Die App zeigt das als sichtbaren Fehler, statt still alte Zahlen anzuzeigen.
- **Der Endpoint ist ratenbegrenzt.** Nie schneller als 60 s abfragen. Standard sind 5 Minuten.
- **Die Prozentwerte kommen unverändert von der API.** ClaudeMeter rechnet nichts selbst und kann
  nicht genauer sein als der Endpoint.
- **Die 7-Block-Wochenansicht im Segmente-Design ist keine Tageshistorie.** Sie teilt den einen
  Wochenwert in Blöcke. Echte Tageswerte bräuchten lokale Speicherung (geplant).
- **App Sandbox ist nicht aktiviert**, weil der Zugriff auf den fremden Schlüsselbund-Eintrag und
  auf `~/.claude` sonst verweigert würde.

### Ausblick

- Benachrichtigung bei 80 % / 95 % je Fenster, einmal pro Fenster statt bei jedem Tick
- Verlaufskurve der letzten 24 Stunden im Panel
- Optional englischsprachige Oberfläche

---

## Grundlagendokumente

- [`docs/runbook.md`](docs/runbook.md) — das ursprüngliche Runbook, nach dem diese App gebaut wurde
- [`docs/design-brief.md`](docs/design-brief.md) — Verweis auf das Claude-Design-Projekt mit den sechs Designs
- [`docs/DATA-SOURCE.md`](docs/DATA-SOURCE.md) — verifizierte Erkenntnisse zum Verbrauchs-Endpoint
- [`CHANGELOG.md`](CHANGELOG.md) — Versionsverlauf

---

## Mitwirken

Issues und Pull Requests sind willkommen. Wenn ClaudeMeter eine Antwortform schlecht verarbeitet,
bitte die Ausgabe von `swift run claudemeter-doctor` anhängen (sie enthält kein Token) und, wenn
möglich, einen geschwärzten Antwort-Body.

## Lizenz

[MIT](LICENSE) © Kolja Sagorski

---

<div align="center">

**Gebaut für alle, die das Limit lieber kommen sehen, als hineinzulaufen.**

</div>
