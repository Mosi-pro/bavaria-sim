extends RefCounted
## Notrufgenerator und Gesprächsführung (nur Host).

const IL = preload("res://src/incidents/incident_logic.gd")

static func scripts() -> Dictionary:
	return Data.call_scripts

static func _pick(arr: Array) -> String:
	if arr.is_empty():
		return ""
	return arr[Sim.rng.randi() % arr.size()]

# ---------------------------------------------------------------- Aufkommen
static func calls_per_hour() -> float:
	var m: Dictionary = Data.modes
	var diff: Dictionary = IL.difficulty()
	var mode: Dictionary = m.get("modes", {}).get(State.meta["mode"], {})
	var rate: float = float(m.get("base_calls_per_hour", 24)) * float(diff.get("call_rate", 1.0)) * float(mode.get("call_rate_mul", 1.0))
	var curve: Array = m.get("hour_curve", [])
	if curve.size() == 24:
		rate *= float(curve[State.hour()])
	rate *= float(m.get("weather", {}).get(State.env["weather"], {}).get("calls", 1.0))
	# Anteil der betreuten Bevölkerung (Karriere: freigeschaltete Regionen)
	var total := 0.0
	var mine := 0.0
	for d in World.districts:
		total += float(d["pop"])
		if _zone_ok(d):
			mine += float(d["pop"])
	rate *= clampf(mine / max(1.0, total) * 1.25, 0.15, 1.0)
	if State.meta["mode"] == "szenario":
		rate *= float(State.meta.get("background_rate", 0.5))
	if State.meta["mode"] == "karriere":
		rate *= 0.75 + 0.06 * float(State.meta["level"])
	return rate

static func _zone_ok(d: Dictionary) -> bool:
	var z := int(d.get("zone", 5))
	var zones: Array = State.meta["zones"]
	return zones.has(z) or zones.has(float(z))

static func tick(h: float) -> void:
	var next: float = float(State.meta.get("next_call", -1.0))
	if next < 0.0:
		State.meta["next_call"] = State.clock + Sim.rng.randf_range(15.0, 45.0)
	elif State.clock >= next:
		var rate := calls_per_hour()
		State.meta["next_call"] = State.clock - log(max(0.0001, Sim.rng.randf())) * 3600.0 / max(0.1, rate)
		if State.calls.size() < 12:
			if Sim.rng.randf() < 0.06:
				make_nuisance_call()
			else:
				spawn_event("")
	# Folgeanrufe (weitere Anrufer, erneute Anrufe bei nicht bedienten Notfällen)
	for tid in State.truths.keys():
		var tr: Dictionary = State.truths[tid]
		if tr["state"] != "open" or float(tr["next_call"]) <= 0.0 or State.clock < float(tr["next_call"]):
			continue
		if _has_open_call(tid):
			tr["next_call"] = State.clock + 30.0
			continue
		var bound: bool = tr["incident"] != "" and State.incidents.has(tr["incident"])
		if bound:
			if int(tr["dup_calls"]) > 0 and not tr["revealed"]:
				tr["dup_calls"] = int(tr["dup_calls"]) - 1
				make_call(tid, false)
				tr["next_call"] = State.clock + Sim.rng.randf_range(40.0, 120.0)
			else:
				tr["next_call"] = 0.0
		else:
			if int(tr["calls"]) >= 4:
				tr["state"] = "missed"
				State.meta["stats"]["calls_missed"] = int(State.meta["stats"]["calls_missed"]) + 1
				Sim.radio("Leitstelle", "Notfall in %s wurde nicht bedient (kein Einsatz angelegt)." % tr["address"], -1, "system", "")
				State.truths.erase(tid)
			else:
				make_call(tid, true)
				tr["next_call"] = State.clock + Sim.rng.randf_range(120.0, 240.0)

static func _has_open_call(tid: String) -> bool:
	for cid in State.calls:
		if State.calls[cid].get("truth", "") == tid:
			return true
	return false

# ---------------------------------------------------------------- Ereignis erzeugen
static func pick_type() -> String:
	var weights := {}
	var total := 0.0
	var night := State.hour() >= 22 or State.hour() < 5
	var weather: String = State.env["weather"]
	for id in Data.incident_types:
		var t: Dictionary = Data.incident_types[id]
		var w := float(t.get("weight", 0.0))
		if t.has("weather") and t["weather"].has(weather):
			w = max(w, 0.3) * float(t["weather"][weather])
		if night and t.has("night"):
			w *= float(t["night"])
		if w > 0.0:
			weights[id] = w
			total += w
	var roll := Sim.rng.randf() * total
	for id in weights:
		roll -= float(weights[id])
		if roll <= 0.0:
			return id
	return "med_notfall"

static func pick_district(styles: Array) -> int:
	var total := 0.0
	var cand: Array = []
	for i in World.districts.size():
		var d: Dictionary = World.districts[i]
		if not _zone_ok(d):
			continue
		if not styles.is_empty() and not styles.has(d["style"]):
			continue
		if World.district_edges[i].is_empty():
			continue
		var w := float(d["pop"])
		for ev in State.env.get("events", []):
			if ev.get("district", "") == d["id"]:
				w *= float(ev.get("factor", 2.0))
		cand.append([i, w])
		total += w
	if cand.is_empty():
		if styles.is_empty():
			return 0
		return pick_district([])
	var roll := Sim.rng.randf() * total
	for c in cand:
		roll -= float(c[1])
		if roll <= 0.0:
			return int(c[0])
	return int(cand[0][0])

static func pick_location(type_id: String, opts: Dictionary) -> Dictionary:
	var t: Dictionary = Data.incident_types[type_id]
	var loc: Dictionary = t.get("loc", {"mode": "road"})
	var rng: RandomNumberGenerator = Sim.rng
	var mode: String = loc.get("mode", "road")
	if opts.has("poi"):
		for p in World.pois:
			if p["id"] == opts["poi"]:
				return _poi_location(p)
	if opts.has("cls"):
		return _road_result(World.random_class_point(rng, int(opts["cls"])), "")
	if mode == "water" or opts.has("water"):
		var wps: Array = Data.world.get("water_points", [])
		var wp: Dictionary = wps[int(opts["water"]) % wps.size()] if opts.has("water") else wps[rng.randi() % wps.size()]
		var p := Vector2(wp["pos"][0], wp["pos"][1])
		var a := World.address_at(p)
		return {"pos": p, "node": World.access_node(p), "edge": -1, "address": "%s (nahe %s)" % [wp["name"], a["street"]], "district": a["district"], "street": a["street"], "poi": wp["name"]}
	if mode == "poi" and not opts.has("district"):
		var kinds: Array = loc.get("poi_kinds", [])
		var cand: Array = []
		for p in World.pois:
			if kinds.has(p["kind"]) and _zone_ok(World.districts[World.district_at(p["p"])]):
				cand.append(p)
		for hsp in Sim.hospitals:
			if kinds.has("klinik"):
				cand.append({"id": hsp["id"], "name": hsp["name"], "kind": "klinik", "p": hsp["p"], "node": hsp["node"]})
		if not cand.is_empty():
			return _poi_location(cand[rng.randi() % cand.size()])
	var d := -1
	if opts.has("district"):
		d = World.district_index(opts["district"])
	if d < 0:
		d = pick_district(loc.get("styles", []))
	var classes: Array = []
	for c in loc.get("classes", []):
		classes.append(int(c))
	if classes.has(0) and rng.randf() < 0.14 and not opts.has("district"):
		return _road_result(World.random_class_point(rng, 0), "")
	classes.erase(0)
	return _road_result(World.random_road_point(rng, d, classes), "")

static func _road_result(r: Dictionary, poi: String) -> Dictionary:
	if r.is_empty():
		r = World.random_road_point(Sim.rng, 0, [])
	var a := World.address_at(r["pos"])
	return {"pos": r["pos"], "node": r["node"], "edge": r["edge"], "address": a["text"], "district": a["district"], "street": a["street"], "poi": poi}

static func _poi_location(p: Dictionary) -> Dictionary:
	var pos: Vector2 = p["p"] + Vector2(Sim.rng.randf_range(-25, 25), Sim.rng.randf_range(-25, 25))
	var a := World.address_at(pos)
	return {"pos": pos, "node": int(p["node"]), "edge": a["edge"], "address": "%s, %s" % [p["name"], a["text"]], "district": a["district"], "street": a["street"], "poi": p["name"]}

## Erzeugt ein Schadensereignis samt erstem Notruf. Rückgabe: Notruf-ID.
static func spawn_event(type_id: String, opts: Dictionary = {}) -> String:
	if type_id == "":
		type_id = pick_type()
	var loc := pick_location(type_id, opts)
	var tid := IL.make_truth(type_id, loc, int(opts.get("variant", -1)))
	var tr: Dictionary = State.truths[tid]
	tr["next_call"] = State.clock + Sim.rng.randf_range(35.0, 90.0)
	return make_call(tid, false)

# ---------------------------------------------------------------- Notruf
static func _caller(persona_forced: String) -> Dictionary:
	var n: Dictionary = Data.names
	var rng: RandomNumberGenerator = Sim.rng
	var female := rng.randf() < 0.5
	var first: Array = n.get("first_f" if female else "first_m", ["Alex"])
	var last: Array = n.get("last", ["Muster"])
	var mobile := rng.randf() < 0.72
	var phone := ""
	if mobile:
		var pre: Array = n.get("prefix_mobile", ["0170"])
		phone = "%s 555%04d" % [pre[rng.randi() % pre.size()], rng.randi() % 10000]
	else:
		phone = "%s 55%05d" % [n.get("prefix_land", "0855"), rng.randi() % 100000]
	var personas: Dictionary = scripts().get("personas", {})
	var persona := persona_forced
	if persona == "" or not personas.has(persona):
		var total := 0.0
		for k in personas:
			total += float(personas[k]["weight"])
		var roll := rng.randf() * total
		for k in personas:
			roll -= float(personas[k]["weight"])
			if roll <= 0.0:
				persona = k
				break
	return {"name": "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]], "phone": phone, "mobile": mobile, "persona": persona}

static func _new_call(caller: Dictionary) -> Dictionary:
	var id := "c%d" % State.next_id("call")
	var diff: Dictionary = IL.difficulty()
	var c := {
		"id": id, "t": State.clock, "state": "ringing", "caller": caller, "line": "112", "truth": "", "nuisance": "",
		"loc_level": -1, "loc": {}, "known": {}, "transcript": [], "pending": [], "asked": {}, "taken_by": "", "t_taken": -1.0,
		"wait": 0.0, "talk": 0.0, "patience": float(diff.get("patience", 75)) * Sim.rng.randf_range(0.8, 1.3), "calm": false,
		"incident": "", "aml": "", "recall": false,
	}
	State.calls[id] = c
	State.meta["stats"]["calls"] = int(State.meta["stats"]["calls"]) + 1
	return c

static func make_call(tid: String, recall: bool) -> String:
	var tr: Dictionary = State.truths[tid]
	var t: Dictionary = Data.incident_types[tr["type"]]
	var script: Dictionary = scripts().get("scripts", {}).get(t.get("call", ""), {})
	var caller := _caller("panisch" if recall and Sim.rng.randf() < 0.6 else String(script.get("persona", "")))
	var c := _new_call(caller)
	c["truth"] = tid
	c["recall"] = recall
	tr["calls"] = int(tr["calls"]) + 1
	var diff: Dictionary = IL.difficulty()
	var persona: Dictionary = scripts()["personas"][caller["persona"]]
	var vague: float = float(diff.get("vague", 0.3)) * float(persona.get("vague_mul", 1.0))
	var level := 2
	if not script.get("exact", false) and tr["poi"] == "":
		var roll := Sim.rng.randf()
		if roll < vague * 0.45:
			level = 0
		elif roll < vague:
			level = 1
	c["true_pos"] = [tr["x"], tr["y"]]
	_set_loc_level(c, tr, level)
	var prefix := _pick(persona.get("prefix", [""]))
	var open := _pick(script.get("open", ["Ich brauche Hilfe!"]))
	if recall:
		open = _pick(["Ich habe schon einmal angerufen! Wo bleibt denn die Hilfe?! ", "Hallo?! Hier ist immer noch niemand gekommen! ", "Es wird immer schlimmer, bitte beeilen Sie sich! "]) + open
	c["pending"] = [
		{"d": 0.4, "who": "D", "text": scripts().get("greeting", "Notruf, wo ist der Notfallort?")},
		{"d": 1.6, "who": "A", "text": prefix + open},
		{"d": 3.4, "who": "A", "text": _loc_phrase(c, tr)},
	]
	Sim.sound("phone")
	State.touch_call(c["id"])
	return c["id"]

static func make_nuisance_call() -> String:
	var list: Array = scripts().get("nuisance", [])
	if list.is_empty():
		return ""
	var n: Dictionary = list[Sim.rng.randi() % list.size()]
	var c := _new_call(_caller("ruhig"))
	c["nuisance"] = n["id"]
	var d := pick_district([])
	var r := World.random_road_point(Sim.rng, d, [])
	c["true_pos"] = [r["pos"].x, r["pos"].y]
	c["loc_level"] = 0
	c["loc"] = {"x": r["pos"].x, "y": r["pos"].y, "r": 900.0, "text": "Funkzelle %s (ungenau)" % World.districts[d]["name"]}
	c["pending"] = [
		{"d": 0.4, "who": "D", "text": scripts().get("greeting", "")},
		{"d": 1.8, "who": "A", "text": _pick(n["open"])},
	]
	Sim.sound("phone")
	State.touch_call(c["id"])
	return c["id"]

static func _set_loc_level(c: Dictionary, tr: Dictionary, level: int) -> void:
	c["loc_level"] = level
	var p := Vector2(tr["x"], tr["y"])
	if level >= 2:
		c["loc"] = {"x": p.x, "y": p.y, "r": 0.0, "text": tr["address"]}
	elif level == 1:
		var ne := World.nearest_edge(p, 600.0)
		var q := p
		if not ne.is_empty():
			q = World.edge_point(int(ne["edge"]), 0.5)
			var off := q.distance_to(p)
			if off < 60.0:
				q += (q - p).normalized() * 60.0 if off > 1.0 else Vector2(70, 0)
		c["loc"] = {"x": q.x, "y": q.y, "r": 180.0, "text": "%s, %s (Hausnummer unbekannt)" % [tr["street"], tr["district"]]}
	else:
		var q := p + Vector2.from_angle(Sim.rng.randf() * TAU) * Sim.rng.randf_range(250.0, 600.0)
		c["loc"] = {"x": q.x, "y": q.y, "r": 800.0, "text": "%s (genauer Ort unbekannt)" % tr["district"]}

static func _fmt(text: String, c: Dictionary, tr: Dictionary) -> String:
	var n := 0
	for p in tr.get("patients", []):
		n += 1
	return text.format({
		"objekt": tr.get("object", ""), "n": n, "stadtteil": tr.get("district", ""), "strasse": tr.get("street", ""),
		"adresse": tr.get("address", ""), "name": c["caller"]["name"], "telefon": c["caller"]["phone"],
	})

static func _loc_phrase(c: Dictionary, tr: Dictionary) -> String:
	var g: Dictionary = scripts().get("generic", {})
	var key: String = ["loc_vague", "loc_street", "loc_exact"][clampi(int(c["loc_level"]), 0, 2)]
	return _fmt(_pick(g.get(key, ["..."])), c, tr)

# ---------------------------------------------------------------- Gesprächsführung
static func take(c: Dictionary, by: String) -> String:
	if c["state"] != "ringing":
		return "Notruf wird bereits bearbeitet."
	c["state"] = "active"
	c["taken_by"] = by
	c["t_taken"] = State.clock
	Sim.radio("Leitstelle", "Notruf %s angenommen (%s, Wartezeit %d s)." % [c["line"], by, int(c["wait"])], -1, "system", "")
	State.touch_call(c["id"])
	return ""

static func ask(c: Dictionary, q: String) -> String:
	if c["state"] != "active":
		return "Kein aktives Gespräch."
	var qs: Dictionary = scripts().get("questions", {})
	if not qs.has(q):
		return "Unbekannte Rückfrage."
	var g: Dictionary = scripts().get("generic", {})
	var asked := int(c["asked"].get(q, 0))
	c["asked"][q] = asked + 1
	var answer := ""
	var tr: Dictionary = State.truths.get(c["truth"], {})
	if c["nuisance"] != "" or tr.is_empty():
		var list: Array = scripts().get("nuisance", [])
		answer = "..."
		for n in list:
			if n["id"] == c["nuisance"]:
				answer = _pick(n["answers"])
		if q == "q_rueckruf" and c["nuisance"] != "hosentasche":
			answer = _fmt(_pick(g.get("callback", [""])), c, {})
			c["known"]["callback"] = "%s, %s" % [c["caller"]["name"], c["caller"]["phone"]]
	else:
		var t: Dictionary = Data.incident_types[tr["type"]]
		var script: Dictionary = scripts().get("scripts", {}).get(t.get("call", ""), {})
		var persona: Dictionary = scripts()["personas"][c["caller"]["persona"]]
		var unsure: float = float(IL.difficulty().get("panic", 0.3)) * float(persona.get("vague_mul", 1.0)) * (0.3 if c["calm"] else 1.0)
		if asked > 0:
			unsure *= 0.3
		match q:
			"q_wo":
				if int(c["loc_level"]) < 2 and Sim.rng.randf() > unsure * 0.8:
					_set_loc_level(c, tr, int(c["loc_level"]) + 1)
				answer = _loc_phrase(c, tr)
			"q_was":
				answer = _fmt(_pick(script.get("what", ["Das habe ich doch gesagt!"])), c, tr)
				c["known"]["what"] = answer
			"q_personen":
				if Sim.rng.randf() < unsure * 0.6:
					answer = _pick(g.get("dontknow", ["Weiß ich nicht."]))
				else:
					var n: int = tr["patients"].size()
					if n == 0:
						answer = _pick(g.get("persons0", [""]))
					elif script.get("many", false):
						answer = _fmt(_pick(g.get("persons_many", [""])), c, tr)
					else:
						answer = _fmt(_pick(g.get("persons", [""])), c, tr)
					c["known"]["persons"] = answer
			"q_gefahr":
				if Sim.rng.randf() < unsure * 0.5:
					answer = _pick(g.get("dontknow", ["Weiß ich nicht."]))
				else:
					var danger: String = script.get("danger", "maybe")
					var yes := danger == "yes"
					if danger == "maybe":
						yes = float(tr["gate"]) > 0.0
						for p in tr["patients"]:
							if int(p["sev"]) >= 3:
								yes = true
					answer = _pick(g.get("danger_yes" if yes else "danger_no", [""]))
					c["known"]["danger"] = answer
			"q_zustand":
				var maxsev := -1
				for p in tr["patients"]:
					maxsev = max(maxsev, int(p["sev"]))
				var cat: String = t.get("cat", "")
				if maxsev < 1 or not (cat in ["rd", "vu", "thl"]):
					answer = _pick(g.get("zustand_na", [""]))
				elif Sim.rng.randf() < unsure * 0.4:
					answer = _pick(g.get("dontknow", [""]))
				else:
					answer = _pick(g.get("zustand%d" % clampi(maxsev, 1, 4), [""]))
					c["known"]["zustand"] = answer
			"q_rueckruf":
				answer = _fmt(_pick(g.get("callback", [""])), c, tr)
				c["known"]["callback"] = "%s, %s" % [c["caller"]["name"], c["caller"]["phone"]]
			"q_beruhigen":
				c["calm"] = true
				answer = _pick(g.get("calmed", ["Okay."]))
	c["pending"].append({"d": 0.1, "who": "D", "text": qs[q]["text"]})
	c["pending"].append({"d": Sim.rng.randf_range(1.2, 2.4), "who": "A", "text": answer})
	State.touch_call(c["id"])
	return ""

## Mobilfunk-Standortdaten (AML) abfragen.
static func locate(c: Dictionary) -> String:
	if c["state"] != "active":
		return "Kein aktives Gespräch."
	if c["aml"] != "":
		return "Standortabfrage wurde bereits durchgeführt."
	if not c["caller"]["mobile"]:
		c["aml"] = "festnetz"
		c["pending"].append({"d": 1.0, "who": "S", "text": "Festnetzanschluss – keine Mobilfunk-Standortdaten. Anschlussinhaberabfrage nicht verfügbar."})
		State.touch_call(c["id"])
		return ""
	var tr: Dictionary = State.truths.get(c["truth"], {})
	if Sim.rng.randf() < 0.7:
		c["aml"] = "ok"
		if not tr.is_empty():
			c["pending"].append({"d": 3.0, "who": "S", "text": "AML-Standortdaten empfangen (Genauigkeit ±20 m): %s" % tr["address"], "loc": 2})
		else:
			var tp: Array = c["true_pos"]
			var a := World.address_at(Vector2(tp[0], tp[1]))
			c["pending"].append({"d": 3.0, "who": "S", "text": "AML-Standortdaten empfangen (Genauigkeit ±20 m): %s" % a["text"], "locxy": [tp[0], tp[1], a["text"]]})
	else:
		c["aml"] = "fail"
		c["pending"].append({"d": 3.0, "who": "S", "text": "Keine AML-Standortdaten verfügbar (nur Funkzelle)."})
	State.touch_call(c["id"])
	return ""

static func end_call(c: Dictionary, reason: String) -> void:
	var tr: Dictionary = State.truths.get(c["truth"], {})
	if c["nuisance"] != "":
		State.meta["stats"]["calls_nuisance"] = int(State.meta["stats"]["calls_nuisance"]) + 1
	elif not tr.is_empty() and tr["incident"] == "" and c["incident"] == "":
		# echter Notfall ohne Einsatz beendet → Anrufer meldet sich erneut
		tr["next_call"] = State.clock + Sim.rng.randf_range(60.0, 150.0)
	State.remove_call(c["id"])

## Echtzeit-Fortschritt: Klingeldauer, Gesprächsdauer, Gesprächszeilen.
static func real_tick(delta: float) -> void:
	for cid in State.calls.keys():
		var c: Dictionary = State.calls[cid]
		if c["state"] == "ringing":
			c["wait"] = float(c["wait"]) + delta
			if float(c["wait"]) > float(c["patience"]):
				Sim.radio("Leitstelle", "Notruf nicht angenommen – Anrufer hat nach %d s aufgelegt." % int(c["wait"]), -1, "system", "")
				State.meta["stats"]["calls_missed"] = int(State.meta["stats"]["calls_missed"]) + 1
				var tr: Dictionary = State.truths.get(c["truth"], {})
				if not tr.is_empty():
					tr["next_call"] = State.clock + Sim.rng.randf_range(45.0, 120.0)
				State.remove_call(cid)
		elif c["state"] == "active":
			c["talk"] = float(c["talk"]) + delta
			var pending: Array = c["pending"]
			if pending.size() > 0:
				pending[0]["d"] = float(pending[0]["d"]) - delta
				if float(pending[0]["d"]) <= 0.0:
					var line: Dictionary = pending.pop_front()
					c["transcript"].append({"who": line["who"], "text": line["text"], "t": State.clock})
					if line.has("loc"):
						var tr: Dictionary = State.truths.get(c["truth"], {})
						if not tr.is_empty():
							_set_loc_level(c, tr, int(line["loc"]))
					if line.has("locxy"):
						c["loc"] = {"x": line["locxy"][0], "y": line["locxy"][1], "r": 0.0, "text": line["locxy"][2]}
						c["loc_level"] = 2
					if line["who"] == "A":
						Sim.sound("voice")
					State.touch_call(cid)
