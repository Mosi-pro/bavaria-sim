extends Node
## Autoritative Simulation. Läuft im Einzelspiel lokal und im Mehrspielermodus
## ausschließlich auf dem PC des Hosts. Clients senden nur Aktionen (act()).

const VL = preload("res://src/vehicles/vehicle_logic.gd")
const IL = preload("res://src/incidents/incident_logic.gd")
const CallGen = preload("res://src/incidents/call_generator.gd")
const Advisor = preload("res://src/dispatch/advisor.gd")
const StationLogic = preload("res://src/stations/station_logic.gd")
const Personnel = preload("res://src/personnel/personnel.gd")
const Env = preload("res://src/simulation/environment.gd")
const Modes = preload("res://src/simulation/modes.gd")

signal sound_requested(name)
signal autosave_due

var rng := RandomNumberGenerator.new()
var running := false
var hospitals: Array = []
var _autosave_t := 0.0

func sound(name: String) -> void:
	sound_requested.emit(name)

func radio(src: String, text: String, status := -1, kind := "funk", inc := "") -> void:
	State.add_radio({"t": State.clock, "src": src, "text": text, "status": status, "kind": kind, "inc": inc})

func _build_hospitals() -> void:
	hospitals = []
	for h in Data.hospitals:
		var p := Vector2(h["pos"][0], h["pos"][1])
		hospitals.append({"id": h["id"], "name": h["name"], "p": p, "node": World.nearest_node(p), "level": int(h["level"]), "beds": int(h["beds"])})

func choose_hospital(pos: Vector2, sev: int) -> Dictionary:
	var min_level := 2 if sev >= 3 else 1
	var best := {}
	var bd := INF
	for h in hospitals:
		if int(h["level"]) < min_level:
			continue
		var d: float = pos.distance_to(h["p"])
		if d < bd:
			bd = d
			best = h
	return best

# ---------------------------------------------------------------- Spielstart
func new_game(opts: Dictionary) -> void:
	World.ensure_built()
	State.reset()
	if opts.has("seed"):
		rng.seed = int(opts["seed"])
	else:
		rng.randomize()
	_build_hospitals()
	var mode: String = opts.get("mode", "frei")
	var md: Dictionary = Data.modes.get("modes", {}).get(mode, {})
	var m: Dictionary = State.meta
	m["mode"] = mode
	m["difficulty"] = opts.get("difficulty", "mittel")
	m["name"] = opts.get("name", "Neue Schicht")
	m["speed"] = float(opts.get("speed", md.get("speed", 2)))
	m["budget"] = int(md.get("budget", 0))
	var start_hour := int(opts.get("start_hour", 7))
	if mode == "szenario":
		m["scenario"] = opts.get("scenario", "")
		var sc := Modes.scenario()
		start_hour = int(sc.get("start_hour", 12))
		m["background_rate"] = float(sc.get("background_rate", 0.5))
		m["weather_lock"] = sc.get("weather_lock", false)
		State.env["weather"] = sc.get("weather", "klar")
	if mode == "karriere":
		m["zones"] = [1]
		m["orgs"] = Modes.orgs_for_level(1)
	var now := Time.get_datetime_dict_from_system()
	now["hour"] = start_hour
	now["minute"] = 30 if mode != "szenario" else 0
	now["second"] = 0
	m["start_unix"] = Time.get_unix_time_from_datetime_dict(now)
	StationLogic.init_from_data()
	Env.init_new_game()
	if md.has("oos_chance"):
		for vid in State.vehicles:
			if rng.randf() < float(md["oos_chance"]):
				State.vehicles[vid]["state"] = "oos"
				State.vehicles[vid]["status"] = 6
	if mode == "szenario":
		var sc := Modes.scenario()
		if sc.has("city_event"):
			for p in World.pois:
				if p["id"] == sc["city_event"]["poi"]:
					Env.add_event(sc["city_event"]["name"], p, float(sc["city_event"].get("factor", 3.0)), float(sc.get("duration", 7200)))
	State.active = true
	running = true
	_autosave_t = 0.0
	radio("Leitstelle", "Integrierte Leitstelle Bavaria – Schichtbeginn. %d Wachen, %d Einsatzmittel im Zuständigkeitsbereich." % [State.stations.size(), State.vehicles.size()], -1, "system", "")
	State.reset_done.emit()

func resume_loaded() -> void:
	World.ensure_built()
	_build_hospitals()
	running = true
	_autosave_t = 0.0

func stop() -> void:
	running = false

func _process(delta: float) -> void:
	if not running or not State.active:
		return
	if State.meta["paused"]:
		return
	CallGen.real_tick(delta)
	var dt: float = min(delta, 0.25) * float(State.meta["speed"])
	var steps := int(ceil(dt / 0.5))
	var h := dt / steps
	for i in steps:
		step(h)
	if Settings.get_v("game", "autosave"):
		_autosave_t += delta
		if _autosave_t >= float(Settings.get_v("game", "autosave_min")) * 60.0:
			_autosave_t = 0.0
			autosave_due.emit()

func step(h: float) -> void:
	State.clock += h
	Env.tick(h)
	CallGen.tick(h)
	VL.tick(h)
	IL.tick(h)
	Modes.tick(h)

func on_incident_finished(inc: Dictionary, tr: Dictionary) -> void:
	Modes.reward(inc, tr)

# ---------------------------------------------------------------- Aktionen
func _role(player: Dictionary) -> Dictionary:
	return Data.roles.get(player.get("role", "beobachter"), {})

func _err(text: String) -> Dictionary:
	return {"ok": false, "err": text}

## Führt eine Spieleraktion aus. Jede Aktion wird gegen Rolle und Spielzustand geprüft.
func act(a: Dictionary, player: Dictionary) -> Dictionary:
	if not State.active:
		return _err("Keine laufende Sitzung.")
	var role := _role(player)
	var who: String = player.get("name", "?")
	var kind: String = a.get("a", "")
	match kind:
		"call_take", "call_ask", "call_locate", "call_end", "call_create", "call_attach":
			if not role.get("calls", false):
				return _err("Ihre Rolle darf keine Notrufe bearbeiten.")
			var cid: String = a.get("id", "")
			if not State.calls.has(cid):
				return _err("Notruf nicht mehr vorhanden.")
			var c: Dictionary = State.calls[cid]
			if kind != "call_take" and c["taken_by"] != who:
				return _err("Der Notruf wird von %s bearbeitet." % c["taken_by"])
			match kind:
				"call_take":
					var e := CallGen.take(c, who)
					return _err(e) if e != "" else {"ok": true}
				"call_ask":
					var e := CallGen.ask(c, a.get("q", ""))
					return _err(e) if e != "" else {"ok": true}
				"call_locate":
					var e := CallGen.locate(c)
					return _err(e) if e != "" else {"ok": true}
				"call_end":
					CallGen.end_call(c, a.get("reason", ""))
					return {"ok": true}
				"call_create":
					var form: Dictionary = a.get("form", {})
					if not Data.keywords.has(form.get("keyword", "")):
						return _err("Bitte ein Einsatzstichwort wählen.")
					if not form.has("x"):
						return _err("Einsatzort fehlt.")
					var id := IL.create_incident(form, cid, who)
					return {"ok": true, "id": id}
				"call_attach":
					var iid: String = a.get("incident", "")
					if not State.incidents.has(iid):
						return _err("Einsatz nicht vorhanden.")
					IL.add_note(State.incidents[iid], who, "Weiterer Anrufer: %s, Tel. %s" % [c["caller"]["name"], c["caller"]["phone"]])
					c["incident"] = iid
					CallGen.end_call(c, "dublette")
					return {"ok": true}
		"inc_create":
			if not role.get("incidents", false):
				return _err("Ihre Rolle darf keine Einsätze anlegen.")
			var form: Dictionary = a.get("form", {})
			if not Data.keywords.has(form.get("keyword", "")) or not form.has("x"):
				return _err("Stichwort und Einsatzort sind erforderlich.")
			return {"ok": true, "id": IL.create_incident(form, "", who)}
		"inc_edit", "inc_note", "inc_alarm", "inc_close", "inc_open":
			if not role.get("incidents", false):
				return _err("Ihre Rolle darf keine Einsätze bearbeiten.")
			var iid: String = a.get("id", "")
			if not State.incidents.has(iid):
				return _err("Einsatz nicht mehr vorhanden.")
			var inc: Dictionary = State.incidents[iid]
			match kind:
				"inc_open":
					if not inc.get("opened", false):
						inc["opened"] = true
						State.touch_incident(iid)
					return {"ok": true}
				"inc_edit":
					var f: Dictionary = a.get("form", {})
					for k in ["keyword", "object", "persons", "danger", "info", "prio"]:
						if f.has(k):
							inc[k] = f[k]
					if f.has("x") and not inc["revealed"]:
						var p := Vector2(float(f["x"]), float(f["y"]))
						inc["x"] = p.x
						inc["y"] = p.y
						inc["node"] = World.access_node(p)
						inc["address"] = f.get("address", World.address_at(p)["text"])
						inc["radius"] = float(f.get("radius", 0.0))
						var tr: Dictionary = State.truths.get(inc["truth"], {})
						if not tr.is_empty():
							inc["loc_fixed"] = p.distance_to(Vector2(tr["x"], tr["y"])) <= 130.0
						for vid in State.incident_vehicles(iid):
							if State.vehicles[vid]["state"] == "enroute":
								VL.redirect_to_incident(State.vehicles[vid])
					radio("Leitstelle", "Einsatz %s geändert (%s): %s, %s" % [inc["nr"], who, inc["keyword"], inc["address"]], -1, "system", iid)
					State.touch_incident(iid)
					return {"ok": true}
				"inc_note":
					var text: String = String(a.get("text", "")).strip_edges()
					if text == "":
						return _err("Leere Notiz.")
					IL.add_note(inc, who, text.substr(0, 400))
					return {"ok": true}
				"inc_alarm":
					if inc["done"]:
						return _err("Einsatz ist bereits beendet.")
					var orgs: Array = role.get("orgs", [])
					var ids: Array = []
					var denied: Array = []
					for vid in a.get("vehicles", []):
						if not State.vehicles.has(vid):
							continue
						if orgs.has(State.vehicles[vid]["org"]):
							ids.append(vid)
						else:
							denied.append("%s: keine Berechtigung für %s" % [State.vehicles[vid]["callsign"], Data.org_name(State.vehicles[vid]["org"])])
					var res := IL.alarm(inc, ids, who)
					res["failed"].append_array(denied)
					return {"ok": res["ok"].size() > 0, "err": "\n".join(res["failed"]), "alarmed": res["ok"], "failed": res["failed"]}
				"inc_close":
					var e := IL.close_incident(inc, who)
					return _err(e) if e != "" else {"ok": true}
		"veh_recall", "veh_status", "veh_talk", "veh_msg":
			var vid: String = a.get("id", "")
			if not State.vehicles.has(vid):
				return _err("Fahrzeug nicht vorhanden.")
			var v: Dictionary = State.vehicles[vid]
			if not role.get("orgs", []).has(v["org"]):
				return _err("Keine Berechtigung für %s." % Data.org_name(v["org"]))
			match kind:
				"veh_recall":
					if v["incident"] == "":
						return _err("Fahrzeug ist keinem Einsatz zugeordnet.")
					radio("Leitstelle", "%s: Einsatzabbruch, rücken Sie ein." % v["callsign"], -1, "funk", v["incident"])
					VL.send_home(v)
					return {"ok": true}
				"veh_status":
					var e := VL.set_oos(v, int(a.get("status", 6)) == 6)
					return _err(e) if e != "" else {"ok": true}
				"veh_talk":
					VL.ack_talk(v, who)
					return {"ok": true}
				"veh_msg":
					var text: String = String(a.get("text", "")).strip_edges().substr(0, 300)
					if text == "":
						return _err("Leere Nachricht.")
					radio("Leitstelle", "An %s: %s" % [v["callsign"], text], -1, "text", v["incident"])
					radio(v["callsign"], "Verstanden.", -1, "funk", v["incident"])
					return {"ok": true}
		"st_new", "st_edit", "st_delete", "veh_buy", "veh_sell", "veh_move", "zone_unlock", "set_speed", "pause", "closure":
			if not role.get("manage", false):
				return _err("Nur die Schichtführung darf diese Funktion ausführen.")
			return _manage(kind, a, who)
		"chat":
			var text: String = String(a.get("text", "")).strip_edges().substr(0, 400)
			if text != "":
				State.add_chat({"t": State.clock, "who": who, "text": text})
			return {"ok": true}
		"msg":
			var text: String = String(a.get("text", "")).strip_edges().substr(0, 400)
			if text != "":
				radio(who, text, -1, "text", "")
			return {"ok": true}
	return _err("Unbekannte Aktion: %s" % kind)

func _manage(kind: String, a: Dictionary, who: String) -> Dictionary:
	var car: Dictionary = Modes.career()
	match kind:
		"set_speed":
			State.meta["speed"] = clampf(float(a.get("speed", 1.0)), 0.5, 8.0)
			State.meta_changed.emit()
		"pause":
			State.meta["paused"] = bool(a.get("paused", false))
			State.meta_changed.emit()
		"closure":
			var e := int(a.get("edge", -1))
			if e < 0 or e >= World.edge_a.size():
				return _err("Ungültiger Straßenabschnitt.")
			Env.toggle_closure(e, who)
		"zone_unlock":
			var err := Modes.unlock_zone(int(a.get("zone", 0)))
			if err != "":
				return _err(err)
		"st_new":
			var org: String = a.get("org", "")
			if not Data.organisations.has(org) or not State.meta["orgs"].has(org):
				return _err("Organisation nicht verfügbar.")
			var cost := int(car.get("station_cost", 0))
			if not Modes.can_afford(cost):
				return _err("Budget nicht ausreichend (%s €)." % Modes._money(cost))
			var name: String = String(a.get("name", "")).strip_edges()
			if name == "":
				return _err("Bitte einen Namen angeben.")
			var p := Vector2(float(a.get("x", 0)), float(a.get("y", 0)))
			if not World.bounds.has_point(p):
				return _err("Position außerhalb der Karte.")
			Modes.pay(cost)
			var id := StationLogic.new_station(name.substr(0, 60), org, a.get("kind", "bf"), p, clampi(int(a.get("slots", 4)), 1, 12))
			radio("Leitstelle", "Neuer Standort eingerichtet: %s." % name, -1, "system", "")
			return {"ok": true, "id": id}
		"st_edit":
			var sid: String = a.get("id", "")
			if not State.stations.has(sid):
				return _err("Wache nicht vorhanden.")
			var st: Dictionary = State.stations[sid]
			if a.has("slots"):
				var ns := clampi(int(a["slots"]), State.station_vehicles(sid).size(), 14)
				var add: int = max(0, ns - int(st["slots"]))
				var cost := add * int(car.get("slot_cost", 0))
				if not Modes.can_afford(cost):
					return _err("Budget nicht ausreichend (%s €)." % Modes._money(cost))
				Modes.pay(cost)
				st["slots"] = ns
			if a.has("name") and String(a["name"]).strip_edges() != "":
				st["name"] = String(a["name"]).strip_edges().substr(0, 60)
			if a.has("address") and String(a["address"]).strip_edges() != "":
				st["address"] = String(a["address"]).strip_edges().substr(0, 100)
			State.touch_station(sid)
		"st_delete":
			var sid: String = a.get("id", "")
			if not State.stations.has(sid):
				return _err("Wache nicht vorhanden.")
			var err := StationLogic.remove_station(sid)
			if err != "":
				return _err(err)
		"veh_buy":
			var sid: String = a.get("station", "")
			var type_id: String = a.get("type", "")
			if not State.stations.has(sid) or not Data.vehicle_types.has(type_id):
				return _err("Ungültige Angaben.")
			var t: Dictionary = Data.vehicle_types[type_id]
			if t["org"] != State.stations[sid]["org"]:
				return _err("Fahrzeugtyp passt nicht zur Organisation der Wache.")
			if StationLogic.free_slots(sid) <= 0:
				return _err("Kein freier Stellplatz.")
			var cost := int(t.get("price", 0))
			if not Modes.can_afford(cost):
				return _err("Budget nicht ausreichend (%s €)." % Modes._money(cost))
			Modes.pay(cost)
			var vid := StationLogic.add_vehicle(sid, type_id)
			State.stations[sid]["staff"] = Personnel.compute_staff(sid)
			State.touch_station(sid)
			radio("Leitstelle", "Neues Einsatzmittel in Dienst gestellt: %s (%s)." % [State.vehicles[vid]["callsign"], t["short"]], -1, "system", "")
			return {"ok": true, "id": vid}
		"veh_sell":
			var vid: String = a.get("id", "")
			if not State.vehicles.has(vid):
				return _err("Fahrzeug nicht vorhanden.")
			var price := int(Data.vehicle_types[State.vehicles[vid]["type"]].get("price", 0))
			var err := StationLogic.remove_vehicle(vid)
			if err != "":
				return _err(err)
			Modes.pay(-int(price * 0.5))
		"veh_move":
			var vid: String = a.get("id", "")
			var sid: String = a.get("station", "")
			if not State.vehicles.has(vid) or not State.stations.has(sid):
				return _err("Ungültige Angaben.")
			var err := StationLogic.move_vehicle(vid, sid)
			if err != "":
				return _err(err)
	return {"ok": true}
