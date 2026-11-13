extends RefCounted
## Dispositionsvorschlag (Alarm- und Ausrückeordnung): wählt je benötigter Fähigkeit
## die schnellsten verfügbaren Fahrzeuge anhand realer Fahrzeiten im Straßennetz.

const VL = preload("res://src/vehicles/vehicle_logic.gd")
const IL = preload("res://src/incidents/incident_logic.gd")

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
		if reason == "":
			eta += VL.turnout_mean(v)
		rows.append({"id": vid, "eta": eta, "dist": State.veh_pos(v).distance_to(target), "reason": reason, "caps": VL.caps(v)})
	rows.sort_custom(func(a, b): return a["eta"] < b["eta"])
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
	for k in open.keys():
		while int(open[k]) > 0:
			var pick := {}
			for r in rows:
				if r["reason"] != "" or suggested.has(r["id"]):
					continue
				if int(r["caps"].get(k, 0)) > 0 and r["eta"] < INF:
					pick = r
					break
			if pick.is_empty():
				break
			suggested.append(pick["id"])
			for c in pick["caps"]:
				if open.has(c):
					open[c] = int(open[c]) - int(pick["caps"][c])
	var missing := {}
	for k in open:
		if int(open[k]) > 0:
			missing[k] = int(open[k])
	return {"rows": rows, "suggested": suggested, "missing": missing, "need": need}
