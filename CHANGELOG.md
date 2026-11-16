# Änderungen – LEITSTELLE 112

## Version 1.2.0 (16.11.2026)

**Neue Funktionen**
- **GW-L mit Rollcontainern:** Der Gerätewagen Logistik hat jetzt einen wechselbaren Rollcontainer: Schlauch / Wasserversorgung, Tragkraftspritze (TS), Hochwasser / Unwetter, Strom & Licht, Atemschutz, Gefahrgut / Ölspur und Gitterbox / Transport. Jeder Container bringt eigene Fähigkeiten mit (z. B. Pumpen, Atemschutz-Nachschub, Löschwasserförderung, Beleuchtung).
  - Auswahl beim Alarmieren in der neuen Spalte »Rollcontainer« (Dropdown). Umladen geht nur auf der Wache und verlängert das Ausrücken um 2 Minuten.
  - Der Alarmierungsvorschlag wählt den passenden Container selbst, wenn eine Fähigkeit fehlt (z. B. Pumpen bei vollgelaufener Tiefgarage).
  - Funkprotokoll und Einsatzakte zeigen, welcher Container geladen ist.
- **Ausleuchtung bei Nacht:** Längere Einsätze von Feuerwehr und THW brauchen bei Dunkelheit Beleuchtung. Das leisten Rüstwagen, THW-GKW oder ein GW-L mit Rollcontainer Strom & Licht.

**Fehlerbehebungen**
- Stichwortfarben nach Fachbereich statt nach Priorität: Feuerwehr (B, THL, ABC) rot, Rettungsdienst (RD) orange, Polizei (POL) blau. Gilt für Einsatzliste, Lagekarte, Einsatzakte und Hilfe. Bisher war z. B. RD 2 rot und B 2 gelb.

## Version 1.1.1 (15.11.2026)

**Fehlerbehebungen**
- Download: Jede geprüfte Version erscheint jetzt automatisch unter GitHub „Releases“. Die Setup-EXE lässt sich dort direkt als EXE herunterladen, ohne ZIP-Datei (solange das Repository privat ist, mit GitHub-Anmeldung). Zusätzlich gibt es eine portable ZIP-Version (ohne Installation), das Paket für den Vermittlungsdienst und Prüfsummen (SHA-256).

## Version 1.1.0 (15.11.2026)

**Neue Funktionen**
- **Rettungshubschrauber:** „Christoph 1“ (Klinikum Süd, nur bei Tageslicht) und „Christoph Bavaria“ (Universitätsklinikum, rund um die Uhr), Airbus H145. Sie fliegen direkt zur Einsatzstelle und bringen einen Notarzt mit. Bei Nebel und Sturm gibt es keinen Flugbetrieb. Der Vorschlag wählt den Hubschrauber, wenn er mindestens 2 Minuten schneller ist als der Notarzt mit dem Auto (vor allem im Umland).
- Versionsnummer im Hauptmenü, im Fenstertitel, im Installer und im Download-Namen; diese Änderungsliste.

**Fehlerbehebungen**
- Notrufgespräche: Eröffnung, Antwort auf „Was ist passiert?“ und Schweregrad passen jetzt zusammen. Vorher nannte der Anrufer bei medizinischen Notfällen auf „Was?“ oft nur den Ort.
- Grammatik bei „Wie viele Betroffene?“ (eine Person / mehrere Personen).
- Weniger Brustschmerz-Notrufe (ca. 3 % statt 8 %), weniger Kindernotfälle (ca. 1 % statt 3 %).
- Einweisung: Der erste Einsatz ist eindeutig ein RD 1 (Knieverletzung ohne Lebensgefahr). Nach Schritt 10 gibt es einen eigenen Schritt „Anfahrt abwarten“ mit Hinweis auf den Zeitraffer, statt scheinbar stehenzubleiben.

## Version 1.0.0 (14.11.2026)

Erstveröffentlichung mit allen bisherigen Ausbaustufen:
- Stadt Bavaria, Lagekarte, Routing, Fahrzeuge, Wachen, Personal
- Notrufabfrage in drei Schritten, Einsatzakte, Disposition, Funk, Einsatzsimulation
- Einweisung, Aufgabenliste, Schwierigkeitsstufen mit Hinweisen
- Stichwörter nach bayerischer Alarmierungsbekanntmachung, 46 Einsatzarten
- Mehrspieler im LAN, per IP und über den Vermittlungsdienst (Einladungscode)
- Speichern/Laden, Einstellungen, Windows-Installer
