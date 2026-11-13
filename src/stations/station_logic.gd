extends RefCounted
## Wachen- und Fahrzeugverwaltung (Bestand, Zuordnung, Neuanlage).

const Personnel = preload("res://src/personnel/personnel.gd")

static func init_from_data() -> void:
	for def in Data.stations:
		if _station_allowed(def):
			add_station_from_def(def)

static func _station_allowed(def: Dictionary) -> bool:
	var zones: Array = State.meta["zones"]
	var orgs: Array = State.meta["orgs"]
	if not orgs.has(def["org"]):
		return false
	var p := Vector2(def["pos"][0], def["pos"][1])
	var zone := int(World.districts[World.district_at(p)].get("zone", 5))
	return zones.has(zone) or zones.has(float(zone))

## Fügt nach Freischaltung (Karriere) alle nun zulässigen Standardwachen hinzu.
static func add_unlocked() -> int:
	var n := 0
	for def in Data.stations:
		if not State.stations.has(def["id"]) and _station_allowed(def) and not State.meta.get("removed_stations", []).has(def["id"]):
			add_station_from_def(def)
			n += 1
	return n

static func add_station_from_def(def: Dictionary) -> void:
	var p := Vector2(def["pos"][0], def["pos"][1])
	var id: String = def["id"]
	_create_station(id, int(def["nr"]), def["name"], def["org"], def["kind"], p, int(def["slots"]), false)
	for t in def["vehicles"]:
		add_vehicle(id, t)
	State.stations[id]["staff"] = Personnel.compute_staff(id)
	State.touch_station(id)

static func _create_station(id: String, nr: int, name: String, org: String, kind: String, p: Vector2, slots: int, custom: bool) -> void:
	var node := World.nearest_node(p)
	var np: Vector2 = World.node_pos[node]
	if p.distance_to(np) > 60.0:
		p = np + (p - np).normalized() * 40.0
	State.stations[id] = {
		"id": id, "nr": nr, "name": name, "org": org, "kind": kind, "x": p.x, "y": p.y, "node": node,
		"slots": slots, "address": World.address_at(p)["text"], "staff": {}, "custom": custom,
	}

static func new_station(name: String, org: String, kind: String, p: Vector2, slots: int) -> String:
	var n := State.next_id("st")
	var id := "st_c%d" % n
	var nr := 40 + n
	_create_station(id, nr, name, org, kind, p, slots, true)
	State.touch_station(id)
	return id

static func make_callsign(st: Dictionary, type_id: String, exclude := "") -> String:
	var t: Dictionary = Data.vehicle_types[type_id]
	var pattern: String = Data.organisations[t["org"]]["callsign"]
	var used := {}
	for vid in State.vehicles:
		if vid != exclude:
			used[State.vehicles[vid]["callsign"]] = true
	for n in range(1, 60):
		var cs := pattern.replace("{nr}", str(int(st["nr"]))).replace("{kenn}", String(t.get("kenn", ""))).replace("{n}", str(n))
		if not used.has(cs):
			return cs
	return pattern

static func add_vehicle(st_id: String, type_id: String) -> String:
	var st: Dictionary = State.stations[st_id]
	var t: Dictionary = Data.vehicle_types[type_id]
	var id := "v%04d" % State.next_id("veh")
	State.vehicles[id] = {
		"id": id, "type": type_id, "callsign": make_callsign(st, type_id), "station": st_id, "org": t["org"],
		"status": 2, "prev_status": 2, "state": "station", "x": st["x"], "y": st["y"], "heading": 0.0,
		"incident": "", "last_incident": "", "route": [], "ri": 0, "rt": 0.0, "pre": false, "emergency": false,
		"dest_kind": "", "dest_name": "", "dx": st["x"], "dy": st["y"], "eta": 0.0, "timer": 0.0,
		"crew": {}, "talk": "", "talk_t": 0.0, "patient": -1, "hospital": "", "km": 0.0, "runs": 0,
	}
	State.touch_vehicle(id)
	return id

static func free_slots(st_id: String) -> int:
	return int(State.stations[st_id]["slots"]) - State.station_vehicles(st_id).size()

## Fahrzeug dauerhaft einer anderen Wache zuordnen (nur wenn es auf der Wache steht).
static func move_vehicle(vid: String, st_id: String) -> String:
	var v: Dictionary = State.vehicles[vid]
	if v["state"] != "station" and v["state"] != "oos":
		return "Fahrzeug muss auf der Wache stehen (Status 2 oder 6)."
	var st: Dictionary = State.stations[st_id]
	if st["org"] != v["org"]:
		return "Fahrzeug und Wache gehören nicht zur selben Organisation."
	if free_slots(st_id) <= 0:
		return "Kein freier Stellplatz auf der Zielwache."
	var old: String = v["station"]
	v["station"] = st_id
	v["x"] = st["x"]
	v["y"] = st["y"]
	v["callsign"] = make_callsign(st, v["type"], vid)
	State.stations[old]["staff"] = Personnel.compute_staff(old)
	st["staff"] = Personnel.compute_staff(st_id)
	State.touch_vehicle(vid)
	State.touch_station(old)
	State.touch_station(st_id)
	return ""

static func remove_vehicle(vid: String) -> String:
	var v: Dictionary = State.vehicles[vid]
	if v["state"] != "station" and v["state"] != "oos":
		return "Fahrzeug muss auf der Wache stehen."
	var st_id: String = v["station"]
	State.remove_vehicle(vid)
	State.stations[st_id]["staff"] = Personnel.compute_staff(st_id)
	State.touch_station(st_id)
	return ""

static func remove_station(st_id: String) -> String:
	if State.station_vehicles(st_id).size() > 0:
		return "Wache besitzt noch Fahrzeuge."
	if not State.meta.has("removed_stations"):
		State.meta["removed_stations"] = []
	State.meta["removed_stations"].append(st_id)
	State.remove_station(st_id)
	return ""
