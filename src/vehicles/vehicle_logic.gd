extends RefCounted
## Fahrzeug-Statuslogik und Bewegung entlang des Straßennetzes (nur Host).
## Zustände: station, alarmed, enroute, onscene, transport, hospital, returning, oos.

const Personnel = preload("res://src/personnel/personnel.gd")

static func vtype(v: Dictionary) -> Dictionary:
	return Data.vehicle_types[v["type"]]

static func caps(v: Dictionary) -> Dictionary:
	return vtype(v).get("caps", {})

static func has_cap(v: Dictionary, cap: String) -> bool:
	return int(caps(v).get(cap, 0)) > 0

static func is_dispatchable(v: Dictionary) -> bool:
	if v["incident"] != "":
		return false
	if v["state"] != "station" and v["state"] != "returning":
		return false
	return int(v["status"]) == 1 or int(v["status"]) == 2

## Grund, warum ein Fahrzeug nicht alarmierbar ist ("" = alarmierbar).
static func block_reason(v: Dictionary) -> String:
	if v["state"] == "oos":
		return "Außer Dienst (Status 6)"
	if v["incident"] != "" or not is_dispatchable(v):
		return "Im Einsatz (Status %d)" % int(v["status"])
	if v["state"] == "station" and not Personnel.can_staff(v):
		return "Besatzung nicht verfügbar"
	return ""

static func turnout(v: Dictionary) -> float:
	var tt: Dictionary = Data.modes.get("turnout", {})
	var key: String = "road"
	if v["state"] == "station":
		key = State.stations[v["station"]]["kind"]
	var r: Array = tt.get(key, [45, 90])
	return Sim.rng.randf_range(float(r[0]), float(r[1]))

static func turnout_mean(v: Dictionary) -> float:
	var tt: Dictionary = Data.modes.get("turnout", {})
	var key: String = "road"
	if v["state"] == "station":
		key = State.stations[v["station"]]["kind"]
	var r: Array = tt.get(key, [45, 90])
	return (float(r[0]) + float(r[1])) * 0.5

static func set_status(v: Dictionary, status: int, announce := true) -> void:
	v["status"] = status
	if announce:
		var phrase: String = Data.fms.get("radio_phrases", {}).get(str(status), "")
		Sim.radio(v["callsign"], phrase, status, "status", v["incident"] if v["incident"] != "" else v["last_incident"])
	State.touch_vehicle(v["id"])

static func alarm(v: Dictionary, inc_id: String) -> String:
	var why := block_reason(v)
	if why != "":
		return why
	if v["state"] == "station":
		var crew := Personnel.plan_crew(v)
		if crew.is_empty():
			return "Besatzung nicht verfügbar"
		v["crew"] = crew
	v["timer"] = turnout(v)
	v["from_station"] = v["state"] == "station"
	v["incident"] = inc_id
	v["state"] = "alarmed"
	v["emergency"] = true
	v["runs"] = int(v["runs"]) + 1
	var inc: Dictionary = State.incidents[inc_id]
	v["dest_kind"] = "einsatz"
	v["dest_name"] = inc["address"]
	v["eta"] = 0.0
	set_status(v, 9, false)
	return ""

static func node_of(v: Dictionary) -> int:
	if v["state"] == "station" or v["state"] == "oos" or (v["state"] == "alarmed" and v.get("from_station", false)):
		return int(State.stations[v["station"]]["node"])
	return World.access_node(State.veh_pos(v))

static func start_route(v: Dictionary, to_node: int, emergency: bool, dest: Vector2) -> bool:
	var from := node_of(v)
	var r := World.find_path(from, to_node, emergency)
	if not r["ok"]:
		r = World.find_path(from, to_node, emergency, true)
		if not r["ok"]:
			return false
	var nodes: PackedInt32Array = r["nodes"]
	var route: Array = []
	for n in nodes:
		route.append(n)
	v["route"] = route
	v["ri"] = 0
	v["rt"] = 0.0
	v["pre"] = State.veh_pos(v).distance_to(World.node_pos[from]) > 12.0
	v["emergency"] = emergency
	v["dx"] = dest.x
	v["dy"] = dest.y
	var vmax: float = float(vtype(v)["speed"]) / 3.6
	var slow: float = max(1.0, (float(r["dist"]) / max(1.0, float(r["time"]))) / vmax)
	v["eta"] = State.clock + float(r["time"]) * slow
	return true

static func _depart(v: Dictionary) -> void:
	var inc_id: String = v["incident"]
	if not State.incidents.has(inc_id):
		send_home(v)
		return
	var inc: Dictionary = State.incidents[inc_id]
	if not start_route(v, int(inc["node"]), true, Vector2(inc["x"], inc["y"])):
		Sim.radio(v["callsign"], "Einsatzstelle nicht anfahrbar, brechen ab.", 1, "funk", inc_id)
		send_home(v)
		return
	v["state"] = "enroute"
	v["dest_kind"] = "einsatz"
	v["dest_name"] = inc["address"]
	set_status(v, 3)

static func redirect_to_incident(v: Dictionary) -> void:
	var inc: Dictionary = State.incidents[v["incident"]]
	if start_route(v, int(inc["node"]), true, Vector2(inc["x"], inc["y"])):
		v["state"] = "enroute"
		v["dest_name"] = inc["address"]
		set_status(v, 3, false)

## Fahrzeug aus dem Einsatz lösen und einrücken lassen.
static func send_home(v: Dictionary, announce := true) -> void:
	var st: Dictionary = State.stations[v["station"]]
	if v["incident"] != "":
		v["last_incident"] = v["incident"]
	v["incident"] = ""
	v["patient"] = -1
	v["talk"] = ""
	v["dest_kind"] = "wache"
	v["dest_name"] = st["name"]
	if v["state"] == "alarmed" and v.get("from_station", false):
		_at_station(v, false)
		return
	if not start_route(v, int(st["node"]), false, Vector2(st["x"], st["y"])):
		_at_station(v, announce)
		return
	v["state"] = "returning"
	set_status(v, 1, announce)

static func _at_station(v: Dictionary, announce := true) -> void:
	var st: Dictionary = State.stations[v["station"]]
	v["state"] = "station"
	v["x"] = st["x"]
	v["y"] = st["y"]
	v["route"] = []
	v["crew"] = {}
	v["emergency"] = false
	v["dest_kind"] = ""
	v["dest_name"] = ""
	v["eta"] = 0.0
	set_status(v, 2, announce)

static func start_transport(v: Dictionary, hospital: Dictionary) -> bool:
	if not start_route(v, int(hospital["node"]), true, hospital["p"]):
		return false
	v["last_incident"] = v["incident"]
	v["incident"] = ""
	v["state"] = "transport"
	v["hospital"] = hospital["id"]
	v["dest_kind"] = "klinik"
	v["dest_name"] = hospital["name"]
	v["patient"] = -1
	set_status(v, 7)
	return true

static func set_oos(v: Dictionary, oos: bool) -> String:
	if oos:
		if v["state"] != "station":
			return "Status 6 kann nur auf der Wache gesetzt werden."
		v["state"] = "oos"
		set_status(v, 6)
	else:
		if v["state"] != "oos":
			return "Fahrzeug ist nicht außer Dienst."
		v["state"] = "station"
		set_status(v, 2)
	return ""

static func request_talk(v: Dictionary, text: String) -> void:
	if v["talk"] != "":
		v["talk"] = String(v["talk"]) + " – " + text
	else:
		v["talk"] = text
		v["talk_t"] = State.clock
		v["prev_status"] = v["status"]
	v["status"] = 5
	Sim.radio(v["callsign"], "", 5, "status", v["incident"])
	Sim.sound("talk")
	State.touch_vehicle(v["id"])

static func ack_talk(v: Dictionary, by: String) -> void:
	if v["talk"] == "":
		return
	Sim.radio("Leitstelle", "%s von Leitstelle, kommen." % v["callsign"], -1, "funk", v["incident"])
	Sim.radio(v["callsign"], v["talk"], -1, "funk", v["incident"])
	v["talk"] = ""
	if int(v["status"]) == 5:
		v["status"] = v["prev_status"]
	State.touch_vehicle(v["id"])

# ---------------------------------------------------------------- Tick
static func tick(h: float) -> void:
	for id in State.vehicles:
		var v: Dictionary = State.vehicles[id]
		match v["state"]:
			"station", "oos", "onscene":
				pass
			"alarmed":
				v["timer"] = float(v["timer"]) - h
				if float(v["timer"]) <= 0.0:
					_depart(v)
			"hospital":
				v["timer"] = float(v["timer"]) - h
				if float(v["timer"]) <= 0.0:
					v["hospital"] = ""
					send_home(v)
			_:
				_move(v, h)
		if v["talk"] != "" and State.clock - float(v["talk_t"]) > 150.0:
			State.meta["stats"]["talk_ignored"] = int(State.meta["stats"].get("talk_ignored", 0)) + 1
			Sim.radio(v["callsign"], "Leitstelle für %s – wiederhole: %s" % [v["callsign"], v["talk"]], -1, "funk", v["incident"])
			v["talk"] = ""
			if int(v["status"]) == 5:
				v["status"] = v["prev_status"]
			State.touch_vehicle(id)

static func _move(v: Dictionary, h: float) -> void:
	var route: Array = v["route"]
	var vmax: float = float(vtype(v)["speed"]) / 3.6
	var emergency: bool = v["emergency"]
	var remaining := h
	var pos := State.veh_pos(v)
	if v["pre"] and route.size() > 0:
		var target: Vector2 = World.node_pos[int(route[0])]
		var d := pos.distance_to(target)
		var sp: float = min(vmax, 14.0 if emergency else 9.0)
		if sp * remaining >= d:
			remaining -= d / sp
			pos = target
			v["pre"] = false
		else:
			var dir := (target - pos) / d
			pos += dir * sp * remaining
			v["heading"] = dir.angle()
			v["x"] = pos.x
			v["y"] = pos.y
			return
	var ri := int(v["ri"])
	var rt := float(v["rt"])
	var moved := 0.0
	while remaining > 0.0 and ri < route.size() - 1:
		var a := int(route[ri])
		var b := int(route[ri + 1])
		var e := World.edge_between(a, b)
		if e < 0:
			ri += 1
			rt = 0.0
			continue
		if rt <= 0.0 and World.edge_block[e] != 0 and ri < route.size() - 2:
			# Sperrung voraus: neu routen
			v["x"] = World.node_pos[a].x
			v["y"] = World.node_pos[a].y
			var r := World.find_path(a, int(route[route.size() - 1]), emergency)
			if r["ok"]:
				var nr: Array = []
				for n in r["nodes"]:
					nr.append(n)
				route = nr
				v["route"] = nr
				ri = 0
				State.touch_vehicle(v["id"])
				continue
		var sp: float = min(vmax, World.edge_speed(e, emergency))
		var left: float = World.edge_len[e] - rt
		if sp * remaining >= left:
			remaining -= left / sp
			moved += left
			ri += 1
			rt = 0.0
		else:
			rt += sp * remaining
			moved += sp * remaining
			remaining = 0.0
	v["ri"] = ri
	v["rt"] = rt
	v["km"] = float(v["km"]) + moved / 1000.0
	if ri >= route.size() - 1:
		_arrive(v)
		return
	var pa: Vector2 = World.node_pos[int(route[ri])]
	var pb: Vector2 = World.node_pos[int(route[ri + 1])]
	var e2 := World.edge_between(int(route[ri]), int(route[ri + 1]))
	var t: float = rt / World.edge_len[e2] if e2 >= 0 else 0.0
	var np := pa.lerp(pb, t)
	v["heading"] = (pb - pa).angle()
	v["x"] = np.x
	v["y"] = np.y

static func _arrive(v: Dictionary) -> void:
	v["route"] = []
	v["x"] = v["dx"]
	v["y"] = v["dy"]
	v["eta"] = 0.0
	match v["state"]:
		"enroute":
			v["state"] = "onscene"
			v["emergency"] = false
			set_status(v, 4)
		"transport":
			v["state"] = "hospital"
			v["emergency"] = false
			v["timer"] = Sim.rng.randf_range(420.0, 840.0)
			set_status(v, 8)
		_:
			_at_station(v)
