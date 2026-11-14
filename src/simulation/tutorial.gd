extends RefCounted
## Einweisung: geführte erste Schicht. Erzeugt gezielt Einsätze und schaltet weiter,
## sobald der Spieler den jeweiligen Arbeitsschritt erledigt hat.
## Fortschritt liegt in State.meta["tutorial"] = {step, call, inc}.

const CallGen = preload("res://src/incidents/call_generator.gd")
const IL = preload("res://src/incidents/incident_logic.gd")

const LAST := 12

## Texte je Schritt: [Überschrift, Erklärung]. Die Oberfläche zeigt sie an.
const STEPS := [
	["Willkommen in der Leitstelle", "Du bist Disponent der Integrierten Leitstelle Bavaria. Deine Aufgabe: Notrufe annehmen, die Lage klären und die passenden Fahrzeuge losschicken.\n\nGleich geht der erste Notruf ein."],
	["1. Notruf annehmen", "Das Telefon klingelt. In der Aufgabenliste links steht »Notruf wartet«.\n\n→ Klicke dort auf »Annehmen« (oder drücke F2)."],
	["2. Wo ist der Notfall?", "Das Wichtigste zuerst: der Ort. Der Anrufer nennt meist schon eine Adresse.\n\n→ Klicke im Notruffenster bei Schritt ① auf »Wo genau?«. Grün bedeutet: Adresse vollständig."],
	["3. Was ist passiert?", "Jetzt die Lage klären.\n\n→ Klicke bei Schritt ② auf »Was ist passiert?«. Weitere Fragen (Wie viele? Gefahr? Zustand?) helfen dir bei schwierigeren Notrufen."],
	["4. Stichwort wählen und Einsatz anlegen", "Das Stichwort bestimmt, welche Fahrzeuge vorgeschlagen werden. Hier geht es um einen medizinischen Notfall ohne Lebensgefahr.\n\n→ Wähle bei Schritt ③ die Kategorie »Rettungsdienst / Verletzte« und das Stichwort »RD 1«. Klicke dann »Einsatz anlegen«."],
	["5. Fahrzeuge alarmieren", "Die Einsatzakte öffnet sich. Das System hat bereits passende, schnell verfügbare Fahrzeuge vorgeschlagen und angehakt.\n\n→ Prüfe den Vorschlag und klicke auf »ALARMIEREN«."],
	["6. Anfahrt verfolgen", "Der Rettungswagen rückt aus (Status 3 = Einsatz übernommen) und fährt mit Sonderrechten zur Einsatzstelle. Du siehst ihn auf der Karte.\n\nTipp: Mit dem Zeitraffer oben rechts (2×, 4×) vergeht die Wartezeit schneller."],
	["7. Rückmeldung abwarten", "Das Fahrzeug ist angekommen (Status 4). Es meldet die Lage über Funk – unten im Funkprotokoll. Der Patient wird versorgt und ins Krankenhaus gebracht (Status 7 und 8)."],
	["8. Einsatz abschließen", "Der Einsatz ist beendet, das Fahrzeug fährt zurück zur Wache.\n\n→ Klicke in der Aufgabenliste bei »Einsatz beendet« auf »Abschließen«. Er landet dann im Einsatzarchiv."],
	["9. Ungenaue Ortsangabe", "Neuer Notruf: Es brennt etwas. Diesmal kennt der Anrufer die Hausnummer nicht – die Ortsangabe ist gelb (ungenau).\n\n→ Nimm den Notruf an, frage nochmals »Wo genau?« oder nutze »Standort orten«. Lege den Einsatz mit Stichwort »B 1« an und alarmiere."],
	["10. Ein größerer Einsatz", "Ein Wohnungsbrand wird gemeldet. Lege den Einsatz mit »B 3« an und alarmiere den Vorschlag.\n\nAchtung: Vor Ort kann die Lage schlimmer sein als gemeldet."],
	["11. Nachforderung bearbeiten", "Die Einsatzstelle braucht mehr Kräfte: Ein Fahrzeug meldet Status 5 (Sprechwunsch, lila).\n\n→ Klicke in der Aufgabenliste auf »Sprechen« und höre die Meldung im Funkprotokoll.\n→ Danach bei »Kräfte fehlen« auf »Nachalarmieren« – der Vorschlag enthält genau die fehlenden Fahrzeuge."],
	["Einweisung abgeschlossen", "Gut gemacht! Du kennst jetzt den kompletten Ablauf:\nNotruf annehmen → Ort klären → Lage klären → Stichwort → alarmieren → Rückmeldungen bearbeiten → abschließen.\n\nAb jetzt gehen Notrufe zufällig ein. Die Aufgabenliste links zeigt dir immer, was als Nächstes zu tun ist. Weitere Hilfe: Menü »Hilfe«."],
]

static func active() -> bool:
	return State.meta.get("mode", "") == "einweisung" and State.meta.has("tutorial")

static func start() -> void:
	State.meta["tutorial"] = {"step": 0, "call": "", "inc": "", "t": 0.0}
	State.meta["next_call"] = 1e12

static func _go(tut: Dictionary, step: int) -> void:
	tut["step"] = step
	tut["t"] = State.clock
	State.meta_changed.emit()

static func _spawn(tut: Dictionary, type_id: String, opts: Dictionary) -> void:
	tut["call"] = CallGen.spawn_event(type_id, opts)
	tut["inc"] = ""

static func tick(_h: float) -> void:
	if not active():
		return
	var tut: Dictionary = State.meta["tutorial"]
	var step := int(tut["step"])
	# Einsatz des aktuellen Notrufs merken
	var cid: String = tut.get("call", "")
	if cid != "" and String(tut.get("inc", "")) == "":
		for iid in State.incidents:
			if State.incidents[iid].get("call", "") == cid:
				tut["inc"] = iid
				break
	var c: Dictionary = State.calls.get(cid, {})
	var inc: Dictionary = State.incidents.get(tut.get("inc", ""), {})
	var since := State.clock - float(tut.get("t", 0.0))
	match step:
		0:
			if since > 6.0:
				_spawn(tut, "med_notfall", {"district": "altstadt", "variant": 0, "loc_level": 2})
				_go(tut, 1)
		1:
			if not c.is_empty() and c["state"] == "active":
				_go(tut, 2)
		2:
			if not c.is_empty() and c["asked"].has("q_wo"):
				_go(tut, 3)
		3:
			if not c.is_empty() and c["asked"].has("q_was"):
				_go(tut, 4)
		4:
			if not inc.is_empty():
				_go(tut, 5)
		5:
			if not inc.is_empty() and float(inc["t_alarm"]) >= 0.0:
				_go(tut, 6)
		6:
			if not inc.is_empty() and float(inc["t_arrival"]) >= 0.0:
				_go(tut, 7)
		7:
			if not inc.is_empty() and inc["done"]:
				_go(tut, 8)
		8:
			if inc.is_empty():
				_spawn(tut, "brand_muell", {"district": "zentrum_sued", "variant": 0, "loc_level": 1})
				_go(tut, 9)
		9:
			if not inc.is_empty() and float(inc["t_alarm"]) >= 0.0:
				tut["prev_inc"] = tut["inc"]
				_spawn(tut, "brand_wohnung", {"district": "westend", "variant": 2, "loc_level": 2})
				_go(tut, 10)
		10:
			if not inc.is_empty() and inc["revealed"]:
				_go(tut, 11)
		11:
			if not inc.is_empty() and inc["revealed"] and not inc.get("need", {}).is_empty():
				var talks := false
				for vid in State.incident_vehicles(inc["id"]):
					if State.vehicles[vid]["talk"] != "":
						talks = true
				if not talks and IL.shortage(inc["need"], IL.caps_assigned(inc["id"])).is_empty():
					_finish(tut)
			elif not inc.is_empty() and inc["done"]:
				_finish(tut)

static func _finish(tut: Dictionary) -> void:
	_go(tut, LAST)
	State.meta["next_call"] = State.clock + 60.0
	Sim.radio("Leitstelle", "Einweisung abgeschlossen – ab jetzt regulärer Leitstellenbetrieb.", -1, "system", "")
