extends RefCounted
## Spielmodi: Karriere (Budget, Erfahrung, Regionen, Organisationen) und Szenarien.

const StationLogic = preload("res://src/stations/station_logic.gd")
const CallGen = preload("res://src/incidents/call_generator.gd")
const Env = preload("res://src/simulation/environment.gd")
const Tutorial = preload("res://src/simulation/tutorial.gd")

static func career() -> Dictionary:
	return Data.modes.get("career", {})

static func is_career() -> bool:
	return State.meta["mode"] == "karriere"

static func orgs_for_level(level: int) -> Array:
	var out: Array = []
	var ol: Dictionary = career().get("org_level", {})
	for org in ol:
		if int(ol[org]) <= level:
			out.append(org)
	return out

static func can_afford(cost: int) -> bool:
	return not is_career() or int(State.meta["budget"]) >= cost

static func pay(cost: int) -> void:
	if is_career():
		State.meta["budget"] = int(State.meta["budget"]) - cost
		State.meta_changed.emit()

static func reward(inc: Dictionary, tr: Dictionary) -> void:
	if tr.is_empty():
		return
	var score := int(inc["score"])
	var prio_f := 4 - clampi(int(inc["prio"]), 1, 3)
	var xp := int(score * prio_f * 0.6)
	State.meta["xp"] = int(State.meta["xp"]) + xp
	if is_career():
		var money := int(float(career().get("reward_base", 4000)) * prio_f * score / 100.0)
		State.meta["budget"] = int(State.meta["budget"]) + money
	var need := int(career().get("xp_per_level", 1500)) * int(State.meta["level"])
	while int(State.meta["xp"]) >= need:
		State.meta["xp"] = int(State.meta["xp"]) - need
		State.meta["level"] = int(State.meta["level"]) + 1
		need = int(career().get("xp_per_level", 1500)) * int(State.meta["level"])
		State.notice.emit("Beförderung: Erfahrungsstufe %d erreicht." % int(State.meta["level"]), "info")
		if is_career():
			var before: Array = State.meta["orgs"].duplicate()
			State.meta["orgs"] = orgs_for_level(int(State.meta["level"]))
			for org in State.meta["orgs"]:
				if not before.has(org):
					State.notice.emit("Neue Organisation verfügbar: %s." % Data.org_name(org), "info")
			StationLogic.add_unlocked()
	State.meta_changed.emit()

static func unlock_zone(zone: int) -> String:
	if not is_career():
		return "Nur im Karrieremodus."
	var zones: Array = State.meta["zones"]
	if zones.has(zone):
		return "Region ist bereits freigeschaltet."
	if not zones.has(zone - 1):
		return "Zuerst muss die vorherige Region übernommen werden."
	var cost := int(career().get("zone_cost", {}).get(str(zone), 0))
	if not can_afford(cost):
		return "Budget nicht ausreichend (%s €)." % _money(cost)
	pay(cost)
	zones.append(zone)
	var n := StationLogic.add_unlocked()
	Sim.radio("Leitstelle", "Zuständigkeitsbereich erweitert: %s (%d Standorte übernommen)." % [career().get("zone_names", {}).get(str(zone), "Region %d" % zone), n], -1, "system", "")
	State.meta_changed.emit()
	return ""

static func _money(v: int) -> String:
	var s := str(abs(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

# ---------------------------------------------------------------- Szenarien
static func scenario() -> Dictionary:
	for s in Data.scenarios:
		if s["id"] == State.meta.get("scenario", ""):
			return s
	return {}

static func tick(_h: float) -> void:
	Tutorial.tick(_h)
	if State.meta["mode"] != "szenario" or State.meta.get("scenario_over", false):
		return
	var sc := scenario()
	if sc.is_empty():
		return
	var done: Array = State.meta["scenario_done"]
	var events: Array = sc.get("events", [])
	for i in events.size():
		if done.has(i):
			continue
		var ev: Dictionary = events[i]
		if State.clock >= float(ev["t"]):
			done.append(i)
			var opts := {}
			for k in ["district", "poi", "cls", "water", "variant"]:
				if ev.has(k):
					opts[k] = ev[k]
			CallGen.spawn_event(ev["type"], opts)
	if done.size() >= events.size() and State.clock >= float(sc.get("duration", 7200)) * 0.5 and State.incidents.is_empty() and State.calls.is_empty():
		State.meta["scenario_over"] = true
		var st: Dictionary = State.meta["stats"]
		var avg := 0.0 if int(st["done"]) == 0 else float(st["score_sum"]) / int(st["done"])
		State.notice.emit("Szenario »%s« abgeschlossen.\n\nEinsätze: %d   Durchschnittliche Bewertung: %d %%\nVerpasste Notrufe: %d   Verstorbene Patienten: %d\n\nSie können im freien Betrieb weiterspielen." % [sc["name"], int(st["done"]), int(avg), int(st["calls_missed"]), int(st["deaths"])], "result")
		State.meta_changed.emit()
