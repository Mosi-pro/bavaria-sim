extends RefCounted
## Vereinfachtes Personalsystem: Jede Wache besitzt eine Wachstärke je Qualifikation.
## Fahrzeuge binden beim Alarm eine Besatzung und geben sie bei Rückkehr (Status 2) frei.

static func availability_factor(st: Dictionary) -> float:
	var mode: Dictionary = Data.modes.get("modes", {}).get(State.meta["mode"], {})
	if mode.get("ff_availability", false) and st["kind"] in ["ff", "thw", "wr", "kats"]:
		var curve: Array = Data.modes.get("ff_availability_curve", [])
		if curve.size() == 24:
			return float(curve[State.hour()])
	return 1.0

## Wachstärke gesamt und aktuell verfügbar: {qual: [gesamt, im Dienst, verfügbar]}
static func overview(st_id: String) -> Dictionary:
	var st: Dictionary = State.stations[st_id]
	var f := availability_factor(st)
	var out := {}
	for q in st["staff"]:
		var total := int(st["staff"][q])
		var duty := int(ceil(total * f))
		out[q] = [total, duty, duty]
	for vid in State.vehicles:
		var v: Dictionary = State.vehicles[vid]
		if v["station"] != st_id:
			continue
		for q in v["crew"]:
			if out.has(q):
				out[q][2] -= int(v["crew"][q])
	return out

static func plan_crew(v: Dictionary) -> Dictionary:
	var t: Dictionary = Data.vehicle_types[v["type"]]
	var ov := overview(v["station"])
	var av := {}
	for q in ov:
		av[q] = ov[q][2]
	var crew := {}
	var have := 0
	for q in t.get("quals", {}):
		var need := int(t["quals"][q])
		if int(av.get(q, 0)) < need:
			return {}
		crew[q] = need
		av[q] -= need
		have += need
	var std := int(t["crew"])
	var fill: Array = Data.organisations.get(t["org"], {}).get("fill", [])
	for q in fill:
		while have < std and int(av.get(q, 0)) > 0:
			crew[q] = int(crew.get(q, 0)) + 1
			av[q] -= 1
			have += 1
	if have < int(t["min"]):
		return {}
	return crew

static func can_staff(v: Dictionary) -> bool:
	if not v["crew"].is_empty():
		return true
	return not plan_crew(v).is_empty()

static func crew_count(v: Dictionary) -> int:
	var n := 0
	for q in v["crew"]:
		n += int(v["crew"][q])
	return n

static func crew_text(v: Dictionary) -> String:
	if v["crew"].is_empty():
		return "–"
	var parts: Array = []
	for q in v["crew"]:
		parts.append("%d %s" % [int(v["crew"][q]), q])
	return "%d (%s)" % [crew_count(v), ", ".join(parts)]

## Sollstärke einer Wache aus ihrem Fahrzeugbestand ableiten.
static func compute_staff(st_id: String) -> Dictionary:
	var st: Dictionary = State.stations[st_id]
	var factor := float(Data.modes.get("staffing", {}).get(st["kind"], 1.0))
	var quals := {}
	var filler := 0.0
	var fill: Array = Data.organisations.get(st["org"], {}).get("fill", ["TM"])
	for vid in State.station_vehicles(st_id):
		var t: Dictionary = Data.vehicle_types[State.vehicles[vid]["type"]]
		var n := 0
		for q in t.get("quals", {}):
			quals[q] = float(quals.get(q, 0.0)) + float(t["quals"][q])
			n += int(t["quals"][q])
		filler += max(0, int(t["crew"]) - n)
	# Funktionsträger sind immer vollständig vorhanden; bei hauptamtlichen Wachen
	# (Faktor < 1) ist die Mannschaft knapper bemessen als die Summe aller Sitzplätze.
	var out := {}
	for q in quals:
		out[q] = int(ceil(float(quals[q]) * max(1.0, factor)))
	if filler > 0.0 and fill.size() > 0:
		out[fill[0]] = int(out.get(fill[0], 0)) + int(ceil(filler * factor))
	return out
