# Datenquelle — Ergebnis aus Schritt 0

Verifiziert am **19. August 2026** gegen ein echtes Max-Konto
(`subscriptionType: max`, `rateLimitTier: default_claude_max_5x`),
Claude Code **2.1.235**, macOS 26.6.2 (Apple Silicon).

Rohantwort: [`usage-schema-sample.json`](usage-schema-sample.json) (enthält keine Geheimnisse).

---

## Endpoint

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-code/2.1.235
Content-Type: application/json
```

→ **HTTP 200**

Der `User-Agent` ist nicht optional: ohne ihn landet die Anfrage in einem deutlich schärferen
Rate-Limit-Bucket. ClaudeMeter ermittelt die Version beim Start über `claude --version`
(gesucht in `~/.claude/local/claude`, Homebrew- und `/usr/local`-Pfaden) und fällt sonst auf
`2.1.235` zurück.

---

## Antwortstruktur: beide Varianten gleichzeitig

Das Runbook nahm an, das Schema sei **entweder** flach (Variante A) **oder** strukturiert
(Variante B). Tatsächlich liefert die API heute **beides in derselben Antwort**:

```jsonc
{
  "five_hour": { "utilization": 21.0, "resets_at": "2026-08-19T11:20:00.831601+00:00", … },
  "seven_day": { "utilization": 73.0, "resets_at": "2026-08-21T18:00:00.831616+00:00", … },
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "limits": [
    { "kind": "session",       "group": "session", "percent": 21, "resets_at": "…", "scope": null,  "is_active": false },
    { "kind": "weekly_all",    "group": "weekly",  "percent": 73, "resets_at": "…", "scope": null,  "is_active": true  },
    { "kind": "weekly_scoped", "group": "weekly",  "percent":  7, "resets_at": "…",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": false }
  ],
  "extra_usage": { … },
  "spend": { … }
}
```

**Implementierte Priorität:** `limits[]` gewinnt, wenn vorhanden und nicht leer; sonst die flachen
Keys; sonst `FetchError.noSubscription`.

Warum `limits[]` Vorrang hat: Der Server hat dieses Array bereits auf die Fenster gefiltert, die
für dieses Konto gelten. Die flache Ebene enthält dagegen auch unveröffentlichte Platzhalter
(siehe unten).

---

## Geklärt: `utilization` ist 0–100, nicht 0–1

Die offene Frage aus Runbook 3.3 ist entschieden — durch Quervergleich innerhalb derselben Antwort:

| Feld | Wert |
|---|---|
| `five_hour.utilization` | `21.0` |
| `limits[kind=session].percent` | `21` |
| `seven_day.utilization` | `73.0` |
| `limits[kind=weekly_all].percent` | `73` |

Beide Darstellungen tragen dieselbe Zahl. **`0.8` bedeutet also 0,8 %, nicht 80 %.**
ClaudeMeter skaliert kleine Werte deshalb **nie** hoch; ein Regressionstest
(`testSmallValuesAreNotRescaledToPercent`) hält das fest.

---

## Codename-Platzhalter — müssen gefiltert werden

Die Antwort enthält Keys für unveröffentlichte Funktionen:

```
seven_day_oauth_apps, seven_day_cowork, seven_day_omelette, omelette_promotional,
tangelo, iguana_necktie, nimbus_quill, cinder_cove, amber_ladder
```

Die meisten sind `null`. **`nimbus_quill` ist es nicht** — es liefert
`{ "utilization": 0.0, "resets_at": null }`. Würde man alle flachen Keys stumpf durchreichen,
erschiene eine sinnlose Zeile „Nimbus Quill 0 %" im Panel.

Im `limits[]`-Array taucht `nimbus_quill` **nicht** auf — ein weiteres Argument für dessen Vorrang.

**Regel im Fallback-Pfad:** Ein unbekannter flacher Key gilt nur dann als Limit-Fenster, wenn er
ein `resets_at` trägt. Ohne Reset-Zeitpunkt ist es kein Fenster. Bekannte Limit-Typen und die
Nicht-Limits `extra_usage` / `spend` sind fest zugeordnet.

---

## `scope` benennt das Modell — nicht zwingend Sonnet

Das Runbook sprach vom „Sonnet-Wochenlimit". Real ist das modellbezogene Fenster generisch:

```json
"scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }
```

`id` ist `null`; **`display_name` ist die einzige verlässliche Quelle**. ClaudeMeter bildet daraus
das Label `Woche · <display_name>` und verdrahtet keinen Modellnamen fest.

---

## Zeitstempel

`resets_at` ist **UTC** mit sechs Nachkommastellen: `2026-08-19T11:20:00.831601+00:00`.

Der Parser versucht ISO-8601 mit Bruchteilen, dann ohne, dann mit auf drei Stellen gekürztem
Bruchteil. Die Anzeige rechnet immer in die lokale Zeitzone um
(Test: `testUTCIsRenderedInLocalTime` — 12:00 UTC → „14:00" in Europe/Berlin im August).

---

## Token-Quelle

Claude Code legt die Anmeldung auf macOS im **Schlüsselbund** ab, nicht als Datei.
`~/.claude/.credentials.json` existierte auf dem Testsystem **nicht**.

### Fallstrick 1 — die GUID-Geschwister sind MCP-Logins

Auf dem Testsystem existierten **13** Einträge, deren Dienstname mit `Claude Code-credentials`
beginnt:

| Dienstname | Inhalt |
|---|---|
| `Claude Code-credentials` | `claudeAiOauth` — **das ist die gesuchte Anmeldung** |
| `Claude Code-credentials-91efcd97` | `claudeAiOauth`, seit 93 Tagen abgelaufen |
| `Claude Code-credentials-<11 weitere GUIDs>` | `mcpOAuth` — Logins einzelner **MCP-Server** |

Die Runbook-Regel „den ersten Eintrag nehmen, dessen Dienstname mit `Claude Code-credentials`
beginnt" trifft damit mit hoher Wahrscheinlichkeit ein **MCP-Token** und führt zu dauerhaften 401ern.

**Implementierte Regel:** nur Einträge akzeptieren, die tatsächlich ein `claudeAiOauth`-Objekt
enthalten; danach sortieren nach *nicht abgelaufen* → *exakter Dienstname* → *spätestes Ablaufdatum*.

### Fallstrick 2 — `kSecReturnData` + `kSecMatchLimitAll` = `errSecParam`

Eine einzige `SecItemCopyMatching`-Abfrage, die alle Treffer **mit Daten** anfordert, schlägt auf
macOS mit **-50 (`errSecParam`)** fehl. Empirisch bestätigt:

| Abfrage | Status |
|---|---|
| `MatchLimitAll` + `ReturnAttributes` | `0`, 145 Einträge, 13 Treffer |
| `MatchLimitAll` + `ReturnAttributes` + `ReturnData` | **`-50`** |
| `MatchLimitOne` + exakter `Service` + `ReturnData` | `0`, 18 126 Bytes |
| `kSecUseDataProtectionKeychain: true` | `-25300` (leer) |

ClaudeMeter arbeitet deshalb **zweistufig**: Durchgang 1 listet Dienstnamen (nur Attribute),
Durchgang 2 liest jeden Kandidaten einzeln. Der Data-Protection-Schlüsselbund wird explizit
ausgeschlossen — Claude Code schreibt in den dateibasierten.

### Auflösungsreihenfolge

1. `CLAUDEMETER_TOKEN` (Umgebungsvariable, für Tests)
2. Eigener Schlüsselbund-Eintrag `de.sagorski.claudemeter.token`
3. Claude-Code-Schlüsselbund (Regeln oben)
4. `${CLAUDE_CONFIG_DIR:-~/.claude}/.credentials.json`

Das Token wird bei **jedem** Poll neu gelesen und nie im Speicher gehalten — Claude Code erneuert
es etwa stündlich.

### `claude setup-token` (Runbook 3.4)

**Nicht gegengetestet.** Der Befehl startet einen interaktiven Browser-Login und erzeugt ein neues
langlebiges Token; das ist eine Aktion mit Außenwirkung, die ohne ausdrückliche Zustimmung nicht
ausgeführt wurde.

Der Pfad ist trotzdem vorbereitet: wer so ein Token besitzt, legt es unter dem Dienstnamen
`de.sagorski.claudemeter.token` (Quelle 2) oder als `CLAUDEMETER_TOKEN` (Quelle 1) ab; beide haben
Vorrang vor dem Schlüsselbund von Claude Code. Ob das Token gegen `/api/oauth/usage` funktioniert,
ist damit **offen**.

---

## Was die App still brechen kann

| Auslöser | Symptom | Reaktion |
|---|---|---|
| `anthropic-beta`-Header wird zurückgezogen | 4xx | Sichtbarer Fehler, letzter Wert bleibt mit Altersangabe stehen |
| Antwortschema ändert sich erneut | weniger/keine Fenster | Parser reicht unbekannte `kind`-Werte durch; leere Antwort → Klartext-Hinweis |
| Endpoint verschwindet | 404 | `Unerwarteter Status 404` im Panel |
| Rate Limit | 429 | Backoff 5 → 10 → 20 → 30 min |

Bei jedem Fehler bleibt der letzte erfolgreiche Snapshot sichtbar und wird als veraltet markiert —
**nie** werden stillschweigend alte Werte als aktuell ausgegeben.

---

## Selbsttest

```bash
swift run claudemeter-doctor
```

Läuft exakt den Pfad der App (Token → Abfrage → Parser) und meldet jede Stufe einzeln.
Das Token wird nie ausgegeben.
