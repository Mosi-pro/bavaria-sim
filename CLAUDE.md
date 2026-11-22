# LEITSTELLE 112 / Leitstelle Bavaria – Hinweise für die Weiterentwicklung

Leitstellen-Simulation (Godot 4.7, GDScript) mit fiktiver Stadt Bavaria. Sprache im Projekt
und in der Kommunikation mit dem Projektinhaber: **Deutsch**.

## Zweige und Veröffentlichung (wichtig!)

- **Hauptzweig = Standard-Branch des Repositorys** (derzeit `claude/dazzling-faraday-bazqvw`).
  Jeder Push dorthin baut und veröffentlicht die **öffentliche Version** (GitHub-Release
  `v<Version>` = „latest“, dazu `v<Version>-beta` und das Server-Paket).
- **Test-/Entwicklungsarbeit immer in einem eigenen Zweig.** Pushes aus anderen Zweigen
  bauen und testen nur und veröffentlichen eine **Testversion** als Vorabversion
  `test-<zweig>` (Beta-Variante mit Zugangscode, eigener Installationsordner). Die
  öffentliche Version und der Server-Installer (`releases/latest`) bleiben unberührt.
- Testentwicklungen kommen erst nach ausdrücklicher Freigabe durch den Projektinhaber in den
  Hauptzweig (Pull Request).

## Versionen

- Jede Auslieferung bekommt eine **neue Versionsnummer** (`tools/set_version.sh X.Y.Z`) und
  einen Eintrag in `CHANGELOG.md` (Neue Funktionen / Fehlerbehebungen).
- Testzweige: eigene Versionsnummer mit Zusatz ist nicht nötig; die Testversion trägt den
  Zweignamen im Dateinamen.

## Tests

- `godot --headless --path . res://tests/run_tests.tscn` (Kerntests, alle müssen bestehen)
- `tools/test_multiplayer.sh godot` und `tools/test_relay.sh godot`
- GitHub Actions: Tests, Windows-Export + Selbsttest (normal und Beta), Linux-Server-Paket.

## Wichtige Orte

- Daten: `data/*.json` (Fahrzeuge, Wachen via `tools/gen_stations.py`, Einsätze, Stichwörter,
  Anrufertexte, Spielmodi/Rollen/Gebiete). Einsatzliste: `python3 tools/gen_einsatzliste.py`.
- Mehrspieler: `src/multiplayer/` (Host-autoritativ, Vermittlungsdienst `relay_server.gd`
  auf dem Projektserver, Adresse in `data/network.json`), Gebiete: `src/simulation/areas.gd`.
- Beta-Zugang: `src/core/beta.gd`, Codes erzeugen/sperren mit `tools/beta_codes.py`
  (nur Prüfwerte ins Repository, Klartext-Codes nie einchecken).
- Server-Anleitung: `docs/SERVER_INSTALLATION.md`, Installer `tools/wyse/server.sh`.

## Regeln

- Keine realen Einsatz-/Personalpläne, keine echten Firmen- oder Organisationslogos,
  eigene fiktive Namen (Wachen, Funkrufnamen, Kliniken, Firmen).
- Niemals Passwörter oder Zugangsdaten im Chat erfragen oder entgegennehmen.
- Fertige EXE-Dateien dem Projektinhaber direkt im Chat schicken (Setup normal + Beta).
