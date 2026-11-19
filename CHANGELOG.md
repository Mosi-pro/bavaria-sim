# Änderungen – LEITSTELLE 112

## Version 1.4.1 (19.11.2026)

**Neu**
- **Internet-Mehrspieler ohne Einrichtung:** Das Spiel verbindet sich jetzt automatisch mit dem Vermittlungsdienst des Projekts (`ws://v2202611458938560247.nicesrv.de:24180`). »SPIEL ERSTELLEN« → Einladungscode weitergeben, Mitspieler geben ihn unter »MULTIPLAYER« ein – keine Portfreigabe nötig. Die Adresse lässt sich in den Einstellungen weiterhin ändern.
- Installationsanleitung für den Mietserver (`docs/SERVER_INSTALLATION.md`) und eigenes Absicherungsskript `absichern_vps.sh` (Firewall, automatische Updates, Schutz gegen SSH-Passwort-Raten).

## Version 1.4.0 (17.11.2026)

**Neu**
- **Flughafenfeuerwehr ausgebaut:** jetzt 4 Flugfeldlöschfahrzeuge, ELW 1, TLF 4000 und **2 Treppenfahrzeuge** (Rettungstreppe für Evakuierung und Patientenzugang am Flugzeug).
- **Neue Flughafen-Einsätze** mit eigenen Stichwörtern:
  - Luftfahrzeug in Not – Notlandung (THL FLUGZEUG; Varianten: sichere Landung, Evakuierung über Notrutschen, Triebwerksbrand → B FLUGZEUG)
  - Brand an einem Luftfahrzeug (B FLUGZEUG; Bremsenbrand, Hilfstriebwerk, Brand in der Kabine)
  - Medizinischer Notfall an Bord (RD 2; an einer Außenposition nur über das Treppenfahrzeug erreichbar)
- **Werkfeuerwehr:** zusätzlich Teleskopmastbühne (TMB) und Hochleistungslüfter (HLL). Der Lüfter wird bei großen Hallenbränden gebraucht.
- **Großraum-RTW:** einer jetzt an Feuerwache 6, einer weiterhin am SEG-Standort. Beide können zusätzlich unverletzte Betroffene aufnehmen (Betreuung).

**Fehlerbehebungen**
- **Anrufer legt auf:** Danach sind keine Rückfragen mehr möglich (Fragen-Knöpfe gesperrt, Hinweis im Gesprächsverlauf). Bisher konnte man einem Scherzanrufer nach dem Auflegen weiter Fragen stellen.
- **Kindernotarzt** steht jetzt an Feuerwache 1 (vorher am Universitätsklinikum).

## Version 1.3.1 (16.11.2026)

**Neu**
- **Beta-Tester-Version:** Zusätzlich zur normalen Version wird eine getrennte BETA-Version gebaut (`LEITSTELLE112_BETA_Setup_<Version>.exe`, eigene Vorabversion auf GitHub).
  - Startet nur mit einem persönlichen Zugangscode (Format LB-XXXX-XXXX-XXXX). Im Spiel liegen nur gesalzene SHA-256-Prüfwerte, nicht die Codes selbst.
  - Codes erzeugen und sperren mit `tools/beta_codes.py`; gesperrte Codes gelten ab dem nächsten Beta-Build nicht mehr.
  - Eigener Installationsordner, eigene Spielstände (%APPDATA%\LEITSTELLE112_Beta), eigener Startmenü-Eintrag – beide Versionen können parallel installiert sein.
  - Gekennzeichnet als BETA im Fenstertitel und im Hauptmenü (mit Testernummer).
- Die normale Version ist unverändert und verlangt keinen Code.

## Version 1.3.0 (16.11.2026)

**Neue Funktionen**
- **Feuerwehrkräne:** Zwei Kranwagen »FwK 70« (70-Tonnen-Klasse, Front-Seilwinde) an Feuerwache 6 (Güterstadt, Westen) und Feuerwache 9 (Industriehafen, Südosten).
- **Neue Kran-Einsätze:**
  - LKW umgestürzt (THL 2; Varianten: Fahrer eingeklemmt → THL 3, Ladung verloren)
  - Baukran umgestürzt (THL 3; Varianten: Person unter Last, Kranführer in Höhe → THL P RETTUNG H/T)
  - Straßenbahn entgleist (THL 2; Varianten: Fahrgäste verletzt → RD 3, gegen Gebäude geprallt → THL 3)
  - PKW in Gewässer (THL WASSER; Variante: Person im Fahrzeug → RD WASSERNOT 3)
- **Werkfeuerwehr:** »Werkfeuerwehr Bavaria Metallwerke« im Westen (ELW 1, HLF 20, TLF 3000, GW-L) mit eigenem Werksanitätsdienst (RTW), rund um die Uhr besetzt.

**Änderungen**
- **Wachen neu angeordnet:** Die 10 Feuerwachen der Berufsfeuerwehr liegen jetzt grob so wie in einer echten bayerischen Großstadt: Hauptfeuerwache im Zentrum, Wache 2 im Süden, 3 im Westend, 4 im Norden bei der Leitstelle, 5 im Osten, 6 weit im Westen, 7 im Norden, 8 im Nordosten, 9 im Südosten, 10 an der Messe. Die Flughafen-Wache der BF entfällt (der Flughafen hat seine eigene Flughafenfeuerwehr); dafür gibt es neue Freiwillige Feuerwehren in der Südstadt und am Flughafen-Nord.
- **Weniger Tanklöschfahrzeuge:** Nur noch 4 der 10 Feuerwachen haben ein TLF (5, 6, 9, 10).

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
