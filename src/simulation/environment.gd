extends RefCounted
## Umwelt: Tageszeit, Verkehrslage, Staus, Baustellen, Wetter, Veranstaltungen (nur Host).

static func init_new_game() -> void:
	var rng: RandomNumberGenerator = Sim.rng
	var sites := {}
	var closures := {}
	var pool: Array = []
	for cls in [World.CLS_BUNDES, World.CLS_HAUPT, World.CLS_HAUPT, World.CLS_NEBEN]:
		pool.append(World.class_edges[cls])
	for i in 16:
		var p: PackedInt32Array = pool[rng.randi() % pool.size()]
		var e := p[rng.randi() % p.size()]
		if World.edge_flags[e] != 0:
			continue
		if i < 3 and World.edge_cls[e] != World.CLS_BUNDES:
			closures[e] = "Vollsperrung wegen Bauarbeiten"
		else:
			sites[e] = "Baustelle"
	State.env["sites"] = sites
	State.env["closures"] = closures
	State.env["jams"] = {}
	State.env["events"] = []
	State.env["hour_done"] = -1
	_hourly(true)
	State.apply_env()

static func tick(_h: float) -> void:
	var hr := State.hour()
	if int(State.env.get("hour_done", -1)) != hr:
		_hourly(false)
		State.apply_env()
		State.env_changed.emit()
	var nj: float = float(State.env.get("next_jam", 0.0))
	if State.clock >= nj:
		State.env["next_jam"] = State.clock + 1200.0
		_roll_jams()
		State.apply_env()
		State.env_changed.emit()

static func _hourly(first: bool) -> void:
	var hr := State.hour()
	State.env["hour_done"] = hr
	var curve: Array = Data.modes.get("traffic_curve", [])
	State.env["traffic"] = float(curve[hr]) if curve.size() == 24 else 1.0
	var wd: Dictionary = Data.modes.get("weather", {})
	if not first and not State.meta.get("weather_lock", false):
		var cur: Dictionary = wd.get(State.env["weather"], {})
		var roll := Sim.rng.randf()
		for k in cur.get("next", {}):
			roll -= float(cur["next"][k])
			if roll <= 0.0:
				if k != State.env["weather"]:
					State.env["weather"] = k
					var nd: Dictionary = wd.get(k, {})
					Sim.radio("Leitstelle", "Wetterlage: %s." % nd.get("name", k), -1, "system", "")
					if nd.get("storm", false):
						State.notice.emit("Unwetterwarnung für das Stadtgebiet Bavaria: %s. Mit erhöhtem Einsatzaufkommen ist zu rechnen." % nd.get("name", k), "warn")
						Sim.sound("system")
				break
	# Veranstaltungen
	var events: Array = State.env.get("events", [])
	var keep: Array = []
	for ev in events:
		if float(ev.get("until", 0.0)) > State.clock:
			keep.append(ev)
		else:
			Sim.radio("Leitstelle", "Veranstaltung beendet: %s." % ev["name"], -1, "system", "")
	State.env["events"] = keep
	if not first and State.meta["mode"] != "szenario" and keep.is_empty() and hr in [11, 14, 18, 19, 20] and Sim.rng.randf() < 0.3:
		var cand: Array = []
		for p in World.pois:
			if p["kind"] in ["stadion", "messe", "veranstaltung"]:
				cand.append(p)
		if not cand.is_empty():
			var p: Dictionary = cand[Sim.rng.randi() % cand.size()]
			add_event("Veranstaltung: %s" % p["name"], p, 2.5, 3.0 * 3600.0)

static func add_event(name: String, poi: Dictionary, factor: float, duration: float) -> void:
	var d: int = World.district_at(poi["p"])
	State.env["events"].append({"name": name, "district": World.districts[d]["id"], "x": poi["p"].x, "y": poi["p"].y, "factor": factor, "until": State.clock + duration})
	Sim.radio("Leitstelle", "%s – erhöhtes Einsatzaufkommen im Bereich %s erwartet." % [name, World.districts[d]["name"]], -1, "system", "")
	State.env_changed.emit()

static func _roll_jams() -> void:
	var level: float = float(State.env.get("traffic", 1.0))
	var jams := {}
	var n := int((level - 1.0) * 45.0)
	if State.env["weather"] in ["starkregen", "sturm", "schnee"]:
		n += 8
	var rng: RandomNumberGenerator = Sim.rng
	for i in n:
		var cls: int = [World.CLS_AUTOBAHN, World.CLS_BUNDES, World.CLS_BUNDES, World.CLS_HAUPT][rng.randi() % 4]
		var pool: PackedInt32Array = World.class_edges[cls]
		var e := pool[rng.randi() % pool.size()]
		var f := rng.randf_range(1.8, 3.6)
		var node := World.edge_a[e]
		for step in rng.randi_range(2, 6):
			jams[e] = f
			var nxt := -1
			for e2 in World.node_edges[node]:
				if e2 != e and World.edge_cls[e2] == cls and not jams.has(e2):
					nxt = e2
					break
			if nxt < 0:
				break
			node = World.edge_b[nxt] if World.edge_a[nxt] == node else World.edge_a[nxt]
			e = nxt
	State.env["jams"] = jams

static func toggle_closure(e: int, by: String) -> void:
	var cl: Dictionary = State.env["closures"]
	if cl.has(e):
		cl.erase(e)
		Sim.radio("Leitstelle", "Sperrung aufgehoben: %s (%s)." % [World.street_name(e), by], -1, "system", "")
	else:
		cl[e] = "Sperrung durch Leitstelle"
		Sim.radio("Leitstelle", "Straßensperrung eingetragen: %s (%s)." % [World.street_name(e), by], -1, "system", "")
	State.apply_env()
	State.env_changed.emit()
