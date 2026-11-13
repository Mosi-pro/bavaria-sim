extends Node
## Zentraler Spielzustand (reine Daten). Auf dem Host wird er von der Simulation
## verändert, auf Clients vom Netzwerkmodul gespiegelt. Die Oberfläche liest
## ausschließlich aus diesem Zustand und reagiert auf dessen Signale.

signal reset_done
signal incident_changed(id)
signal incident_removed(id)
signal call_changed(id)
signal call_removed(id)
signal vehicle_changed(id)
signal vehicle_removed(id)
signal station_changed(id)
signal station_removed(id)
signal radio_added(entry)
signal chat_added(entry)
signal env_changed
signal meta_changed
signal players_changed
signal notice(text, level)

const VERSION := 1

var stations: Dictionary = {}
var vehicles: Dictionary = {}
var incidents: Dictionary = {}
var calls: Dictionary = {}
var truths: Dictionary = {}      # nur Host: tatsächliche Lagen (verdeckt)
var archive: Array = []
var radio: Array = []
var chat: Array = []
var clock: float = 0.0
var env: Dictionary = {}
var meta: Dictionary = {}
var players: Dictionary = {}
var active := false

func _ready() -> void:
	reset()

func reset() -> void:
	stations = {}
	vehicles = {}
	incidents = {}
	calls = {}
	truths = {}
	archive = []
	radio = []
	chat = []
	clock = 0.0
	env = {"weather": "klar", "traffic": 1.0, "jams": {}, "closures": {}, "sites": {}, "events": [], "hour_done": -1}
	meta = {
		"version": VERSION, "name": "", "mode": "frei", "difficulty": "mittel", "scenario": "",
		"start_unix": 0, "speed": 2.0, "paused": false, "seq": {"inc": 0, "call": 0, "veh": 0, "truth": 0, "st": 0},
		"budget": 0, "xp": 0, "level": 1, "zones": [1, 2, 3, 4, 5], "orgs": ["fw", "rd", "pol", "kats", "thw", "wr"],
		"stats": {"calls": 0, "calls_missed": 0, "calls_nuisance": 0, "incidents": 0, "done": 0, "score_sum": 0.0, "deaths": 0, "resp_sum": 0.0, "resp_n": 0, "saved": 0},
		"scenario_done": [], "scenario_over": false,
	}
	players = {}
	active = false
	if World.built:
		World.reset_dynamic()
	reset_done.emit()

func next_id(kind: String) -> int:
	var seq: Dictionary = meta["seq"]
	seq[kind] = int(seq.get(kind, 0)) + 1
	return seq[kind]

# ---------------------------------------------------------------- Zeit
func game_unix(t: float = -1.0) -> int:
	return int(meta["start_unix"]) + int(clock if t < 0.0 else t)

func hour() -> int:
	return Time.get_datetime_dict_from_unix_time(game_unix())["hour"]

func hour_f() -> float:
	var d := Time.get_datetime_dict_from_unix_time(game_unix())
	return float(d["hour"]) + float(d["minute"]) / 60.0

func time_str(t: float = -1.0) -> String:
	var d := Time.get_datetime_dict_from_unix_time(game_unix(t))
	return "%02d:%02d:%02d" % [d["hour"], d["minute"], d["second"]]

func date_str(t: float = -1.0) -> String:
	var d := Time.get_datetime_dict_from_unix_time(game_unix(t))
	var wd: String = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][d["weekday"]]
	return "%s %02d.%02d.%04d" % [wd, d["day"], d["month"], d["year"]]

static func dur_str(sec: float) -> String:
	var s := int(max(0.0, sec))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]

# ---------------------------------------------------------------- Änderungen melden
func touch_incident(id: String) -> void:
	incident_changed.emit(id)

func touch_call(id: String) -> void:
	call_changed.emit(id)

func touch_vehicle(id: String) -> void:
	vehicle_changed.emit(id)

func touch_station(id: String) -> void:
	station_changed.emit(id)

func remove_incident(id: String) -> void:
	incidents.erase(id)
	incident_removed.emit(id)

func remove_call(id: String) -> void:
	calls.erase(id)
	call_removed.emit(id)

func remove_vehicle(id: String) -> void:
	vehicles.erase(id)
	vehicle_removed.emit(id)

func remove_station(id: String) -> void:
	stations.erase(id)
	station_removed.emit(id)

func add_radio(entry: Dictionary) -> void:
	radio.append(entry)
	if radio.size() > 3000:
		radio = radio.slice(radio.size() - 2500)
	radio_added.emit(entry)

func add_chat(entry: Dictionary) -> void:
	chat.append(entry)
	if chat.size() > 500:
		chat = chat.slice(chat.size() - 400)
	chat_added.emit(entry)

func veh_pos(v: Dictionary) -> Vector2:
	return Vector2(v["x"], v["y"])

func station_vehicles(st_id: String) -> Array:
	var out: Array = []
	for id in vehicles:
		if vehicles[id]["station"] == st_id:
			out.append(id)
	out.sort()
	return out

func incident_vehicles(inc_id: String) -> Array:
	var out: Array = []
	for id in vehicles:
		if vehicles[id]["incident"] == inc_id:
			out.append(id)
	out.sort()
	return out

## Überträgt Sperrungen, Staus und Baustellen aus env in den Straßengraphen.
func apply_env() -> void:
	if not World.built:
		return
	World.edge_block.fill(0)
	World.edge_traffic.fill(1.0)
	var ne := World.edge_a.size()
	for k in env.get("sites", {}):
		var e := int(k)
		if e < ne:
			World.edge_traffic[e] = 1.9
	for k in env.get("jams", {}):
		var e := int(k)
		if e < ne:
			World.edge_traffic[e] = max(World.edge_traffic[e], float(env["jams"][k]))
	for k in env.get("closures", {}):
		var e := int(k)
		if e < ne:
			World.edge_block[e] = 1
	World.traffic_level = float(env.get("traffic", 1.0))
	var wd: Dictionary = Data.modes.get("weather", {}).get(env.get("weather", "klar"), {})
	World.speed_scale = float(wd.get("speed", 1.0))
	World.recompute_times()

# ---------------------------------------------------------------- Serialisierung
func to_dict(include_hidden := true) -> Dictionary:
	var d := {
		"version": VERSION, "stations": stations, "vehicles": vehicles, "incidents": incidents, "calls": calls,
		"archive": archive, "radio": radio.slice(max(0, radio.size() - 600)), "chat": chat, "clock": clock, "env": env, "meta": meta,
	}
	if include_hidden:
		d["truths"] = truths
	else:
		d["calls"] = {}
		for id in calls:
			d["calls"][id] = public_call(calls[id])
		d["truths"] = {}
	return d.duplicate(true)

func from_dict(d: Dictionary) -> void:
	reset()
	stations = d.get("stations", {})
	vehicles = d.get("vehicles", {})
	incidents = d.get("incidents", {})
	calls = d.get("calls", {})
	truths = d.get("truths", {})
	archive = d.get("archive", [])
	radio = d.get("radio", [])
	chat = d.get("chat", [])
	clock = d.get("clock", 0.0)
	var e: Dictionary = d.get("env", {})
	for k in e:
		env[k] = e[k]
	var m: Dictionary = d.get("meta", {})
	for k in m:
		meta[k] = m[k]
	active = true
	apply_env()
	reset_done.emit()

## Notruf ohne verdeckte Informationen (für Clients).
func public_call(c: Dictionary) -> Dictionary:
	var p: Dictionary = c.duplicate(true)
	p.erase("truth")
	p.erase("true_pos")
	p.erase("pending")
	return p
