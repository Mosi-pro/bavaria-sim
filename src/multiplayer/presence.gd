extends Node
## Präsenz in der begehbaren Leitstelle (Mehrspieler, Host-autoritativ):
## Spielerpositionen und Blickrichtungen, Belegung der Arbeits- und Sitzplätze,
## Zustand von Türen und Geräten (Kühlschrank, Kochfeld).
##
## Die Leitstellenlogik selbst (Einsätze, Fahrzeuge, Alarmierungen) läuft unverändert über
## Game.act → Sim.act bzw. Net; hier wird nur die räumliche Anwesenheit abgeglichen.

signal seats_changed
signal toggles_changed
signal seat_denied(seat, text)

const Layout = preload("res://src/building/layout.gd")
const POSE_HZ := 10.0
const ITEM_NONE := 0
const ITEM_COFFEE := 1
const ITEM_WATER := 2
const ITEM_FOOD := 3

var seats := {}          # Platz-ID -> Peer-ID
var toggles := {}        # Tür-/Geräte-ID -> bool
var poses := {}          # Peer-ID -> {p: Vector3, yaw, pitch, item, t}
var want_seat := ""      # Platz, den dieser Spieler belegt (für Wiederverbindung)
var local_pose := {}     # eigene Pose (wird von der 3D-Ansicht gesetzt)
var _send_t := 0.0
var _bcast_t := 0.0
var _sync_t := 0.0
var _rate := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	Net.lobby_changed.connect(func():
		if Net.mode == Net.MODE_HOST:
			_broadcast_state())
	Net.connect_result.connect(_on_connect_result)
	Game.session_ended.connect(func(_r): reset())

func reset() -> void:
	seats = {}
	toggles = {}
	poses = {}
	want_seat = ""
	local_pose = {}
	seats_changed.emit()
	toggles_changed.emit()

func me() -> int:
	return Net.my_id()

func owner_of(seat: String) -> int:
	return int(seats.get(seat, 0))

func my_seat() -> String:
	for s in seats:
		if int(seats[s]) == me():
			return s
	return ""

func player_name(pid: int) -> String:
	if pid == me():
		return String(Game.me.get("name", "Disponent"))
	if Net.players.has(pid):
		return String(Net.players[pid].get("name", "Spieler"))
	if State.players.has(pid):
		return String(State.players[pid].get("name", "Spieler"))
	return "Spieler %d" % pid

static func valid_id(id: String) -> bool:
	if id.length() < 1 or id.length() > 16:
		return false
	for ch in id:
		if not (ch >= "a" and ch <= "z") and not (ch >= "0" and ch <= "9") and ch != "_":
			return false
	return true

# ------------------------------------------------------------------ Plätze
func request_seat(seat: String) -> void:
	want_seat = seat
	if Net.mode == Net.MODE_CLIENT:
		s_seat.rpc_id(1, seat, true)
	else:
		_apply_seat(me(), seat, true)

func release_seat() -> void:
	var s := my_seat()
	want_seat = ""
	if Net.mode == Net.MODE_CLIENT:
		s_seat.rpc_id(1, s, false)
	else:
		_apply_seat(me(), s, false)

@rpc("any_peer", "call_remote", "reliable")
func s_seat(seat: String, take: bool) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if Net.mode != Net.MODE_HOST or not Net.players.has(pid) or not _allow(pid, 12):
		return
	_apply_seat(pid, seat, take)

## Host (bzw. Einzelplatz): Platz vergeben oder freigeben. Jeder Platz hat höchstens einen
## Inhaber, jeder Spieler höchstens einen Platz.
func _apply_seat(pid: int, seat: String, take: bool) -> void:
	if take:
		if not valid_id(seat):
			return
		var holder := owner_of(seat)
		if holder != 0 and holder != pid:
			_deny(pid, seat, "%s ist bereits belegt (%s)." % [_seat_title(seat), player_name(holder)])
			return
		for s in seats.keys():
			if int(seats[s]) == pid and s != seat:
				seats.erase(s)
		seats[seat] = pid
	else:
		for s in seats.keys():
			if int(seats[s]) == pid:
				seats.erase(s)
	_broadcast_state()

func _seat_title(seat: String) -> String:
	if seat.begins_with("ws"):
		return "Arbeitsplatz " + seat.substr(2)
	if seat.begins_with("sf"):
		return "Schichtführungsplatz " + seat.substr(2)
	return "Der Platz"

func _deny(pid: int, seat: String, text: String) -> void:
	if pid == me():
		if want_seat == seat:
			want_seat = ""
		seat_denied.emit(seat, text)
	elif Net.mode == Net.MODE_HOST:
		c_seat_denied.rpc_id(pid, seat, text)

@rpc("authority", "call_remote", "reliable")
func c_seat_denied(seat: String, text: String) -> void:
	if want_seat == seat:
		want_seat = ""
	seat_denied.emit(seat, text)

# ------------------------------------------------------------------ Türen und Geräte
func set_toggle(id: String, value: bool) -> void:
	if Net.mode == Net.MODE_CLIENT:
		s_toggle.rpc_id(1, id, value)
	else:
		_apply_toggle(id, value)

@rpc("any_peer", "call_remote", "reliable")
func s_toggle(id: String, value: bool) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if Net.mode != Net.MODE_HOST or not Net.players.has(pid) or not _allow(pid, 12):
		return
	_apply_toggle(id, value)

func _apply_toggle(id: String, value: bool) -> void:
	if not valid_id(id) or (toggles.size() >= 64 and not toggles.has(id)):
		return
	toggles[id] = value
	_broadcast_state()

func is_on(id: String) -> bool:
	return bool(toggles.get(id, false))

# ------------------------------------------------------------------ Abgleich
func _broadcast_state() -> void:
	seats_changed.emit()
	toggles_changed.emit()
	if Net.mode != Net.MODE_HOST:
		return
	for pid in Net._auth_ids():
		c_state.rpc_id(pid, seats, toggles)

@rpc("authority", "call_remote", "reliable")
func c_state(s: Dictionary, t: Dictionary) -> void:
	seats = {}
	for k in s:
		seats[String(k)] = int(s[k])
	toggles = {}
	for k in t:
		toggles[String(k)] = bool(t[k])
	seats_changed.emit()
	toggles_changed.emit()

## Eigene Pose (Position der Füße, Blickrichtung, gehaltener Gegenstand) setzen.
func set_local_pose(p: Vector3, yaw: float, pitch: float, item: int) -> void:
	local_pose = {"p": p, "yaw": yaw, "pitch": pitch, "item": item}

@rpc("any_peer", "call_remote", "unreliable_ordered")
func s_pose(d: PackedFloat32Array) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if Net.mode != Net.MODE_HOST or not Net.players.has(pid) or d.size() != 6 or not _allow(pid, 40, "pose"):
		return
	_store_pose(pid, d)

func _store_pose(pid: int, d: PackedFloat32Array) -> void:
	var b := Layout.BOUNDS
	var p := Vector3(clampf(d[0], b.position.x, b.end.x), clampf(d[1], b.position.y, b.end.y), clampf(d[2], b.position.z, b.end.z))
	if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
		return
	poses[pid] = {"p": p, "yaw": wrapf(d[3], -PI, PI), "pitch": clampf(d[4], -1.5, 1.5), "item": clampi(int(d[5]), 0, 3), "t": Time.get_ticks_msec()}

@rpc("authority", "call_remote", "unreliable_ordered")
func c_poses(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if data.size() != ids.size() * 6:
		return
	var seen := {}
	for i in ids.size():
		var pid := ids[i]
		if pid == me():
			continue
		seen[pid] = true
		_store_pose(pid, data.slice(i * 6, i * 6 + 6))
	for pid in poses.keys():
		if not seen.has(pid):
			poses.erase(pid)

func _pack(pose: Dictionary) -> PackedFloat32Array:
	var p: Vector3 = pose["p"]
	return PackedFloat32Array([p.x, p.y, p.z, float(pose["yaw"]), float(pose["pitch"]), float(pose["item"])])

func _process(delta: float) -> void:
	var online_game := (Net.mode == Net.MODE_HOST and Net._started) or (Net.mode == Net.MODE_CLIENT and Net._in_game and Net._authed)
	if not online_game:
		return
	_send_t += delta
	if Net.mode == Net.MODE_CLIENT:
		if _send_t >= 1.0 / POSE_HZ and not local_pose.is_empty():
			_send_t = 0.0
			s_pose.rpc_id(1, _pack(local_pose))
		return
	# Host: eigene Pose eintragen, alle Posen verteilen, Zustand regelmäßig abgleichen
	if not local_pose.is_empty():
		poses[1] = local_pose.duplicate()
		poses[1]["t"] = Time.get_ticks_msec()
	if _send_t >= 1.0 / POSE_HZ:
		_send_t = 0.0
		var now := Time.get_ticks_msec()
		var ids := PackedInt32Array()
		var data := PackedFloat32Array()
		for pid in poses.keys():
			if pid != 1 and (not Net.players.has(pid) or now - int(poses[pid]["t"]) > 10000):
				poses.erase(pid)
				continue
			ids.append(pid)
			data.append_array(_pack(poses[pid]))
		for pid in Net._auth_ids():
			c_poses.rpc_id(pid, ids, data)
	_sync_t += delta
	if _sync_t >= 3.0:
		_sync_t = 0.0
		for pid in Net._auth_ids():
			c_state.rpc_id(pid, seats, toggles)

func _allow(pid: int, per_sec: int, kind := "act") -> bool:
	var key := "%d_%s" % [pid, kind]
	var now := Time.get_ticks_msec()
	var r: Array = _rate.get(key, [now, 0])
	if now - int(r[0]) > 1000:
		r = [now, 0]
	r[1] = int(r[1]) + 1
	_rate[key] = r
	return int(r[1]) <= per_sec

## Host: Spieler hat die Sitzung verlassen oder die Verbindung verloren → Platz freigeben.
func _on_peer_gone(pid: int) -> void:
	poses.erase(pid)
	_rate.erase("%d_act" % pid)
	_rate.erase("%d_pose" % pid)
	if Net.mode != Net.MODE_HOST:
		return
	var changed := false
	for s in seats.keys():
		if int(seats[s]) == pid:
			seats.erase(s)
			changed = true
	if changed:
		_broadcast_state()

## Client nach Wiederverbindung: neue Peer-ID → zuvor belegten Platz erneut anfordern.
func _on_connect_result(ok: bool, _text: String) -> void:
	if ok and Net.mode == Net.MODE_CLIENT and want_seat != "":
		s_seat.rpc_id(1, want_seat, true)
