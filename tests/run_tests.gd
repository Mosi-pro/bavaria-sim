extends Node
## Automatisierte Tests der Kernfunktionen (ohne Oberfläche).
## Aufruf:  godot --headless --path . res://tests/run_tests.tscn
const IL = preload("res://src/incidents/incident_logic.gd")
const VL = preload("res://src/vehicles/vehicle_logic.gd")
const CallGen = preload("res://src/incidents/call_generator.gd")
const Advisor = preload("res://src/dispatch/advisor.gd")
const Personnel = preload("res://src/personnel/personnel.gd")
const SaveSystem = preload("res://src/save/save_system.gd")
const Auth = preload("res://src/multiplayer/auth.gd")
const Modes = preload("res://src/simulation/modes.gd")

var passed := 0
var failed := 0
var me := {"name": "Tester", "role": "leitung"}

func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  ok    ", name)
	else:
		failed += 1
		print("  FEHLER ", name)

func run(max_sim: float, until: Callable) -> bool:
	var t := 0.0
	while t < max_sim:
		Sim.step(0.5)
		CallGen.real_tick(0.25)
		t += 0.5
		if until.call():
			return true
	return false

func _ready() -> void:
	Settings.set_v("game", "autosave", false)
	World.ensure_built()
	print("== Daten ==")
	test_data()
	print("== Welt und Routing ==")
	test_world()
	print("== Notruf, Einsatz, Alarmierung, Navigation, Abschluss ==")
	test_incident_chain()
	print("== Personal und Rollen ==")
	test_personnel_roles()
	print("== Wachenverwaltung und Karriere ==")
	test_management()
	print("== Alle Einsatzarten ==")
	test_all_types()
	print("== Rettungshubschrauber ==")
	test_rth()
	print("== GW-L Rollcontainer und Stichwortfarben ==")
	test_gwl_modules()
	print("== Notrufgespräche und Häufigkeiten ==")
	test_calls_consistency()
	print("== Einweisung ==")
	test_tutorial()
	print("== Szenarien ==")
	test_scenarios()
	print("== Speichern und Laden ==")
	test_save_load()
	print("== Beta-Zugangscodes ==")
	test_beta()
	print("== Authentifizierung ==")
	test_auth()
	print("\nErgebnis: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func test_data() -> void:
	var caps_provided := {}
	for t in Data.vehicle_types.values():
		for c in t["caps"]:
			caps_provided[c] = true
		check(Data.organisations.has(t["org"]), "Fahrzeugtyp %s hat gültige Organisation" % t["short"]) if not Data.organisations.has(t["org"]) else null
	var ok := true
	for k in Data.keywords:
		for c in Data.keywords[k]["aao"]:
			if not caps_provided.has(c):
				ok = false
				print("    AAO-Fähigkeit ohne Fahrzeug: ", k, " ", c)
	check(ok, "Alle AAO-Fähigkeiten werden von Fahrzeugtypen abgedeckt")
	ok = true
	for id in Data.incident_types:
		var t: Dictionary = Data.incident_types[id]
		if not Data.keywords.has(t["keyword"]) or not Data.call_scripts["scripts"].has(t["call"]):
			ok = false
			print("    Einsatzart fehlerhaft: ", id)
		var psum := 0.0
		for v in t["variants"]:
			psum += float(v["p"])
			for c in v.get("reqs", {}):
				if not caps_provided.has(c):
					ok = false
					print("    Bedarf ohne Fahrzeug: ", id, " ", c)
		if absf(psum - 1.0) > 0.01:
			ok = false
			print("    Variantenwahrscheinlichkeit != 1: ", id, " ", psum)
	check(ok, "Einsatzarten: Stichwörter, Gesprächsskripte, Varianten konsistent (%d Arten)" % Data.incident_types.size())
	ok = true
	for st in Data.stations:
		for v in st["vehicles"]:
			if not Data.vehicle_types.has(v) or Data.vehicle_types[v]["org"] != st["org"]:
				ok = false
		if st["vehicles"].size() > int(st["slots"]):
			ok = false
	check(ok, "Wachen: Fahrzeugtypen und Stellplätze gültig (%d Wachen)" % Data.stations.size())
	check(Data.scenarios.size() == 6, "Sechs Szenarien definiert")
	check(World.districts.size() >= 19, "18 Stadtteile plus Umland/Randgemeinden")

func test_world() -> void:
	World.ensure_built()
	check(World.node_pos.size() > 5000 and World.edge_a.size() > 8000, "Straßennetz erzeugt (%d Knoten, %d Kanten)" % [World.node_pos.size(), World.edge_a.size()])
	var t := World.times_from(World.nearest_node(Vector2.ZERO))
	var unreachable := 0
	for x in t:
		if x == INF:
			unreachable += 1
	check(unreachable == 0, "Straßennetz ist vollständig zusammenhängend")
	var a := World.nearest_node(Vector2(-7000, 3000))
	var b := World.nearest_node(Vector2(5500, -6000))
	var r := World.find_path(a, b, true)
	check(r["ok"] and r["nodes"].size() > 20, "A*-Route quer durch die Stadt (%.1f km, %.0f s)" % [r["dist"] / 1000.0, r["time"]])
	var rn := World.find_path(a, b, false)
	check(rn["time"] > r["time"], "Sonderrechte verkürzen die Fahrzeit")
	var uses_major := false
	for i in range(r["nodes"].size() - 1):
		var e := World.edge_between(r["nodes"][i], r["nodes"][i + 1])
		if World.edge_cls[e] <= World.CLS_BUNDES:
			uses_major = true
	check(uses_major, "Route nutzt Autobahn/Bundesstraße (Straßenklassen berücksichtigt)")
	var mid: int = r["nodes"].size() / 2
	var e_block := World.edge_between(r["nodes"][mid], r["nodes"][mid + 1])
	World.set_edge_blocked(e_block, true)
	var r2 := World.find_path(a, b, true)
	var avoided := true
	for i in range(r2["nodes"].size() - 1):
		if World.edge_between(r2["nodes"][i], r2["nodes"][i + 1]) == e_block:
			avoided = false
	check(r2["ok"] and avoided and r2["time"] >= r["time"], "Straßensperrung wird umfahren")
	World.set_edge_blocked(e_block, false)
	World.set_edge_traffic(e_block, 4.0)
	check(World.edge_te[e_block] > World.edge_len[e_block] / (World.SPEED_EMERG[World.edge_cls[e_block]] / 3.6), "Verkehr verlängert die Kantenfahrzeit")
	World.set_edge_traffic(e_block, 1.0)
	var ad := World.address_at(Vector2(100, 300))
	check(ad["street"] != "" and ad["text"].find("Bavaria") >= 0, "Adressauflösung: " + ad["text"])
	var names := {}
	for d in World.districts:
		names[d["name"]] = true
	check(names.has("Altstadt") and names.has("Flughafen Bavaria") and names.has("Industriehafen") and names.has("Bahnhofsviertel"), "Stadtteile vorhanden")
	check(World.class_edges[World.CLS_AUTOBAHN].size() > 100 and World.junctions.size() > 15, "Autobahnen A 99/A 1/A 2/A 3 mit %d Anschlussstellen" % World.junctions.size())

func test_incident_chain() -> void:
	Sim.new_game({"mode": "frei", "difficulty": "mittel", "seed": 99})
	Sim.running = false
	State.meta["next_call"] = 1e12
	check(State.stations.size() == Data.stations.size() and State.vehicles.size() > 200, "Spielstart: %d Wachen, %d Fahrzeuge" % [State.stations.size(), State.vehicles.size()])
	var cid := CallGen.spawn_event("brand_wohnung", {"district": "westend", "variant": 1})
	check(State.calls.has(cid) and State.calls[cid]["state"] == "ringing", "Notruf wird erzeugt und klingelt")
	check(Sim.act({"a": "call_take", "id": cid}, me)["ok"], "Notruf annehmen")
	var c: Dictionary = State.calls[cid]
	run(30.0, func(): return c["transcript"].size() >= 3)
	check(c["transcript"].size() >= 3, "Gesprächsprotokoll wird geführt")
	for q in ["q_beruhigen", "q_wo", "q_wo", "q_wo", "q_was", "q_personen", "q_gefahr"]:
		Sim.act({"a": "call_ask", "id": cid, "q": q}, me)
	run(40.0, func(): return c["pending"].is_empty())
	Sim.act({"a": "call_locate", "id": cid}, me)
	run(10.0, func(): return c["pending"].is_empty())
	check(c["known"].has("what"), "Rückfragen liefern Angaben")
	if int(c["loc_level"]) < 2:
		var tr0: Dictionary = State.truths[c["truth"]]
		CallGen._set_loc_level(c, tr0, 2)
	var res: Dictionary = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": "B 3", "x": c["loc"]["x"], "y": c["loc"]["y"], "address": c["loc"]["text"], "radius": c["loc"]["r"]}}, me)
	check(res["ok"], "Einsatz aus Notruf anlegen")
	var iid: String = res["id"]
	var inc: Dictionary = State.incidents[iid]
	Sim.act({"a": "call_end", "id": cid}, me)
	check(not State.calls.has(cid), "Gespräch beenden")
	check(inc["status"] == "neu", "Einsatzstatus: Neu")
	var s := Advisor.suggest(inc)
	check(s["suggested"].size() >= 5 and s["missing"].is_empty(), "Dispositionsvorschlag (%d Fahrzeuge)" % s["suggested"].size())
	var first: Dictionary = State.vehicles[s["suggested"][0]]
	var seen := {int(first["status"]): true}
	res = Sim.act({"a": "inc_alarm", "id": iid, "vehicles": s["suggested"]}, me)
	check(res["ok"] and res["alarmed"].size() == s["suggested"].size(), "Alarmierung")
	check(inc["status"] == "alarmiert" and int(first["status"]) == 9, "Einsatzstatus: Alarmiert, Fahrzeug quittiert")
	var start := State.veh_pos(first)
	var flags := {"moved": false, "transported": false, "talk": false}
	var states := {}
	var done: bool = run(4 * 3600.0, func():
		seen[int(first["status"])] = true
		states[inc["status"]] = true
		if State.veh_pos(first).distance_to(start) > 100.0:
			flags["moved"] = true
		for vid in State.vehicles:
			if State.vehicles[vid]["talk"] != "":
				Sim.act({"a": "veh_talk", "id": vid}, me)
		if inc["revealed"] and not inc["done"] and int(State.clock) % 60 == 0:
			var s2 := Advisor.suggest(inc)
			if s2["suggested"].size() > 0:
				Sim.act({"a": "inc_alarm", "id": iid, "vehicles": s2["suggested"]}, me)
		return inc["done"])
	check(flags["moved"], "Fahrzeuge bewegen sich über das Straßennetz")
	check(states.has("anfahrt") and states.has("vor_ort") and states.has("laeuft"), "Einsatzstatus durchläuft Anfahrt → Vor Ort → Einsatz läuft")
	check(inc["revealed"] and String(inc["lage"]).begins_with("Lagemeldung"), "Ersteintreffende Einheit gibt Lagemeldung")
	check(done and inc["status"] == "rueckfahrt" and int(inc["score"]) > 50, "Einsatz wird beendet (Bewertung %d %%)" % int(inc["score"]))
	run(3600.0, func():
		seen[int(first["status"])] = true
		return first["state"] == "station")
	check(seen.has(3) and seen.has(4) and seen.has(1) and seen.has(2), "Fahrzeugstatus 2 → 3 → 4 → 1 → 2 durchlaufen")
	check(first["crew"].is_empty(), "Besatzung nach Rückkehr wieder verfügbar")
	check(Sim.act({"a": "inc_close", "id": iid}, me)["ok"] and not State.incidents.has(iid) and State.archive.size() == 1, "Einsatz abschließen und archivieren")
	var radio_kinds := {}
	for e in State.radio:
		radio_kinds[e["kind"]] = true
	check(radio_kinds.has("alarm") and radio_kinds.has("status") and radio_kinds.has("funk") and radio_kinds.has("system"), "Funkprotokoll enthält Alarm-, Status-, Funk- und Systemmeldungen")
	# medizinischer Notfall mit Transport
	cid = CallGen.spawn_event("med_bewusstlos", {"district": "altstadt", "variant": 0})
	Sim.act({"a": "call_take", "id": cid}, me)
	c = State.calls[cid]
	CallGen._set_loc_level(c, State.truths[c["truth"]], 2)
	res = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": "RD 2", "x": c["loc"]["x"], "y": c["loc"]["y"]}}, me)
	Sim.act({"a": "call_end", "id": cid}, me)
	inc = State.incidents[res["id"]]
	s = Advisor.suggest(inc)
	Sim.act({"a": "inc_alarm", "id": inc["id"], "vehicles": s["suggested"]}, me)
	run(3 * 3600.0, func():
		for vid in State.vehicles:
			if State.vehicles[vid]["state"] == "transport":
				flags["transported"] = true
		return inc["done"])
	check(flags["transported"] and inc["done"], "Rettungsdienst: Versorgung, Transport (Status 7), Einsatzende")
	# ungenaue Ortsangabe → Einsatzstelle wird gesucht
	cid = CallGen.spawn_event("brand_muell", {"district": "nordstadt", "variant": 0})
	Sim.act({"a": "call_take", "id": cid}, me)
	c = State.calls[cid]
	var tr: Dictionary = State.truths[c["truth"]]
	CallGen._set_loc_level(c, tr, 0)
	res = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": "B 1", "x": c["loc"]["x"], "y": c["loc"]["y"], "radius": 800}}, me)
	Sim.act({"a": "call_end", "id": cid}, me)
	inc = State.incidents[res["id"]]
	check(not inc["loc_fixed"], "Ungenaue Ortsangabe wird erkannt")
	Sim.act({"a": "inc_alarm", "id": inc["id"], "vehicles": Advisor.suggest(inc)["suggested"]}, me)
	run(3 * 3600.0, func(): return inc["done"])
	check(inc["done"] and Vector2(inc["x"], inc["y"]).distance_to(Vector2(tr["x"], tr["y"])) < 1.0, "Einheit lokalisiert die tatsächliche Einsatzstelle")
	# nicht angenommener Notruf
	cid = CallGen.spawn_event("med_notfall", {})
	var missed0 := int(State.meta["stats"]["calls_missed"])
	run(600.0, func(): return not State.calls.has(cid))
	check(not State.calls.has(cid) and int(State.meta["stats"]["calls_missed"]) > missed0, "Nicht angenommener Notruf: Anrufer legt auf")
	# Kräftemangel führt zu Nachforderung
	cid = CallGen.spawn_event("brand_industrie", {"variant": 1})
	Sim.act({"a": "call_take", "id": cid}, me)
	c = State.calls[cid]
	CallGen._set_loc_level(c, State.truths[c["truth"]], 2)
	res = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": "B 1", "x": c["loc"]["x"], "y": c["loc"]["y"]}}, me)
	Sim.act({"a": "call_end", "id": cid}, me)
	inc = State.incidents[res["id"]]
	Sim.act({"a": "inc_alarm", "id": inc["id"], "vehicles": Advisor.suggest(inc)["suggested"]}, me)
	run(2 * 3600.0, func():
		for vid in State.incident_vehicles(inc["id"]):
			if State.vehicles[vid]["talk"] != "":
				flags["talk"] = true
		return flags["talk"])
	check(flags["talk"] and not IL.shortage(inc["need"], IL.caps_assigned(inc["id"])).is_empty(), "Unterbesetzter Einsatz: Sprechwunsch mit Nachforderung")
	check(not Sim.act({"a": "inc_close", "id": inc["id"]}, me)["ok"], "Laufender Einsatz kann nicht einfach abgeschlossen werden")

func test_personnel_roles() -> void:
	Sim.new_game({"mode": "frei", "seed": 5})
	Sim.running = false
	State.meta["next_call"] = 1e12
	var res: Dictionary = Sim.act({"a": "inc_create", "form": {"keyword": "B 5", "x": 0.0, "y": 0.0}}, me)
	var iid: String = res["id"]
	var ids := State.station_vehicles("fw1")
	res = Sim.act({"a": "inc_alarm", "id": iid, "vehicles": ids}, me)
	check(res["alarmed"].size() < ids.size() and res["failed"].size() > 0, "Wachstärke begrenzt gleichzeitiges Ausrücken (%d von %d)" % [res["alarmed"].size(), ids.size()])
	var v: Dictionary = State.vehicles[State.station_vehicles("fw2")[0]]
	check(Sim.act({"a": "veh_status", "id": v["id"], "status": 6}, me)["ok"] and VL.block_reason(v) != "", "Status 6: Fahrzeug nicht alarmierbar")
	check(not Sim.act({"a": "inc_alarm", "id": iid, "vehicles": [v["id"]]}, me)["ok"], "Alarmierung eines nicht verfügbaren Fahrzeugs wird abgelehnt")
	var pol := {"name": "P", "role": "polizei"}
	var fw_v: String = State.station_vehicles("fw3")[1]
	var pol_v: String = State.station_vehicles("pi11")[0]
	check(not Sim.act({"a": "inc_alarm", "id": iid, "vehicles": [fw_v]}, pol)["ok"], "Rolle Polizei darf keine Feuerwehrfahrzeuge alarmieren")
	check(Sim.act({"a": "inc_alarm", "id": iid, "vehicles": [pol_v]}, pol)["ok"], "Rolle Polizei darf Polizeifahrzeuge alarmieren")
	var obs := {"name": "B", "role": "beobachter"}
	var cid := CallGen.spawn_event("med_notfall", {})
	check(not Sim.act({"a": "call_take", "id": cid}, obs)["ok"], "Beobachter darf keine Notrufe annehmen")
	check(not Sim.act({"a": "set_speed", "speed": 8.0}, pol)["ok"], "Nur Schichtführung darf Spielgeschwindigkeit ändern")
	check(not Sim.act({"a": "unbekannt"}, me)["ok"], "Unbekannte Aktion wird abgelehnt")
	Sim.act({"a": "call_take", "id": cid}, me)
	check(not Sim.act({"a": "call_ask", "id": cid, "q": "q_wo"}, {"name": "Anderer", "role": "disposition"})["ok"], "Fremder Notruf kann nicht übernommen werden")
	var e: int = World.class_edges[World.CLS_HAUPT][10]
	check(Sim.act({"a": "closure", "edge": e}, me)["ok"] and World.edge_block[e] == 1, "Straßensperrung setzen")
	check(Sim.act({"a": "closure", "edge": e}, me)["ok"] and World.edge_block[e] == 0, "Straßensperrung aufheben")

func test_management() -> void:
	Sim.new_game({"mode": "karriere", "seed": 3})
	Sim.running = false
	State.meta["next_call"] = 1e12
	check(State.stations.size() < Data.stations.size() and State.meta["zones"] == [1], "Karriere beginnt mit der Innenstadt (%d Wachen)" % State.stations.size())
	var budget := int(State.meta["budget"])
	var res: Dictionary = Sim.act({"a": "veh_buy", "station": "rw1", "type": "RTW"}, me)
	check(res["ok"] and int(State.meta["budget"]) == budget - int(Data.vehicle_types["RTW"]["price"]), "Fahrzeug beschaffen kostet Budget")
	check(not Sim.act({"a": "veh_buy", "station": "rw1", "type": "HLF20"}, me)["ok"], "Fahrzeugtyp muss zur Organisation passen")
	check(not Sim.act({"a": "zone_unlock", "zone": 2}, me)["ok"], "Region ohne Budget nicht übernehmbar")
	State.meta["budget"] = 5000000
	var n0 := State.stations.size()
	check(Sim.act({"a": "zone_unlock", "zone": 2}, me)["ok"] and State.stations.size() > n0, "Region übernehmen fügt Wachen hinzu")
	res = Sim.act({"a": "st_new", "name": "Feuerwache 11 – Test", "org": "fw", "kind": "bf", "x": 1500.0, "y": 1500.0, "slots": 3}, me)
	check(res["ok"] and State.stations.has(res["id"]), "Neuen Standort einrichten")
	var sid: String = res["id"]
	res = Sim.act({"a": "veh_buy", "station": sid, "type": "HLF20"}, me)
	check(res["ok"] and not State.stations[sid]["staff"].is_empty(), "Fahrzeug am neuen Standort inkl. Personal")
	var vid: String = res["id"]
	check(Sim.act({"a": "veh_move", "id": vid, "station": "fw1"}, me)["ok"] == (State.station_vehicles("fw1").size() <= int(State.stations["fw1"]["slots"])), "Fahrzeug verlegen (Stellplatzprüfung)")
	check(Sim.act({"a": "st_edit", "id": sid, "name": "Wache Umbenannt", "slots": 5}, me)["ok"] and State.stations[sid]["name"] == "Wache Umbenannt", "Standortdaten bearbeiten")
	var inc := {"score": 100, "prio": 1}
	var lvl := int(State.meta["level"])
	for i in 12:
		Modes.reward(inc, {"x": 1})
	check(int(State.meta["level"]) > lvl, "Erfahrung führt zu Stufenaufstieg")

func run_fast(max_sim: float, until: Callable) -> bool:
	var t := 0.0
	while t < max_sim:
		Sim.step(2.0)
		CallGen.real_tick(1.0)
		t += 2.0
		if until.call():
			return true
	return false

func test_all_types() -> void:
	var failed_types: Array = []
	var ids: Array = Data.incident_types.keys()
	for tid in ids:
		if Data.incident_types[tid].get("weight", 1.0) == 0 and not tid in ["hochwasser", "veranstaltung"]:
			continue
		for vi in Data.incident_types[tid]["variants"].size():
			Sim.new_game({"mode": "frei", "seed": 31 + vi})
			Sim.running = false
			State.meta["next_call"] = 1e12
			var cid := CallGen.spawn_event(tid, {"variant": vi})
			if not State.calls.has(cid):
				failed_types.append("%s/%d: kein Notruf" % [tid, vi])
				continue
			var c: Dictionary = State.calls[cid]
			var tr: Dictionary = State.truths[c["truth"]]
			Sim.act({"a": "call_take", "id": cid}, me)
			CallGen._set_loc_level(c, tr, 2)
			var kw := IL.correct_keyword(tr)
			if not Data.keywords.has(kw):
				failed_types.append("%s/%d: Stichwort %s unbekannt" % [tid, vi, kw])
				continue
			var r: Dictionary = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": kw, "x": c["loc"]["x"], "y": c["loc"]["y"]}}, me)
			Sim.act({"a": "call_end", "id": cid}, me)
			var inc: Dictionary = State.incidents[r["id"]]
			Sim.act({"a": "inc_alarm", "id": inc["id"], "vehicles": Advisor.suggest(inc)["suggested"]}, me)
			var done: bool = run_fast(4 * 3600.0, func():
				for vid in State.vehicles:
					if State.vehicles[vid]["talk"] != "":
						Sim.act({"a": "veh_talk", "id": vid}, me)
				if inc["revealed"] and not inc["done"] and int(State.clock) % 60 < 2:
					var sg: Array = Advisor.suggest(inc)["suggested"]
					if not sg.is_empty():
						Sim.act({"a": "inc_alarm", "id": inc["id"], "vehicles": sg}, me)
				return inc["done"])
			if not done:
				failed_types.append("%s/%d: nicht beendet (need %s, prog %.2f)" % [tid, vi, str(inc.get("need", {})), float(inc.get("progress", 0))])
			elif int(inc["score"]) < 50:
				failed_types.append("%s/%d: Bewertung nur %d" % [tid, vi, int(inc["score"])])
			Sim.act({"a": "inc_close", "id": inc["id"]}, me)
	for f in failed_types:
		print("    ", f)
	check(failed_types.is_empty(), "Alle Einsatzarten und Lagevarianten spielbar (Notruf → Alarm → Einsatzende)")

func _rth(cs: String) -> Dictionary:
	for vid in State.vehicles:
		if State.vehicles[vid]["callsign"] == cs:
			return State.vehicles[vid]
	return {}

func test_rth() -> void:
	Sim.new_game({"mode": "frei", "seed": 12, "start_hour": 13})
	Sim.running = false
	State.meta["next_call"] = 1e12
	var c1 := _rth("Christoph 1")
	var c2 := _rth("Christoph Bavaria")
	check(not c1.is_empty() and not c2.is_empty(), "Zwei Rettungshubschrauber vorhanden (Christoph 1, Christoph Bavaria)")
	check(VL.block_reason(c1) == "" and VL.block_reason(c2) == "", "Tagsüber beide Hubschrauber einsatzbereit")
	# Notfall in entlegener Gemeinde: Hubschrauber wird vorgeschlagen und fliegt direkt
	var res: Dictionary = Sim.act({"a": "inc_create", "form": {"keyword": "RD 2", "x": -11300.0, "y": 6700.0}}, me)
	var inc: Dictionary = State.incidents[res["id"]]
	var sg: Array = Advisor.suggest(inc)["suggested"]
	var heli := ""
	for vid in sg:
		if VL.is_air(State.vehicles[vid]):
			heli = vid
	check(heli != "", "Bei entlegenem Notfall wird ein Hubschrauber als Notarzt vorgeschlagen")
	if heli != "":
		Sim.act({"a": "inc_alarm", "id": inc["id"], "vehicles": sg}, me)
		var h: Dictionary = State.vehicles[heli]
		var arrived: bool = run(1800.0, func(): return h["state"] == "onscene")
		check(arrived and Vector2(h["x"], h["y"]).distance_to(Vector2(inc["x"], inc["y"])) < 5.0, "Hubschrauber fliegt direkt zur Einsatzstelle (Ankunft nach %d s)" % int(State.clock))
	# Stadtgebiet: bodengebundener Notarzt bevorzugt
	res = Sim.act({"a": "inc_create", "form": {"keyword": "RD 2", "x": 200.0, "y": 300.0}}, me)
	var city_sg: Array = Advisor.suggest(State.incidents[res["id"]])["suggested"]
	var any_air := false
	for vid in city_sg:
		if VL.is_air(State.vehicles[vid]):
			any_air = true
	check(not any_air, "In der Innenstadt wird ein bodengebundener Notarzt vorgeschlagen")
	# Nacht: Christoph 1 nicht verfügbar, Christoph Bavaria schon
	Sim.new_game({"mode": "frei", "seed": 12, "start_hour": 21})
	Sim.running = false
	State.meta["next_call"] = 1e12
	State.meta["start_unix"] = int(State.meta["start_unix"]) + 2 * 3600
	c1 = _rth("Christoph 1")
	c2 = _rth("Christoph Bavaria")
	check(VL.block_reason(c1).find("Tageslicht") >= 0 and VL.block_reason(c2) == "", "Nachts fliegt nur Christoph Bavaria (24 h)")
	State.env["weather"] = "nebel"
	check(VL.block_reason(c2).find("Wetter") >= 0, "Bei Nebel kein Flugbetrieb")

func test_gwl_modules() -> void:
	Sim.new_game({"mode": "frei", "seed": 21, "start_hour": 13})
	Sim.running = false
	State.meta["next_call"] = 1e12
	var gwl := ""
	for vid in State.vehicles:
		if State.vehicles[vid]["type"] == "GWL":
			gwl = vid
			break
	check(gwl != "", "GW-L vorhanden")
	var g: Dictionary = State.vehicles[gwl]
	check(VL.module_of(g) == "gitterbox" and int(VL.caps(g).get("logistik", 0)) == 1, "GW-L startet mit Gitterbox, Fähigkeit Logistik")
	check(Data.vehicle_types["GWL"]["modules"].size() == 7, "7 Rollcontainer wählbar")
	check(int(VL.caps_with_module(g, "hochwasser").get("pumpen", 0)) == 1 and int(VL.caps_with_module(g, "atemschutz").get("atemschutz", 0)) == 1, "Rollcontainer liefern Zusatzfähigkeiten (Pumpen, Atemschutz)")
	# Bedarf an Pumpen: Vorschlag lädt den Rollcontainer Hochwasser
	var res: Dictionary = Sim.act({"a": "inc_create", "form": {"keyword": "THL UNWETTER", "x": float(g["x"]) + 300.0, "y": float(g["y"])}}, me)
	var inc: Dictionary = State.incidents[res["id"]]
	inc["revealed"] = true
	inc["need"] = {"pumpen": 2}
	var sg: Dictionary = Advisor.suggest(inc)
	var mod_vid := ""
	for vid in sg["modules"]:
		if sg["modules"][vid] == "hochwasser":
			mod_vid = vid
	check(mod_vid != "" and sg["suggested"].has(mod_vid), "Vorschlag: GW-L mit Rollcontainer Hochwasser/Unwetter für fehlende Pumpen")
	if mod_vid != "":
		var before := State.radio.size()
		var ar: Dictionary = Sim.act({"a": "inc_alarm", "id": inc["id"], "vehicles": [mod_vid], "modules": sg["modules"]}, me)
		var v: Dictionary = State.vehicles[mod_vid]
		check(ar["ok"] and VL.module_of(v) == "hochwasser" and int(VL.caps(v).get("pumpen", 0)) == 1, "Alarmierung lädt Rollcontainer um")
		check(float(v["timer"]) >= 120.0, "Umladen verlängert die Ausrückzeit (%d s)" % int(v["timer"]))
		var said := false
		for i in range(before, State.radio.size()):
			if String(State.radio[i]["text"]).find("Hochwasser") >= 0:
				said = true
		check(said, "Funkprotokoll nennt die Beladung")
		check(not VL.set_module(v, "licht"), "Unterwegs kein Umladen möglich")
	# Feuerwehrkräne, Werkfeuerwehr, TLF-Verteilung
	var kran_st: Array = []
	var tlf_bf := 0
	for sid in State.stations:
		var st: Dictionary = State.stations[sid]
		for vid in State.station_vehicles(sid):
			var vt: String = State.vehicles[vid]["type"]
			if vt == "FWK":
				kran_st.append(sid)
			if st["kind"] == "bf" and vt.begins_with("TLF"):
				tlf_bf += 1
	kran_st.sort()
	check(kran_st == ["fw6", "fw9"], "Feuerwehrkräne an Feuerwache 6 und 9")
	check(tlf_bf == 4, "Nur 4 Berufsfeuerwehr-Wachen mit TLF")
	check(State.stations.has("werk1") and State.station_vehicles("werk1").size() >= 4, "Werkfeuerwehr vorhanden")
	var kr: Dictionary = Sim.act({"a": "inc_create", "form": {"keyword": "THL 2", "x": 0.0, "y": 0.0}}, me)
	var kinc: Dictionary = State.incidents[kr["id"]]
	kinc["revealed"] = true
	kinc["need"] = {"kran": 1}
	var ks: Array = Advisor.suggest(kinc)["suggested"]
	check(ks.size() == 1 and State.vehicles[ks[0]]["type"] == "FWK", "Bei Kranbedarf wird ein Feuerwehrkran vorgeschlagen")
	# Stichwortfarben nach Fachbereich
	check(Data.keyword_color("RD 2") == Color("#e58a2e") and Data.keyword_color("B 2") == Color("#d9534a") and Data.keyword_color("THL 4") == Color("#d9534a") and Data.keyword_color("POL 1") == Color("#5b95c8"), "Stichwortfarben: RD orange, Feuerwehr rot, Polizei blau")

func test_beta() -> void:
	const Beta = preload("res://src/core/beta.gd")
	var l := {"salt": "testsalz", "codes": {"7": ("testsalz:ABCDEFGHJKLM").sha256_text()}}
	check(Beta.check("LB-ABCD-EFGH-JKLM", l) == 7, "Gültiger Code erkennt Tester 7")
	check(Beta.check("lb abcd efgh jklm", l) == 7 and Beta.check("ABCDEFGHJKLM", l) == 7, "Schreibweise egal (klein, Leerzeichen, ohne Präfix)")
	check(Beta.check("LB-ABCD-EFGH-JKLN", l) == -1 and Beta.check("", l) == -1, "Falscher Code abgelehnt")
	var real: Dictionary = Beta._list()
	check(real.get("codes", {}).size() >= 50 and String(real.get("salt", "")).length() >= 16, "Beta-Codeliste vorhanden (nur Prüfwerte)")
	check(not Beta.is_beta(), "Normale Version verlangt keinen Code")

func test_calls_consistency() -> void:
	Sim.new_game({"mode": "frei", "seed": 44})
	Sim.running = false
	State.meta["next_call"] = 1e12
	var scripts: Dictionary = Data.call_scripts["scripts"]
	var ok := true
	for tid in ["med_notfall", "med_bewusstlos", "med_herz", "rd_kind"]:
		var cases: Array = scripts[Data.incident_types[tid]["call"]]["cases"]
		for ci in cases.size():
			var cid := CallGen.spawn_event(tid, {"case": ci, "loc_level": 2})
			var c: Dictionary = State.calls[cid]
			Sim.act({"a": "call_take", "id": cid}, me)
			Sim.act({"a": "call_ask", "id": cid, "q": "q_was"}, me)
			run(40.0, func(): return c["pending"].is_empty())
			var lines: Array = []
			for l in c["transcript"]:
				lines.append(l["text"])
			var all := "\n".join(lines)
			var tr: Dictionary = State.truths[c["truth"]]
			if all.find(cases[ci]["open"]) < 0 or all.find(String(cases[ci]["what"]).replace("{objekt}", tr["object"])) < 0:
				ok = false
				print("    Gespräch passt nicht: ", tid, " Fall ", ci)
			Sim.act({"a": "call_end", "id": cid}, me)
	check(ok, "Medizinische Notrufe: Eröffnung und Antwort auf »Was ist passiert?« passen zusammen")
	var counts := {}
	for i in 4000:
		var t := CallGen.pick_type()
		counts[t] = int(counts.get(t, 0)) + 1
	var herz := float(counts.get("med_herz", 0)) / 4000.0
	var kind := float(counts.get("rd_kind", 0)) / 4000.0
	check(herz < 0.06 and kind < 0.02, "Häufigkeit: Brustschmerz %.1f %%, Kindernotfall %.1f %%" % [herz * 100.0, kind * 100.0])

func test_tutorial() -> void:
	const Tutorial = preload("res://src/simulation/tutorial.gd")
	Sim.new_game({"mode": "einweisung", "seed": 8})
	Sim.running = false
	var tut: Dictionary = State.meta["tutorial"]
	var seen := {}
	var step_of := func(): return int(State.meta["tutorial"]["step"])
	var ok: bool = run(5 * 3600.0, func():
		seen[step_of.call()] = true
		var cid: String = tut.get("call", "")
		if State.calls.has(cid):
			var c: Dictionary = State.calls[cid]
			match step_of.call():
				1: Sim.act({"a": "call_take", "id": cid}, me)
				2: Sim.act({"a": "call_ask", "id": cid, "q": "q_wo"}, me)
				3:
					if c["pending"].is_empty():
						Sim.act({"a": "call_ask", "id": cid, "q": "q_was"}, me)
				4, 9, 10:
					if c["state"] == "ringing":
						Sim.act({"a": "call_take", "id": cid}, me)
					elif c["incident"] == "" and c["pending"].is_empty():
						if step_of.call() == 4:
							check(c.get("hint", {}).get("keyword", "") == "RD 1", "Einweisung: Stichworthinweis wird angezeigt")
						var kw: String = {4: "RD 1", 9: "B 1", 10: "B 3"}[step_of.call()]
						var r: Dictionary = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": kw, "x": c["loc"]["x"], "y": c["loc"]["y"]}}, me)
						if r.get("ok", false):
							Sim.act({"a": "inc_alarm", "id": r["id"], "vehicles": Advisor.suggest(State.incidents[r["id"]])["suggested"]}, me)
							Sim.act({"a": "call_end", "id": cid}, me)
		for vid in State.vehicles:
			if State.vehicles[vid]["talk"] != "":
				Sim.act({"a": "veh_talk", "id": vid}, me)
		var iid: String = tut.get("inc", "")
		if State.incidents.has(iid):
			var inc: Dictionary = State.incidents[iid]
			if step_of.call() == 8 and inc["done"]:
				Sim.act({"a": "inc_close", "id": iid}, me)
			if step_of.call() == 12 and inc["revealed"] and int(State.clock) % 20 == 0:
				var sg: Array = Advisor.suggest(inc)["suggested"]
				if not sg.is_empty():
					Sim.act({"a": "inc_alarm", "id": iid, "vehicles": sg}, me)
		return step_of.call() >= Tutorial.LAST)
	var all := true
	for i in range(1, Tutorial.LAST + 1):
		if not seen.has(i):
			all = false
			print("    Schritt nicht erreicht: ", i)
	check(ok and all, "Einweisung: alle %d Schritte nacheinander durchlaufen" % Tutorial.LAST)
	check(seen.has(12), "Einweisung: Nachforderung tritt auf (Schritt 12)")
	check(float(State.meta["next_call"]) < 1e11, "Nach der Einweisung startet der reguläre Notrufbetrieb")
	check(Tutorial.STEPS.size() == Tutorial.LAST + 1, "Einweisung: Text für jeden Schritt vorhanden")

func test_scenarios() -> void:
	for sc in Data.scenarios:
		Sim.new_game({"mode": "szenario", "scenario": sc["id"], "seed": 11})
		Sim.running = false
		State.meta["next_call"] = 1e12
		run(float(sc["events"][1]["t"]) + 5.0, func(): return false)
		check(State.truths.size() >= 2 and State.hour() == int(sc["start_hour"]), "Szenario »%s« erzeugt Einsatzlagen" % sc["name"])

func test_save_load() -> void:
	Sim.new_game({"mode": "frei", "seed": 21})
	Sim.running = false
	for i in 2400:
		Sim.step(0.5)
	for cid in State.calls.keys():
		Sim.act({"a": "call_take", "id": cid}, me)
		var c: Dictionary = State.calls[cid]
		if c["truth"] != "":
			Sim.act({"a": "call_create", "id": cid, "form": {"keyword": "RD 1", "x": c["loc"]["x"], "y": c["loc"]["y"]}}, me)
	for iid in State.incidents:
		Sim.act({"a": "inc_alarm", "id": iid, "vehicles": Advisor.suggest(State.incidents[iid])["suggested"]}, me)
	for i in 200:
		Sim.step(0.5)
	var snap := {"clock": State.clock, "inc": State.incidents.size(), "veh": State.vehicles.size(), "radio": State.radio.size(), "truths": State.truths.size()}
	var moving := ""
	for vid in State.vehicles:
		if State.vehicles[vid]["state"] == "enroute":
			moving = vid
	var mp := State.veh_pos(State.vehicles[moving]) if moving != "" else Vector2.ZERO
	check(SaveSystem.save("Testspielstand Automatik") == "", "Spiel speichern")
	var listed := false
	for s in SaveSystem.list():
		if s["id"] == "testspielstand_automatik":
			listed = true
	check(listed, "Spielstand erscheint in der Liste")
	State.reset()
	check(State.vehicles.is_empty(), "Zustand zurückgesetzt")
	check(Game.load_game("testspielstand_automatik") == "", "Spiel laden")
	Sim.running = false
	check(is_equal_approx(State.clock, snap["clock"]) and State.incidents.size() == snap["inc"] and State.vehicles.size() == snap["veh"] and State.truths.size() == snap["truths"], "Spielzeit, Einsätze, Fahrzeuge, Lagen wiederhergestellt")
	if moving != "":
		check(State.veh_pos(State.vehicles[moving]).distance_to(mp) < 0.01 and typeof(State.vehicles[moving]["status"]) == TYPE_INT, "Fahrzeugposition und Datentypen exakt erhalten")
		var before := State.veh_pos(State.vehicles[moving])
		for i in 40:
			Sim.step(0.5)
		check(State.veh_pos(State.vehicles[moving]).distance_to(before) > 1.0 or State.vehicles[moving]["state"] != "enroute", "Simulation läuft nach dem Laden weiter")
	SaveSystem.delete("testspielstand_automatik")
	check(not FileAccess.file_exists("user://saves/testspielstand_automatik.sav"), "Spielstand löschen")
	check(Game.load_game("gibt_es_nicht") != "", "Fehlender Spielstand wird gemeldet")
	Game.in_session = false

func test_auth() -> void:
	var salt := Auth.random_bytes(16)
	var key := Auth.derive("Geheim#112", salt)
	var hn := Auth.random_bytes(24)
	var cn := Auth.random_bytes(24)
	check(key.size() == 32 and key != "Geheim#112".to_utf8_buffer(), "Passwort wird nur als abgeleiteter Schlüssel gehalten")
	check(Auth.verify(key, hn, cn, Auth.proof(Auth.derive("Geheim#112", salt), hn, cn)), "Richtiges Passwort wird akzeptiert")
	check(not Auth.verify(key, hn, cn, Auth.proof(Auth.derive("geheim#112", salt), hn, cn)), "Falsches Passwort wird abgelehnt")
	check(not Auth.verify(key, Auth.random_bytes(24), cn, Auth.proof(key, hn, cn)), "Wiederverwendeter Nachweis (Replay) wird abgelehnt")
	check(Auth.derive("Geheim#112", Auth.random_bytes(16)) != key, "Salt verändert den Schlüssel")
