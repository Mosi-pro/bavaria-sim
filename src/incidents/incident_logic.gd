extends RefCounted
## Einsatzsimulation (nur Host). Jede Lage ("truth") besitzt taktischen Kräftebedarf,
## Arbeitsumfang, Patienten und mögliche Lageentwicklungen. Der Einsatz, den der
## Disponent anlegt, wird beim Eintreffen der ersten Einheit mit der Lage abgeglichen.

const VL = preload("res://src/vehicles/vehicle_logic.gd")

const MEDICAL := ["rtw", "notarzt", "ktw"]
const CARE_TIME := [150.0, 360.0, 540.0, 780.0, 1100.0]
const STATUS_NAMES := {
	"neu": "Neu", "in_bearbeitung": "In Bearbeitung", "alarmiert": "Alarmiert", "anfahrt": "Anfahrt",
	"vor_ort": "Vor Ort", "laeuft": "Einsatz läuft", "rueckfahrt": "Rückfahrt", "abgeschlossen": "Abgeschlossen",
}

static func difficulty() -> Dictionary:
	return Data.modes.get("difficulties", {}).get(State.meta["difficulty"], {})

# ---------------------------------------------------------------- Lage erzeugen
static func make_truth(type_id: String, loc: Dictionary, forced_variant := -1) -> String:
	var t: Dictionary = Data.incident_types[type_id]
	var rng: RandomNumberGenerator = Sim.rng
	var variants: Array = t.get("variants", [])
	var idx := 0
	if forced_variant >= 0 and forced_variant < variants.size():
		idx = forced_variant
	else:
		var roll := rng.randf()
		var acc := 0.0
		for i in variants.size():
			acc += float(variants[i]["p"])
			if roll <= acc:
				idx = i
				break
	var va: Dictionary = variants[idx] if variants.size() > 0 else {}
	var tid := "t%d" % State.next_id("truth")
	var reqs := {}
	var src: Dictionary = va.get("reqs", t.get("reqs", {}))
	for k in src:
		reqs[k] = int(src[k])
	var objects: Array = t.get("objects", ["Objekt"])
	var p: Vector2 = loc["pos"]
	var tr := {
		"id": tid, "type": type_id, "t0": State.clock, "x": p.x, "y": p.y, "node": int(loc["node"]),
		"address": loc["address"], "district": loc.get("district", ""), "street": loc.get("street", ""),
		"object": objects[rng.randi() % objects.size()], "vname": va.get("name", t["name"]), "lage": va.get("lage", ""),
		"kw": va.get("keyword", t["keyword"]), "case": int(va.get("case", -1)),
		"reqs": reqs, "known": {}, "work_total": float(va.get("work", t.get("work", 0))), "work_done": 0.0,
		"gate": float(va.get("gate", t.get("gate", 0.0))), "patients": [], "devs": [], "strain_t": 0.0, "strain_i": 0, "strain_n": 0,
		"reports": {}, "incident": "", "calls": 0, "dup_calls": 0, "next_call": 0.0, "closure": -1, "state": "open",
		"onscene": false, "revealed": false, "poi": loc.get("poi", ""), "dead": 0,
	}
	var pr: Array = va.get("patients", t.get("patients", [0, 0]))
	var sr: Array = va.get("sev", t.get("sev", [1, 1]))
	_add_patients(tr, rng.randi_range(int(pr[0]), int(pr[1])), sr)
	var esc: float = float(difficulty().get("escalation", 1.0))
	var devs: Array = t.get("developments", [])
	for i in devs.size():
		if rng.randf() < float(devs[i]["p"]) * esc:
			tr["devs"].append({"idx": i, "at": rng.randf_range(float(devs[i]["at"][0]), float(devs[i]["at"][1])), "done": false})
	if t.has("closure") and rng.randf() < float(t["closure"]):
		var e: int = int(loc.get("edge", -1))
		if e >= 0 and World.edge_cls[e] != World.CLS_AUTOBAHN:
			tr["closure"] = e
	if rng.randf() < float(t.get("multi_calls", 0.0)):
		tr["dup_calls"] = rng.randi_range(1, 2)
	State.truths[tid] = tr
	return tid

static func _add_patients(tr: Dictionary, n: int, sev_range: Array) -> void:
	for i in n:
		var sev: int = Sim.rng.randi_range(int(sev_range[0]), int(sev_range[1]))
		tr["patients"].append({"sev": sev, "state": "wait", "wait": 0.0, "care": 0.0, "veh": ""})

static func correct_keyword(tr: Dictionary) -> String:
	return tr.get("kw", Data.incident_types[tr["type"]]["keyword"])

## Gleichwertige Stichwörter (Meldebild am Telefon passt zu mehreren Stichwörtern).
static func acceptable_keywords(tr: Dictionary) -> Array:
	var t: Dictionary = Data.incident_types[tr["type"]]
	var out: Array = [correct_keyword(tr), t["keyword"]]
	out.append_array(t.get("kw_ok", []))
	return out

# ---------------------------------------------------------------- Einsatz anlegen
static func create_incident(form: Dictionary, call_id: String, by: String) -> String:
	var n := State.next_id("inc")
	var id := "e%d" % n
	var d := Time.get_datetime_dict_from_unix_time(State.game_unix())
	var p := Vector2(float(form["x"]), float(form["y"]))
	var kw: String = form.get("keyword", "SONST")
	var kd: Dictionary = Data.keywords.get(kw, {})
	var inc := {
		"id": id, "nr": "%02d%02d%02d-%04d" % [int(d["year"]) % 100, d["month"], d["day"], n],
		"keyword": kw, "x": p.x, "y": p.y, "node": World.access_node(p), "radius": float(form.get("radius", 0.0)),
		"address": form.get("address", World.address_at(p)["text"]), "district": World.districts[World.district_at(p)]["name"],
		"object": form.get("object", ""), "persons": form.get("persons", ""), "danger": form.get("danger", ""), "info": form.get("info", ""),
		"prio": int(form.get("prio", kd.get("prio", 2))), "status": "neu", "t_created": State.clock, "t_call": State.clock,
		"t_alarm": -1.0, "t_arrival": -1.0, "t_done": -1.0, "notes": [], "truth": "", "call": call_id, "caller": form.get("caller", ""),
		"revealed": false, "lage": "", "need": {}, "have": {}, "pat": {}, "progress": 0.0, "done": false, "closable": false,
		"loc_fixed": true, "recon": -1.0, "search": -1.0, "lead": "", "by": by, "dup_of": "", "score": -1, "alarmed_n": 0, "close_t": 0.0, "sig": "",
	}
	if call_id != "" and State.calls.has(call_id):
		var c: Dictionary = State.calls[call_id]
		inc["t_call"] = float(c["t"])
		inc["caller"] = "%s, Tel. %s" % [c["caller"]["name"], c["caller"]["phone"]]
		var tid: String = c.get("truth", "")
		if tid != "" and State.truths.has(tid):
			var tr: Dictionary = State.truths[tid]
			if tr["incident"] == "" or not State.incidents.has(tr["incident"]):
				tr["incident"] = id
				inc["truth"] = tid
				inc["loc_fixed"] = p.distance_to(Vector2(tr["x"], tr["y"])) <= 130.0
			else:
				inc["dup_of"] = State.incidents[tr["incident"]]["nr"]
		c["incident"] = id
	State.incidents[id] = inc
	State.meta["stats"]["incidents"] = int(State.meta["stats"]["incidents"]) + 1
	Sim.radio("Leitstelle", "Einsatz %s angelegt: %s – %s" % [inc["nr"], kw, inc["address"]], -1, "system", id)
	State.touch_incident(id)
	return id

static func add_note(inc: Dictionary, who: String, text: String) -> void:
	inc["notes"].append({"t": State.clock, "who": who, "text": text})
	Sim.radio(who, "Notiz zu %s: %s" % [inc["nr"], text], -1, "note", inc["id"])
	State.touch_incident(inc["id"])

static func alarm(inc: Dictionary, vehicle_ids: Array, by: String) -> Dictionary:
	var ok: Array = []
	var failed: Array = []
	for vid in vehicle_ids:
		if not State.vehicles.has(vid):
			continue
		var v: Dictionary = State.vehicles[vid]
		var err := VL.alarm(v, inc["id"])
		if err == "":
			ok.append(v["callsign"])
		else:
			failed.append("%s: %s" % [v["callsign"], err])
	if ok.size() > 0:
		if float(inc["t_alarm"]) < 0.0:
			inc["t_alarm"] = State.clock
		inc["alarmed_n"] = int(inc["alarmed_n"]) + ok.size()
		Sim.radio("Leitstelle", "Alarm %s, %s, %s – für: %s" % [inc["keyword"], inc["address"], inc["object"], ", ".join(ok)], -1, "alarm", inc["id"])
		Sim.sound("alarm")
		_derive_status(inc)
		State.touch_incident(inc["id"])
	return {"ok": ok, "failed": failed}

# ---------------------------------------------------------------- Hilfsfunktionen
static func _caps_on_scene(on: Array) -> Dictionary:
	var have := {}
	for v in on:
		var c: Dictionary = VL.caps(v)
		for k in c:
			have[k] = int(have.get(k, 0)) + int(c[k])
	return have

static func caps_assigned(inc_id: String) -> Dictionary:
	var have := {}
	for vid in State.incident_vehicles(inc_id):
		var c: Dictionary = VL.caps(State.vehicles[vid])
		for k in c:
			have[k] = int(have.get(k, 0)) + int(c[k])
	return have

static func _medical_need(tr: Dictionary) -> Dictionary:
	var rtw := 0
	var na := 0
	var ktw := 0
	for p in tr["patients"]:
		if p["state"] == "wait" or p["state"] == "care":
			if int(p["sev"]) == 0:
				ktw += 1
			else:
				rtw += 1
			if int(p["sev"]) >= 3:
				na += 1
	var out := {}
	if rtw > 0:
		out["rtw"] = rtw
	if na > 0:
		out["notarzt"] = int(ceil(na / 2.0))
	if ktw > 0:
		out["ktw"] = ktw
	return out

## Dem Disponenten bekannter Gesamtbedarf (nach Lagemeldung).
static func known_need(tr: Dictionary) -> Dictionary:
	var need := {}
	for k in tr["known"]:
		need[k] = int(tr["known"][k])
	var med := _medical_need(tr)
	for k in med:
		need[k] = max(int(need.get(k, 0)), int(med[k]))
	return need

static func shortage(need: Dictionary, have: Dictionary) -> Dictionary:
	var out := {}
	for k in need:
		var miss: int = int(need[k]) - int(have.get(k, 0))
		if k == "ktw":
			miss -= int(have.get("rtw", 0))
		if miss > 0:
			out[k] = miss
	return out

static func need_text(d: Dictionary) -> String:
	var parts: Array = []
	for k in d:
		parts.append("%d × %s" % [int(d[k]), Data.capabilities.get(k, k)])
	return ", ".join(parts)

static func _lead(inc: Dictionary, on: Array) -> Dictionary:
	if on.is_empty():
		return {}
	var cur: String = inc["lead"]
	var best: Dictionary = on[0]
	var best_rank := -1
	for v in on:
		if v["id"] == cur:
			return v
		var rank := 0
		if VL.has_cap(v, "fuehrung_fw") or VL.has_cap(v, "elrd") or VL.has_cap(v, "pol_fuehrung"):
			rank = 2
		if rank > best_rank:
			best_rank = rank
			best = v
	inc["lead"] = best["id"]
	return best

static func _say(inc: Dictionary, on: Array, text: String, talk := false) -> void:
	var lead := _lead(inc, on)
	if lead.is_empty():
		Sim.radio("Einsatzstelle", text, -1, "funk", inc["id"])
	elif talk:
		VL.request_talk(lead, text)
	else:
		Sim.radio(lead["callsign"], text, -1, "funk", inc["id"])

static func _derive_status(inc: Dictionary) -> void:
	if inc["done"]:
		return
	var any_scene := false
	var any_route := false
	var any := false
	for vid in State.incident_vehicles(inc["id"]):
		any = true
		var st: String = State.vehicles[vid]["state"]
		if st == "onscene":
			any_scene = true
		elif st == "enroute":
			any_route = true
	var s := "neu"
	if any_scene:
		s = "laeuft" if inc["revealed"] else "vor_ort"
	elif any_route:
		s = "anfahrt"
	elif any:
		s = "alarmiert"
	elif float(inc["t_alarm"]) >= 0.0 or inc.get("opened", false):
		s = "in_bearbeitung"
	if s != inc["status"]:
		inc["status"] = s
		State.touch_incident(inc["id"])

# ---------------------------------------------------------------- Tick
static func tick(h: float) -> void:
	_tick_truths(h)
	for id in State.incidents.keys():
		var inc: Dictionary = State.incidents[id]
		_tick_incident(inc, h)

static func _tick_truths(h: float) -> void:
	var esc: float = float(difficulty().get("escalation", 1.0))
	for tid in State.truths.keys():
		var tr: Dictionary = State.truths[tid]
		if tr["state"] != "open":
			continue
		for p in tr["patients"]:
			if p["state"] != "wait":
				continue
			p["wait"] = float(p["wait"]) + h * esc
			var sev := int(p["sev"])
			var w := float(p["wait"])
			if sev == 2 and w > 1800.0:
				p["sev"] = 3
				p["wait"] = 0.0
			elif sev == 3 and w > 1200.0:
				p["sev"] = 4
				p["wait"] = 0.0
			elif sev == 4 and w > (1100.0 if tr["onscene"] else 600.0):
				p["state"] = "dead"
				tr["dead"] = int(tr["dead"]) + 1
				State.meta["stats"]["deaths"] = int(State.meta["stats"]["deaths"]) + 1
				if tr["incident"] != "" and State.incidents.has(tr["incident"]):
					var inc: Dictionary = State.incidents[tr["incident"]]
					Sim.radio("Leitstelle", "Einsatz %s: Für einen Patienten kam jede Hilfe zu spät." % inc["nr"], -1, "system", inc["id"])

static func _tick_incident(inc: Dictionary, h: float) -> void:
	var id: String = inc["id"]
	if inc["done"]:
		inc["close_t"] = float(inc["close_t"]) + h
		if float(inc["close_t"]) > 900.0:
			close_incident(inc, "System")
		return
	var on: Array = []
	for vid in State.incident_vehicles(id):
		var v: Dictionary = State.vehicles[vid]
		if v["state"] == "onscene":
			on.append(v)
	_derive_status(inc)
	var tr: Dictionary = State.truths.get(inc["truth"], {})
	if not tr.is_empty():
		tr["onscene"] = on.size() > 0
	if on.is_empty():
		return
	if float(inc["t_arrival"]) < 0.0:
		inc["t_arrival"] = State.clock
		if float(inc["t_alarm"]) >= 0.0:
			State.meta["stats"]["resp_sum"] = float(State.meta["stats"]["resp_sum"]) + (State.clock - float(inc["t_alarm"]))
			State.meta["stats"]["resp_n"] = int(State.meta["stats"]["resp_n"]) + 1
		State.touch_incident(id)
	# Einsatzstelle suchen, falls Ortsangabe ungenau war
	if not inc["loc_fixed"] and not tr.is_empty():
		if float(inc["search"]) < 0.0:
			var dist := Vector2(inc["x"], inc["y"]).distance_to(Vector2(tr["x"], tr["y"]))
			inc["search"] = clampf(dist / 3.0, 40.0, 420.0)
			_say(inc, on, "Einsatzstelle an der gemeldeten Adresse nicht auffindbar. Erkunden die Umgebung.")
		inc["search"] = float(inc["search"]) - h
		if float(inc["search"]) <= 0.0:
			inc["loc_fixed"] = true
			inc["x"] = tr["x"]
			inc["y"] = tr["y"]
			inc["node"] = tr["node"]
			inc["address"] = tr["address"]
			inc["radius"] = 0.0
			_say(inc, on, "Einsatzstelle lokalisiert: %s." % tr["address"])
			for vid in State.incident_vehicles(id):
				var v: Dictionary = State.vehicles[vid]
				if v["state"] == "onscene" or v["state"] == "enroute":
					VL.redirect_to_incident(v)
			State.touch_incident(id)
		return
	if not inc["revealed"]:
		if float(inc["recon"]) < 0.0:
			inc["recon"] = Sim.rng.randf_range(35.0, 80.0)
		inc["recon"] = float(inc["recon"]) - h
		if float(inc["recon"]) <= 0.0:
			_reveal(inc, tr, on)
		return
	if tr.is_empty():
		return
	_work(inc, tr, on, h)
	_patients(inc, tr, on, h)
	_publish(inc, tr, on)
	if _is_complete(tr):
		finish(inc, tr, on)

static func _reveal(inc: Dictionary, tr: Dictionary, on: Array) -> void:
	inc["revealed"] = true
	if tr.is_empty():
		if inc["dup_of"] != "":
			_say(inc, on, "Einsatzstelle identisch mit Einsatz %s – Doppelalarmierung, rücken ein." % inc["dup_of"])
		else:
			_say(inc, on, "Lagemeldung: Keine Feststellung an der Einsatzstelle. Kein Einsatz erforderlich.")
		finish(inc, tr, on)
		return
	tr["revealed"] = true
	if tr["closure"] >= 0:
		State.env["closures"][int(tr["closure"])] = "Einsatzstelle %s" % inc["nr"]
		State.apply_env()
		State.env_changed.emit()
	var n := 0
	for p in tr["patients"]:
		if p["state"] != "dead":
			n += 1
	var text := "Lagemeldung %s, %s: %s – %s" % [inc["keyword"], String(inc["address"]).get_slice(",", 0), tr["object"], tr["lage"]]
	if n > 0 and int(tr["patients"][0]["sev"]) > 0:
		text += " %d Verletzte/Betroffene." % n
	inc["lage"] = text
	_say(inc, on, text)
	tr["known"] = tr["reqs"].duplicate()
	_publish(inc, tr, on)
	var miss := shortage(known_need(tr), caps_assigned(inc["id"]))
	if not miss.is_empty():
		_say(inc, on, "Nachforderung: benötigen %s." % need_text(miss), true)
	_derive_status(inc)
	State.touch_incident(inc["id"])

static func _work(inc: Dictionary, tr: Dictionary, on: Array, h: float) -> void:
	var total := float(tr["work_total"])
	if total <= 0.0 or float(tr["work_done"]) >= total:
		return
	var have := _caps_on_scene(on)
	var sum := 0.0
	var cnt := 0
	for k in tr["reqs"]:
		if MEDICAL.has(k):
			continue
		cnt += 1
		sum += min(1.0, float(have.get(k, 0)) / max(1.0, float(tr["reqs"][k])))
	var rate := 1.0 if cnt == 0 else sum / cnt
	var before := float(tr["work_done"]) / total
	tr["work_done"] = min(total, float(tr["work_done"]) + h * rate)
	var frac := float(tr["work_done"]) / total
	var t: Dictionary = Data.incident_types[tr["type"]]
	# Folgen von Kräftemangel
	var strains: Array = t.get("strain", [])
	if rate < 0.999 and int(tr["strain_i"]) < strains.size():
		tr["strain_t"] = float(tr["strain_t"]) + h * float(difficulty().get("escalation", 1.0))
		var s: Dictionary = strains[int(tr["strain_i"])]
		if float(tr["strain_t"]) >= float(s["after"]):
			tr["strain_t"] = 0.0
			tr["strain_i"] = int(tr["strain_i"]) + 1
			tr["strain_n"] = int(tr["strain_n"]) + 1
			_apply_change(inc, tr, on, s)
	# Dynamische Lageentwicklung
	var devs: Array = t.get("developments", [])
	for d in tr["devs"]:
		if not d["done"] and frac >= float(d["at"]):
			d["done"] = true
			_apply_change(inc, tr, on, devs[int(d["idx"])])
	# Rückmeldungen
	var reps: Dictionary = t.get("reports", {})
	for key in ["p35", "p50", "p75"]:
		var thr := float(key.substr(1)) / 100.0
		if reps.has(key) and not tr["reports"].has(key) and before < thr and frac >= thr:
			tr["reports"][key] = true
			_say(inc, on, reps[key])

static func _apply_change(inc: Dictionary, tr: Dictionary, on: Array, ch: Dictionary) -> void:
	for k in ch.get("add", {}):
		tr["reqs"][k] = int(tr["reqs"].get(k, 0)) + int(ch["add"][k])
	tr["work_total"] = float(tr["work_total"]) + float(ch.get("work", 0))
	if ch.has("patients"):
		_add_patients(tr, Sim.rng.randi_range(int(ch["patients"][0]), int(ch["patients"][1])), ch.get("sev", [1, 2]))
	tr["known"] = tr["reqs"].duplicate()
	var text: String = ch.get("text", "Lageänderung.")
	var miss := shortage(known_need(tr), caps_assigned(inc["id"]))
	if not miss.is_empty():
		text += " Nachforderung: %s." % need_text(miss)
	_say(inc, on, text, true)
	inc["lage"] = String(inc["lage"]) + "\n" + State.time_str() + " " + ch.get("text", "")

static func _patients(inc: Dictionary, tr: Dictionary, on: Array, h: float) -> void:
	var pats: Array = tr["patients"]
	if pats.is_empty():
		return
	var total := float(tr["work_total"])
	var frac := 1.0 if total <= 0.0 else float(tr["work_done"]) / total
	var accessible := float(tr["gate"]) <= 0.0 or frac >= float(tr["gate"])
	var na_here := false
	for v in on:
		if VL.has_cap(v, "notarzt"):
			na_here = true
	for i in pats.size():
		var p: Dictionary = pats[i]
		if p["state"] == "wait" and accessible:
			var sev := int(p["sev"])
			for v in on:
				if int(v["patient"]) >= 0:
					continue
				if VL.has_cap(v, "rtw") or (sev <= 1 and VL.has_cap(v, "ktw")):
					v["patient"] = i
					p["state"] = "care"
					p["veh"] = v["id"]
					p["care"] = CARE_TIME[clampi(sev, 0, 4)] * Sim.rng.randf_range(0.8, 1.2)
					break
		elif p["state"] == "care":
			var vid: String = p["veh"]
			if not State.vehicles.has(vid) or State.vehicles[vid]["incident"] != inc["id"] or State.vehicles[vid]["state"] != "onscene":
				p["state"] = "wait"
				p["veh"] = ""
				continue
			var speed := 1.0
			if int(p["sev"]) >= 3 and not na_here:
				speed = 0.3
			p["care"] = float(p["care"]) - h * speed
			if float(p["care"]) <= 0.0:
				var v: Dictionary = State.vehicles[vid]
				if int(p["sev"]) == 1 and Sim.rng.randf() < 0.35:
					p["state"] = "ambulant"
					v["patient"] = -1
					Sim.radio(v["callsign"], "Patient ambulant versorgt, kein Transport erforderlich.", -1, "funk", inc["id"])
				else:
					var hosp := Sim.choose_hospital(Vector2(inc["x"], inc["y"]), int(p["sev"]))
					if VL.start_transport(v, hosp):
						p["state"] = "transport"
						State.meta["stats"]["saved"] = int(State.meta["stats"]["saved"]) + 1
						Sim.radio(v["callsign"], "Transportieren einen Patienten (%s) nach %s." % [["Krankentransport", "leicht verletzt", "mittelschwer verletzt", "schwer verletzt", "kritisch, unter Reanimationsbereitschaft"][clampi(int(p["sev"]), 0, 4)], hosp["name"]], -1, "funk", inc["id"])
					else:
						p["state"] = "ambulant"
						v["patient"] = -1

static func _is_complete(tr: Dictionary) -> bool:
	if float(tr["work_total"]) > 0.0 and float(tr["work_done"]) < float(tr["work_total"]):
		return false
	for p in tr["patients"]:
		if p["state"] == "wait" or p["state"] == "care":
			return false
	return true

static func _publish(inc: Dictionary, tr: Dictionary, on: Array) -> void:
	var need := known_need(tr)
	var have := _caps_on_scene(on)
	var pat := {"total": 0, "wait": 0, "care": 0, "transport": 0, "dead": 0, "ambulant": 0}
	for p in tr["patients"]:
		pat["total"] += 1
		pat[p["state"]] = int(pat.get(p["state"], 0)) + 1
	var total := float(tr["work_total"])
	var prog := 1.0 if total <= 0.0 else float(tr["work_done"]) / total
	var sig := "%s|%s|%s|%d" % [str(need), str(have), str(pat), int(prog * 20.0)]
	if sig != inc["sig"]:
		inc["sig"] = sig
		inc["need"] = need
		inc["have"] = have
		inc["pat"] = pat
		inc["progress"] = prog
		State.touch_incident(inc["id"])

# ---------------------------------------------------------------- Abschluss
static func score(inc: Dictionary, tr: Dictionary) -> int:
	if tr.is_empty():
		return 40
	var sc: Dictionary = Data.modes.get("scoring", {})
	var s := 100.0
	if float(inc["t_alarm"]) >= 0.0:
		s -= clampf((float(inc["t_alarm"]) - float(inc["t_call"]) - float(sc.get("call_to_alarm", 120))) / 6.0, 0.0, 20.0)
	if float(inc["t_arrival"]) >= 0.0 and float(inc["t_alarm"]) >= 0.0:
		s -= clampf((float(inc["t_arrival"]) - float(inc["t_alarm"]) - float(sc.get("hilfsfrist", 600))) / 12.0, 0.0, 25.0)
	var correct := correct_keyword(tr)
	if inc["keyword"] != correct:
		var same: bool = Data.keywords.get(inc["keyword"], {}).get("cat", "") == Data.keywords.get(correct, {}).get("cat", "x")
		if acceptable_keywords(tr).has(inc["keyword"]):
			s -= 2.0
		else:
			s -= 6.0 if same else 12.0
	s -= 10.0 * int(tr["strain_n"])
	s -= 30.0 * int(tr["dead"])
	return int(clampf(s, 0.0, 100.0))

static func finish(inc: Dictionary, tr: Dictionary, on: Array) -> void:
	var id: String = inc["id"]
	inc["done"] = true
	inc["closable"] = true
	inc["t_done"] = State.clock
	inc["status"] = "rueckfahrt"
	inc["progress"] = 1.0
	inc["need"] = {}
	if not tr.is_empty():
		var reps: Dictionary = Data.incident_types[tr["type"]].get("reports", {})
		_say(inc, on, reps.get("done", "Einsatz beendet."))
		tr["state"] = "done"
		if int(tr["closure"]) >= 0:
			State.env["closures"].erase(int(tr["closure"]))
			State.apply_env()
			State.env_changed.emit()
	inc["score"] = score(inc, tr)
	for vid in State.incident_vehicles(id):
		var v: Dictionary = State.vehicles[vid]
		if v["state"] != "onscene":
			Sim.radio("Leitstelle", "%s: Einsatzabbruch, Einsatzstelle benötigt keine weiteren Kräfte." % v["callsign"], -1, "funk", id)
		VL.send_home(v)
	var st: Dictionary = State.meta["stats"]
	st["done"] = int(st["done"]) + 1
	st["score_sum"] = float(st["score_sum"]) + int(inc["score"])
	Sim.on_incident_finished(inc, tr)
	Sim.radio("Leitstelle", "Einsatz %s (%s) beendet – Bewertung %d %%. Einsatz kann abgeschlossen werden." % [inc["nr"], inc["keyword"], int(inc["score"])], -1, "system", id)
	State.touch_incident(id)

## Einsatz abschließen (Archiv) bzw. abbrechen, wenn noch keine Kräfte gebunden sind.
static func close_incident(inc: Dictionary, by: String) -> String:
	var id: String = inc["id"]
	var state := "abgeschlossen"
	if not inc["done"]:
		if State.incident_vehicles(id).size() > 0:
			return "Einsatz läuft noch. Zuerst alle Einsatzmittel abziehen oder Einsatzende abwarten."
		state = "abgebrochen"
		var tr: Dictionary = State.truths.get(inc["truth"], {})
		if not tr.is_empty() and tr["state"] == "open":
			tr["incident"] = ""
			tr["next_call"] = State.clock + Sim.rng.randf_range(90.0, 200.0)
			if int(tr["closure"]) >= 0 and State.env["closures"].has(int(tr["closure"])):
				State.env["closures"].erase(int(tr["closure"]))
				State.apply_env()
				State.env_changed.emit()
	else:
		State.truths.erase(inc["truth"])
	State.archive.append({
		"nr": inc["nr"], "keyword": inc["keyword"], "address": inc["address"], "t_created": inc["t_created"], "t_done": State.clock,
		"score": inc["score"], "state": state, "lage": inc["lage"], "vehicles": int(inc["alarmed_n"]), "by": by,
		"time": State.date_str(float(inc["t_created"])) + " " + State.time_str(float(inc["t_created"])),
	})
	if State.archive.size() > 400:
		State.archive = State.archive.slice(State.archive.size() - 400)
	Sim.radio("Leitstelle", "Einsatz %s %s." % [inc["nr"], state], -1, "system", id)
	State.remove_incident(id)
	return ""
