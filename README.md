# LEITSTELLE 112 – Integrierte Leitstelle Bavaria

Eigenständige Windows-Desktop-Simulation einer deutschen Integrierten Leitstelle
(Godot 4.7, GDScript). Der Spieler arbeitet als Disponent der **Integrierten Leitstelle
Bavaria**, einer fiktiven Millionenstadt in Bayern: Notrufe abfragen, Einsätze anlegen,
Einsatzmittel disponieren und alarmieren, Fahrzeuge auf der Lagekarte verfolgen,
Nachforderungen bearbeiten und Einsätze abschließen – allein oder gemeinsam im Mehrspielermodus.

Alle Orte, Straßen, Wachen, Funkrufnamen, Personen und Telefonnummern sind frei erfunden.

## Funktionsumfang

| Bereich | Umsetzung |
|---|---|
| Spielwelt | Stadt Bavaria (≈ 26 × 23 km), 18 Stadtteile + 5 Randgemeinden, ≈ 7.700 Straßenknoten, ≈ 11.900 Straßenabschnitte, ≈ 1.000 Straßennamen, Autobahnring A 99, A 1/A 2/A 3/A 991 mit 40 Anschlussstellen, Bundesstraßen, Ringe, Kreisstraßen, Fußgängerzone, Brücken, Tunnel, Ampeln, Kreisverkehre, Flüsse, Seen, Wälder, Flughafen, Hafen, Messe, Stadion, Universität, Bahnanlagen, 50 besondere Objekte, 9 Kliniken |
| Karte | Eigene Vektorkarte (offline), chunkbasiert (1-km-Kacheln) mit 4 Detailstufen, Gebäude erst bei hoher Zoomstufe und bedarfsweise erzeugt, räumlicher Index, Straßennamen, Verkehrslage, Baustellen, Sperrungen, Routen |
| Organisationen | Feuerwehr (10 BF-Wachen, Flughafenfeuerwehr, 13 FF), Rettungsdienst (22 Standorte inkl. NEF, ITW, KTW, SEG, ELRD), Polizei (Präsidium, 9 PI, VPI, Einsatzhundertschaft, Kripo, Spezialeinheit), THW, Wasserrettung, Katastrophenschutz – 66 Standorte, 271 Fahrzeuge, 52 Fahrzeugtypen |
| Notrufe | Dynamisch erzeugt, Tageszeit-/Wetter-/Stadtteil-/Veranstaltungsabhängig; Anrufertypen (ruhig, aufgeregt, panisch, Senior, Kind, Passant), ungenaue Ortsangaben (Stadtteil / Straße / genau), Rückfragen, Beruhigen, AML-Ortung, Folge- und Wiederholungsanrufe, Fehl- und Scherzanrufe, Mehrfachmeldungen |
| Einsätze | 46 Einsatzarten mit eigener Logik (Lagevarianten, Lageentwicklungen, Verschärfung bei Kräftemangel, Patienten mit Verschlechterung, technische Rettung vor Patientenversorgung, Transport in geeignete Kliniken, Sperrungen); 51 Einsatzstichwörter nach bayerischer Systematik mit Mindestanforderung und Alarmierungsvorschlag |
| Disposition | Vorschlag nach realer Fahrzeit (Dijkstra/A* im Straßennetz), Verfügbarkeit, Besatzung, Fähigkeiten und laufenden Einsätzen; Entscheidung beim Spieler |
| Fahrzeuge | FMS-Status 1–9 (konfigurierbar), Ausrückzeiten je Wachentyp, Sonder- und Wegerechte, Routing mit Straßenklassen, Abbiegekosten, Ampeln, Sperrungen, Verkehr; Neuroutung bei Sperrung |
| Personal | Wachstärke je Qualifikation, Mindestbesatzung und Qualifikationen je Fahrzeug, eingeschränkte Verfügbarkeit Freiwilliger (Realismusmodus) |
| Kommunikation | Funkprotokoll mit Zeitstempel und Status, Sprechwünsche (Status 5) mit Sprechaufforderung, Textnachrichten, Systemmeldungen, Alarmmeldungen, Einsatznotizen, Chat |
| Spielmodi | Freies Spiel, Karriere (Budget, Erfahrung, Regionen, Organisationen, Beschaffung), Realismusmodus, 6 Szenarien (Großbrand, Massenkarambolage, Unwetter, Gefahrgut, Großveranstaltung, Hochwasser), Multiplayer; 4 Schwierigkeitsgrade |
| Mehrspieler | Peer-to-Peer mit Host-Autorität über ENet, LAN-Suche (UDP-Broadcast) und Direkt-IP, Ping, Passwortschutz per Challenge-Response, Rollen, Lobby, Chat, Synchronisierung, Wiederverbindung, Host-Verlassen, optional UPnP |
| Weiteres | Speichern/Laden/Autosave/Löschen, Einstellungen, eigene synthetische Audiosignale, Wachen- und Standortverwaltung, Statistik, Einsatzarchiv |

## Einstieg für neue Spieler

* **Einweisung** (Hauptmenü, grüner Knopf): geführte erste Schicht in 12 Schritten – vom ersten Notruf bis zur Nachalarmierung.
* **„Was ist zu tun?“** (links oben): listet jederzeit die offenen Aufgaben nach Dringlichkeit, jeweils mit einem Knopf für den nächsten Schritt.
* **Notruffenster in drei Schritten:** ① Wo? ② Was? ③ Einsatzart → Stichwort → Einsatz anlegen.
* **Einsatzakte:** zeigt zuerst nur den Vorschlag des Systems und den Bedarf in Klartext (✓ vor Ort · … unterwegs · ✗ fehlt).
* **Schwierigkeit:** Leicht schlägt das Stichwort vor, Mittel nennt nur die Einsatzart, Schwer und Experte geben keine Hinweise.

## Bedienung (Kurzfassung)

* **F2** Notruf annehmen → Rückfragen → Stichwort wählen → *Einsatz anlegen und disponieren*
* Dispositionsfenster: Vorschlag prüfen/ändern → **ALARMIEREN**
* **F6** Sprechwunsch annehmen (Lagemeldungen, Nachforderungen)
* Karte: ziehen = verschieben, Mausrad = zoomen, Klick = Details, Rechtsklick = Kontextmenü
* **F5** Schnellspeichern, **Pause**, Num +/− Zeitraffer, **F11** Vollbild

## Internet-Spiel ohne Einrichtung (Vermittlungsdienst)

Ein kleiner Vermittlungsdienst, z. B. auf einem Dell Wyse zuhause, führt die Serverliste und reicht die Spieldaten weiter. Host und Mitspieler bauen nur ausgehende Verbindungen auf, deshalb braucht beim Kunden niemand eine Portfreigabe. Der Host bekommt einen **Einladungscode**, die Mitspieler geben ihn ein oder wählen die Sitzung aus der Liste.
Die Simulation läuft weiterhin ausschließlich beim Host; der Dienst kennt keine Passwörter. Einrichtung: [docs/VERMITTLUNGSDIENST.md](docs/VERMITTLUNGSDIENST.md). Start: `leitstelle112.x86_64 --headless -- --vermittlung`.

## Mehrspieler hosten

1. Hauptmenü → **SPIEL ERSTELLEN**: Servername, Spielername, Passwort, max. Spieler, Spielmodus, Region, private Sitzung.
2. Die Lobby zeigt die lokalen IP-Adressen und den Port (Standard **24112/UDP**). Im LAN erscheint die Sitzung automatisch in der Serverliste der Mitspieler.
3. Internet: Port 24112/UDP am Router auf den Host-PC weiterleiten (oder in der Lobby „Portfreigabe per UPnP versuchen“) und die öffentliche IP weitergeben.
4. Mitspieler: Hauptmenü → **MULTIPLAYER** → Sitzung wählen bzw. IP/Port eingeben → Passwort → Verbinden.
5. Rollen in der Lobby zuweisen (Schichtführung, Disposition, Feuerwehr, Rettungsdienst, Polizei, Beobachter), dann **Spiel starten**.
   Ein laufendes Einzelspiel lässt sich über *Multiplayer → Laufendes Spiel für Mitspieler öffnen* freigeben.

## Einsatzstichwörter und Fahrzeuge

* **Stichwörter** folgen der Systematik der öffentlich bekanntgemachten bayerischen Alarmierungsbekanntmachung (ABek): Brand (B 1–B 5, B 2/B 3 PERSON, B BMA, B ZUG, B WALD …), THL (THL 1–5, THL P EINGESCHLOSSEN, THL P RETTUNG H/T …), ABC (ABC 1–3, ABC EXPLOSION, Gefahrstoff-Meldeanlage …) und RD (RD 1, RD 2, RD 2-KIND, RD 3–5, RD MANV …). Zu jedem Stichwort zeigt das Spiel typische Schlagwörter und die Mindestanforderung (Trupp/Staffel/Gruppe, Löschwasser, Atemschutz).
* Das richtige Stichwort ergibt sich aus der **tatsächlichen Lage** (z. B. B 3 PERSON, wenn Menschen in Gefahr sind). Gleichwertige Stichwörter werden in der Bewertung nur gering abgezogen.
* **Fahrzeugtypen** nach dem Vorbild bayerischer Großstädte, u. a. Kleinalarmfahrzeug, Schwerlast-RTW, Großraum-RTW, Kindernotarzt, Höhenrettung, Dekon-Fahrzeug, Diensthundeführer, Polizei-Motorrad und Kriseninterventionsteam. Rettungswagen stehen auch an Feuerwachen.
* Alle Wachen, Standorte und Fahrzeugbestände von Bavaria bleiben **erfunden**; reale Standort- und Bestandslisten werden nicht nachgebildet.

## Architektur

```
src/core          Datenladen (Data), Sitzungssteuerung (Game), Hauptszene
src/map           Stadtgenerator, Welt/Routing (A*, Dijkstra), Kartenansicht, Chunks, Gebäude, Overlay
src/simulation    Spielzustand (State), autoritative Simulation (Sim), Umwelt, Spielmodi
src/incidents     Notrufgenerator/Gesprächsführung, Einsatzlogik
src/dispatch      Dispositionsvorschlag
src/vehicles      Fahrzeugstatus und Bewegung
src/stations      Wachen- und Fahrzeugverwaltung
src/personnel     Besatzung und Wachstärken
src/multiplayer   ENet-Host/Client, Authentifizierung, LAN-Erkennung
src/audio         Tonausgabe
src/save          Spielstände, lokale Datenbank
src/settings      Einstellungen
src/ui            Theme, Arbeitsplatz, Fenster
data/             sämtliche Spielparameter als JSON
tests/            automatisierte Tests
tools/            Generatoren (Wachen, Audio), Build- und Testskripte
installer/        Inno-Setup-Skript
```

### Wichtige Entscheidungen

* **Prozedurale, deterministische Stadt.** Bavaria wird aus `data/world/bavaria.json` (Stadtteile, Ringe, Radialen, Autobahnen, Flüsse, Flächen, Objekte) mit festem Seed erzeugt. Damit ist die Karte frei von fremden Kartendaten, offline verfügbar und auf Host und Clients bitgenau identisch – über das Netz werden nur Zustände, nie Kartendaten übertragen.
* **Getrennter Zustand und Simulation.** `State` enthält ausschließlich serialisierbare Daten. Nur der Host führt `Sim` aus; Clients spiegeln den Zustand und senden Aktionen (`Sim.act`), die der Host gegen Authentifizierung, Rolle, Rate-Limit und Spielzustand prüft. Dieselbe Aktionsschnittstelle nutzt auch der Einzelspieler.
* **Verdeckte Lagen.** Die tatsächliche Lage eines Notfalls („truth“) kennt nur die Simulation des Hosts. Der Disponent erfährt sie über das Gespräch und die Lagemeldung der ersten Einheit; Clients erhalten verdeckte Daten nie.
* **Lokale Datenbank ohne native Erweiterung.** Statt einer SQLite-GDExtension (zusätzliche DLL, Versionsbindung) dient eine kleine Dokumentendatenbank aus JSON-Tabellen (`user://db`) für Spielstandindex, Profil und Serverliste; Spielstände selbst sind binär (Godot-Variant ohne Objekte, daher sicher ladbar).
* **Passwörter.** Der Host hält nur Salt und PBKDF2-HMAC-SHA256-Schlüssel; der Client beweist die Kenntnis des Passworts per HMAC über zwei Zufallswerte. Das Passwort wird weder gespeichert noch übertragen; Fehlversuche führen zu einer Sperre.
* **Audio** wird mit `tools/gen_audio.py` synthetisch erzeugt (keine Fremdaufnahmen).
* **Konfigurierbarkeit.** Alle Spielparameter liegen in `data/*.json`; in der installierten Version überschreiben Dateien im Ordner `config` neben der EXE die Standardwerte (Vorlagen in `config_standard`).

## Tests

```bash
godot --headless --path . res://tests/run_tests.tscn     # 87 Kerntests inkl. Einweisung und Durchlauf aller Einsatzarten
tools/test_multiplayer.sh                                # Host + 2 Clients als getrennte Prozesse
LEITSTELLE112.exe --headless --selbsttest                # Selbsttest der fertigen Anwendung
```

## Bekannte Einschränkungen

* Sprache der Oberfläche: Deutsch (Englisch als „nicht verfügbar“ gekennzeichnet).
* Eine öffentliche Internet-Serverliste (Vermittlungsdienst) ist nicht enthalten; Internetspiele laufen über Direkt-IP und Portfreigabe.
* Die Karte ist eine sachliche 2D-Lagekarte; es gibt keine 3D-Ansicht.

Siehe [BUILD.md](BUILD.md) für die Erstellung der Windows-Version.
