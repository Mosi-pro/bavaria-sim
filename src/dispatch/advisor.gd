extends RefCounted
## Dispositionsvorschlag (Alarm- und Ausrückeordnung): wählt je benötigter Fähigkeit
## die schnellsten verfügbaren Fahrzeuge anhand realer Fahrzeiten im Straßennetz.

const VL = preload("res://src/vehicles/vehicle_logic.gd")
const IL = preload("res://src/incidents/incident_logic.gd")
const SPECIAL := ["grtw", "srtw", "itw", "kindernotarzt", "flf", "elw2", "sek", "hoehenrettung", "dekon"]

## Rückgabe: {rows: [{id, eta, dist, reason, caps}], suggested: [ids], missing: {cap: n}, need: {cap: n}}
static func suggest(inc: Dictionary, org_filter: Array = []) -> Dictionary:
	var node := int(inc["node"])
	var times := World.times_from(node, true)
	var target := Vector2(inc["x"], inc["y"])
	var rows: Array = []
	for vid in State.vehicles:
		var v: Dictionary = State.vehicles[vid]
		if not org_filter.is_empty() and not org_filter.has(v["org"]):
			continue
		var reason := VL.block_reason(v)
		var n := VL.node_of(v)
		var eta: float = times[n] if n >= 0 else INF
		if VL.is_air(v):
			eta = VL.air_eta(v, target)
		if reason == "":
			eta += VL.turnout_mean(v)
		var row := {"id": vid, "eta": eta, "dist": State.veh_pos(v).distance_to(target), "reason": reason, "caps": VL.caps(v), "crew": int(Data.vehicle_types[v["type"]]["crew"])}
		if VL.has_modules(v):
			row["module"] = VL.module_of(v)
			row["can_change"] = VL.can_change_module(v) and reason == ""
		rows.append(row)
	rows.sort_custom(func(a, b):
		if absf(a["eta"] - b["eta"]) > 20.0:
			return a["eta"] < b["eta"]
		if a["crew"] != b["crew"]:
			return a["crew"] > b["crew"]
		return a["id"] < b["id"])
	var need := {}
	var aao: Dictionary = Data.keywords.get(inc["keyword"], {}).get("aao", {})
	for k in aao:
		need[k] = int(aao[k])
	if inc["revealed"]:
		need = {}
		for k in inc.get("need", {}):
			need[k] = int(inc["need"][k])
	var open := need.duplicate()
	var have := IL.caps_assigned(inc["id"])
	for k in open.keys():
		open[k] = int(open[k]) - int(have.get(k, 0))
	var suggested: Array = []
	var modules := {}
	for k in open.keys():
		while int(open[k]) > 0:
			var pick := {}
			var pick_mod := ""
			var best := INF
			for r in rows:
				if r["reason"] != "" or suggested.has(r["id"]):
					continue
				var mod_for := ""
				if int(r["caps"].get(k, 0)) <= 0 and r.get("can_change", false):
					mod_for = _module_for(r["id"], k)
				if (int(r["caps"].get(k, 0)) > 0 or mod_for != "") and r["eta"] < INF:
					# Sonderfahrzeuge nur, wenn ihre Sonderfähigkeit gebraucht wird oder nichts anderes in Reichweite ist
					var eff: float = r["eta"]
					# Hubschrauber nur, wenn er mindestens 2 Minuten schneller ist als bodengebundene Notärzte
					if int(r["caps"].get("rth", 0)) > 0 and not need.has("rth"):
						eff += 120.0
					for sc in SPECIAL:
						if int(r["caps"].get(sc, 0)) > 0 and not need.has(sc):
							eff += 1200.0
					if mod_for != "":
						eff += float(Data.vehicle_types[State.vehicles[r["id"]]["type"]].get("module_change", 120))
					if eff < best:
						best = eff
						pick = r
						pick_mod = mod_for
			if pick.is_empty():
				break
			suggested.append(pick["id"])
			if pick_mod != "":
				# Vorschlag: GW-L mit passendem Rollcontainer
				pick["module"] = pick_mod
				pick["caps"] = VL.caps_with_module(State.vehicles[pick["id"]], pick_mod)
				modules[pick["id"]] = pick_mod
			for c in pick["caps"]:
				if open.has(c):
					open[c] = int(open[c]) - int(pick["caps"][c])
	var missing := {}
	for k in open:
		if int(open[k]) > 0:
			missing[k] = int(open[k])
	return {"rows": rows, "suggested": suggested, "missing": missing, "need": need, "modules": modules}

## Rollcontainer, der die Fähigkeit cap liefert ("" = keiner).
static func _module_for(vid: String, cap: String) -> String:
	var v: Dictionary = State.vehicles[vid]
	var mods: Dictionary = Data.vehicle_types[v["type"]].get("modules", {})
	for m in VL.available_modules(v):
		if int(mods.get(m, {}).get("caps", {}).get(cap, 0)) > 0:
			return m
	return ""
