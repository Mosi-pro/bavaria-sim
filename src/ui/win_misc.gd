extends RefCounted
## Kleinere Informationsfenster: Personal, Einsatzarchiv, Statistik, Lage, Hilfe.

const UI = preload("res://src/ui/kit.gd")
const IL = preload("res://src/incidents/incident_logic.gd")
const Personnel = preload("res://src/personnel/personnel.gd")
const CallGen = preload("res://src/incidents/call_generator.gd")

static func personnel(host: Node) -> void:
	var tree := UI.tree([{"title": "Wache"}, {"title": "Organisation", "width": 170}, {"title": "Qualifikation", "width": 190}, {"title": "Soll", "width": 44}, {"title": "Dienst", "width": 50}, {"title": "Verfügbar", "width": 70}])
	var fill := func():
		tree.clear()
		var root := tree.create_item()
		var ids: Array = State.stations.keys()
		ids.sort_custom(func(a, b): return [State.stations[a]["org"], int(State.stations[a]["nr"])] < [State.stations[b]["org"], int(State.stations[b]["nr"])])
		var tot := 0
		var avail := 0
		for id in ids:
			var st: Dictionary = State.stations[id]
			var ov := Personnel.overview(id)
			var first := true
			for q in ov:
				var it := tree.create_item(root)
				if first:
					it.set_text(0, st["name"])
					it.set_text(1, Data.org_name(st["org"]))
					it.set_custom_color(0, Data.org_color(st["org"]).lightened(0.35))
					first = false
				it.set_text(2, Data.qualifications.get(q, q))
				it.set_text(3, str(ov[q][0]))
				it.set_text(4, str(ov[q][1]))
				it.set_text(5, str(ov[q][2]))
				if int(ov[q][2]) <= 0:
					it.set_custom_color(5, UI.RED)
				tot += int(ov[q][1])
				avail += int(ov[q][2])
		tree.set_meta("sum", "Personal im Dienst: %d   ·   davon auf den Wachen verfügbar: %d" % [tot, avail])
	fill.call()
	var sum := UI.label(tree.get_meta("sum", ""), UI.TEXT2)
	var box := UI.vbox([UI.label("Wachstärken nach Qualifikation. Fahrzeuge binden beim Alarm ihre Besatzung; ohne ausreichendes Personal kann ein Fahrzeug nicht ausrücken.", UI.TEXT2), tree,
		UI.hbox([sum, UI.spacer(), UI.button("Aktualisieren", func():
			fill.call()
			sum.text = tree.get_meta("sum", ""))])])
	UI.window(host, "Personalübersicht", Vector2i(820, 560), box, "personnel")

static func archive(host: Node) -> void:
	var tree := UI.tree([{"title": "Nr.", "width": 100}, {"title": "Zeit", "width": 130}, {"title": "Stichwort", "width": 80}, {"title": "Einsatzort"}, {"title": "EM", "width": 34}, {"title": "Ergebnis", "width": 90}, {"title": "Bew.", "width": 46}])
	var root := tree.create_item()
	var arr: Array = State.archive.duplicate()
	arr.reverse()
	for a in arr:
		var it := tree.create_item(root)
		it.set_text(0, a["nr"])
		it.set_text(1, a.get("time", ""))
		it.set_text(2, a["keyword"])
		it.set_text(3, a["address"])
		it.set_tooltip_text(3, String(a.get("lage", "")))
		it.set_text(4, str(int(a.get("vehicles", 0))))
		it.set_text(5, a["state"])
		it.set_text(6, "%d %%" % int(a["score"]) if int(a["score"]) >= 0 else "–")
	UI.window(host, "Einsatzarchiv (%d)" % arr.size(), Vector2i(860, 520), UI.vbox([tree]), "archive")

static func stats_text() -> String:
	var st: Dictionary = State.meta["stats"]
	var done := int(st["done"])
	var avg := 0.0 if done == 0 else float(st["score_sum"]) / done
	var resp := 0.0 if int(st["resp_n"]) == 0 else float(st["resp_sum"]) / int(st["resp_n"])
	var by := {}
	for id in State.vehicles:
		var s := int(State.vehicles[id]["status"])
		by[s] = int(by.get(s, 0)) + 1
	var sl: Array = []
	for s in [1, 2, 3, 4, 5, 6, 7, 8, 9]:
		if by.has(s):
			sl.append("Status %d: %d" % [s, by[s]])
	var t := "[b]Integrierte Leitstelle Bavaria – Schichtübersicht[/b]\n\n"
	t += "[color=#a4adb5]Spielmodus[/color]  %s   [color=#a4adb5]Schwierigkeit[/color]  %s\n" % [Data.modes["modes"].get(State.meta["mode"], {}).get("name", State.meta["mode"]), Data.modes["difficulties"].get(State.meta["difficulty"], {}).get("name", "")]
	t += "[color=#a4adb5]Schichtdauer[/color]  %s   [color=#a4adb5]Spielzeit[/color]  %s %s\n\n" % [State.dur_str(State.clock), State.date_str(), State.time_str()]
	t += "[color=#a4adb5]Notrufe gesamt[/color]  %d\n[color=#a4adb5]davon nicht angenommen / nicht bedient[/color]  %d\n[color=#a4adb5]Fehl- und Scherzanrufe[/color]  %d\n" % [int(st["calls"]), int(st["calls_missed"]), int(st["calls_nuisance"])]
	t += "[color=#a4adb5]Einsätze angelegt[/color]  %d\n[color=#a4adb5]Einsätze beendet[/color]  %d\n[color=#a4adb5]Laufende Einsätze[/color]  %d\n" % [int(st["incidents"]), done, State.incidents.size()]
	t += "[color=#a4adb5]Durchschnittliche Bewertung[/color]  %d %%\n[color=#a4adb5]Mittlere Zeit Alarm → Eintreffen[/color]  %s\n" % [int(avg), State.dur_str(resp)]
	t += "[color=#a4adb5]Transportierte Patienten[/color]  %d\n[color=#a4adb5]Verstorbene Patienten[/color]  %d\n[color=#a4adb5]Unbeantwortete Sprechwünsche[/color]  %d\n\n" % [int(st["saved"]), int(st["deaths"]), int(st.get("talk_ignored", 0))]
	t += "[color=#a4adb5]Einsatzmittel[/color]  %s\n" % "  ·  ".join(sl)
	t += "[color=#a4adb5]Erfahrungsstufe[/color]  %d  (%d XP)" % [int(State.meta["level"]), int(State.meta["xp"])]
	if State.meta["mode"] == "karriere":
		t += "   [color=#a4adb5]Budget[/color]  %s" % UI.money(int(State.meta["budget"]))
	return t

static func stats(host: Node) -> void:
	var r := UI.rich(false)
	r.scroll_following = false
	r.text = stats_text()
	var box := UI.vbox([r, UI.hbox([UI.spacer(), UI.button("Aktualisieren", func(): r.text = stats_text())])])
	UI.window(host, "Statistik / Schichtübersicht", Vector2i(560, 470), box, "stats")

static func situation(host: Node) -> void:
	var r := UI.rich(false)
	r.scroll_following = false
	var fill := func():
		var env: Dictionary = State.env
		var wd: Dictionary = Data.modes.get("weather", {}).get(env["weather"], {})
		var t := "[b]Lageinformation Stadtgebiet Bavaria[/b]   %s %s\n\n" % [State.date_str(), State.time_str()]
		t += "[color=#a4adb5]Wetter[/color]  %s   (Fahrgeschwindigkeit %d %%, Einsatzaufkommen ×%.2f)\n" % [wd.get("name", env["weather"]), int(float(wd.get("speed", 1.0)) * 100.0), float(wd.get("calls", 1.0))]
		t += "[color=#a4adb5]Verkehrslage[/color]  Faktor %.2f   (%d Staustrecken, %d Baustellen, %d Sperrungen)\n" % [float(env["traffic"]), env["jams"].size(), env["sites"].size(), env["closures"].size()]
		t += "[color=#a4adb5]Erwartetes Notrufaufkommen[/color]  ca. %d Anrufe pro Stunde\n\n" % int(CallGen.calls_per_hour())
		t += "[b]Veranstaltungen[/b]\n"
		if env["events"].is_empty():
			t += "[color=#6b737b]keine[/color]\n"
		for ev in env["events"]:
			t += "%s  (bis %s)\n" % [ev["name"], State.time_str(float(ev["until"]))]
		t += "\n[b]Sperrungen[/b]\n"
		if env["closures"].is_empty():
			t += "[color=#6b737b]keine[/color]\n"
		for k in env["closures"]:
			var e := int(k)
			t += "%s (%s) – %s\n" % [World.street_name(e), World.districts[World.edge_dist[e]]["name"], env["closures"][k]]
		t += "\n[b]Baustellen[/b]\n"
		for k in env["sites"]:
			var e := int(k)
			t += "%s (%s)\n" % [World.street_name(e), World.districts[World.edge_dist[e]]["name"]]
		r.text = t
	fill.call()
	UI.window(host, "Wetter- und Lageinformation", Vector2i(600, 480), UI.vbox([r, UI.hbox([UI.spacer(), UI.button("Aktualisieren", fill)])]), "situation")

static func help(host: Node, topic: String) -> void:
	var r := UI.rich(false)
	r.scroll_following = false
	var title := "Hilfe"
	match topic:
		"anleitung":
			title = "Kurzanleitung"
			r.text = """[b]So funktioniert die Leitstelle[/b]

Am einfachsten lernst du das Spiel mit der [b]Einweisung[/b] im Hauptmenü.

[b]Der wichtigste Bereich: »Was ist zu tun?« (links oben)[/b]
Dort steht immer, was als Nächstes erledigt werden muss – mit einem Knopf für genau diesen Schritt. Arbeite die Liste von oben nach unten ab.

[b]Der Ablauf eines Einsatzes[/b]
1. [b]Notruf annehmen[/b] (F2). Wartet ein Anrufer zu lange, legt er auf und ruft später verärgert wieder an.
2. [b]① Wo?[/b] – Ort klären. Grün = Adresse vollständig, gelb = Hausnummer fehlt, rot = nur Stadtteil. Nachfragen oder »Standort orten«.
3. [b]② Was?[/b] – Lage klären. Weitere Fragen (Wie viele? Gefahr? Zustand?) helfen bei schwierigen Anrufen.
4. [b]③ Stichwort[/b] – erst die Einsatzart (Brand, Technische Hilfe, Rettungsdienst …), dann das Stichwort. Danach »Einsatz anlegen«.
5. [b]Alarmieren[/b] – Das System hakt passende, schnelle Fahrzeuge an. Prüfen und ALARMIEREN.
6. [b]Rückmeldungen[/b] – Die erste Einheit meldet die tatsächliche Lage. Ist sie schlimmer als gemeldet, kommt ein [b]Sprechwunsch[/b] (Status 5, lila). Sprechaufforderung geben (F6) und fehlende Kräfte nachalarmieren.
7. [b]Abschließen[/b] – Ist der Einsatz beendet, in der Aufgabenliste »Abschließen«.

[b]Fahrzeugstatus (Farben in der rechten Liste)[/b]
1/2 frei · 3 auf der Anfahrt · 4 an der Einsatzstelle · 5 Sprechwunsch · 7/8 Patiententransport · 6 außer Dienst

[b]Stichwortfarben[/b]
[color=#d9534a]Feuerwehr (B, THL, ABC)[/color] · [color=#e58a2e]Rettungsdienst (RD)[/color] · [color=#5b95c8]Polizei (POL)[/color] · [color=#a4adb5]Sonstiges[/color]

[b]GW-L mit Rollcontainern[/b]
Der Gerätewagen Logistik hat einen wechselbaren Rollcontainer: Schlauch/Wasserversorgung, Tragkraftspritze, Hochwasser/Unwetter (Pumpen), Strom & Licht, Atemschutz, Gefahrgut/Ölspur oder Gitterbox/Transport. Beim Alarmieren in der Spalte »Rollcontainer« auswählen – Umladen geht nur auf der Wache und dauert 2 Minuten. Nachts brauchen längere Feuerwehreinsätze Beleuchtung (RW, GKW oder GW-L mit Strom & Licht).

[b]Feuerwehrkran (FwK 70)[/b]
Zwei Kranwagen an Feuerwache 6 und 9 – für umgestürzte LKW, Baukranunfälle, entgleiste Straßenbahnen und Fahrzeuge im Wasser. Sie fahren langsam (max. 80 km/h), also früh alarmieren.

[b]Schwierigkeit[/b]
Leicht: Das passende Stichwort wird vorgeschlagen.  Mittel: Nur die Einsatzart wird angedeutet.  Schwer/Experte: keine Hinweise, mehr und hektischere Notrufe.

[b]Karte[/b]
Ziehen = verschieben, Mausrad = zoomen, Klick auf Fahrzeug/Einsatz/Wache = Details, Rechtsklick = Kontextmenü.

[b]Tasten[/b]
F2 Notruf annehmen · F6 Sprechwunsch · F5 Speichern · Pause · Num +/− Zeitraffer · Pos1 Gesamtansicht · F11 Vollbild (änderbar in den Einstellungen)"""
		"stichworte":
			title = "Einsatzstichwörter und Alarmierungsvorschlag"
			var t := "[b]Einsatzstichwörter der ILS Bavaria[/b]\n[color=#a4adb5]Systematik angelehnt an die bayerische Alarmierungsbekanntmachung (Brand, THL, ABC, RD). Trupp = 3, Staffel = 6, Gruppe = 9 Einsatzkräfte.[/color]\n"
			for cat in ["brand", "thl", "abc", "rd", "pol", "sonst"]:
				t += "\n[b]%s[/b]\n" % Data.category_name(cat)
				for k in Data.keywords_in(cat):
					var kd: Dictionary = Data.keywords[k]
					t += "[color=#%s]%s[/color] – %s\n" % [Data.keyword_color(k).to_html(false), k, kd["name"]]
					if String(kd.get("schlagworte", "")) != "":
						t += "    [color=#a4adb5]Typisch:[/color] %s\n" % kd["schlagworte"]
					if String(kd.get("min", "")) != "":
						t += "    [color=#a4adb5]Mindestanforderung:[/color] %s\n" % kd["min"]
					t += "    [color=#a4adb5]Vorschlag:[/color] %s\n" % IL.need_text(kd.get("aao", {}))
			r.text = t
		"fms":
			title = "Funkmeldesystem – Statusübersicht"
			var t := "[b]FMS-Status[/b]  (konfigurierbar in data/fms_status.json)\n\n"
			for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]:
				var e: Dictionary = Data.fms["status"].get(k, {})
				if not e.is_empty():
					t += "[bgcolor=%s][color=#ffffff]  %s  [/color][/bgcolor]   %s\n" % [e["color"], k, e["text"]]
			t += "\nFunkrufnamen: Florian Bavaria (Feuerwehr) · Rettung Bavaria (Rettungsdienst) · Löwe (Polizei) · Kater Bavaria (Katastrophenschutz) · Heros Bavaria (THW) · Pelikan Bavaria (Wasserrettung).\nAufbau Feuerwehr: Wache / Fahrzeugkennzahl – laufende Nummer, z. B. Florian Bavaria 1/40-1 = HLF 20 der Feuerwache 1."
			r.text = t
		"about":
			title = "Über LEITSTELLE 112"
			r.text = "[b]LEITSTELLE 112[/b]   Version %s\n\nSimulation der Integrierten Leitstelle der fiktiven Millionenstadt Bavaria.\n\nAlle Orte, Straßen, Wachen, Funkrufnamen, Personen und Telefonnummern sind frei erfunden. Fahrzeugtypen, Statusmeldungen und Dispositionsgrundsätze orientieren sich an öffentlich bekannten Grundlagen deutscher Leitstellen. Das Programm ist ein Spiel und kein Ausbildungs- oder Einsatzführungssystem.\n\nErstellt mit der Godot Engine (MIT-Lizenz). Karte, Grafiken und Töne wurden eigens für dieses Spiel erzeugt.\n\nStadt Bavaria: %d Straßenknoten, %d Straßenabschnitte, %d Straßennamen." % [ProjectSettings.get_setting("application/config/version", "1.0"), World.node_pos.size(), World.edge_a.size(), World.names.size()]
	UI.window(host, title, Vector2i(760, 560), UI.vbox([r]), "help_" + topic)
