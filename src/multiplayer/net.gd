extends Node
## Mehrspieler über Godot ENet (Peer-to-Peer mit Host-Autorität).
## Der PC des Hosts führt die Simulation aus; Clients senden ausschließlich Aktionen,
## die der Host gegen Authentifizierung, Rolle und Spielzustand prüft.

const Areas = preload("res://src/simulation/areas.gd")
const Auth = preload("res://src/multiplayer/auth.gd")
const Discovery = preload("res://src/multiplayer/discovery.gd")
const RelayPeer = preload("res://src/multiplayer/relay_peer.gd")

const MODE_NONE := 0
const MODE_HOST := 1
const MODE_CLIENT := 2
const PROTOCOL := 4
const CHUNK := 48000
const MOVING := ["enroute", "transport", "returning", "alarmed"]

signal lobby_changed
signal lobby_chat(who, text)
signal connect_result(ok, text)
signal connection_lost(text)
signal reconnecting(attempt, max_attempts)
signal game_started
signal servers_changed
signal upnp_result(text)
signal relay_hosted(code)
signal host_failed(text)
signal internet_list(sessions, error)

var mode := MODE_NONE
var session := {}
var players := {}            # peer_id -> {name, role, token}
var discovery := Discovery.new()
var status_text := "Einzelplatz"
var last_ping := -1

var _peer: MultiplayerPeer
var via_relay := false
var relay_code := ""
var _dir_ws: WebSocketPeer
var _dir_t := 0.0
var _dir_sent := false
var _pw_salt := PackedByteArray()
var _pw_key := PackedByteArray()
var _pending := {}           # Host: peer_id -> {nonce, t}
var _tokens := {}            # Host: token -> role (für Wiederverbindung)
var _token_areas := {}       # Host: token -> Gebiete (für Wiederverbindung)
var _fails := {}             # Host: ip -> [anzahl, sperre_bis_ms]
var _rate := {}              # Host: peer_id -> [fensterstart_ms, anzahl]
var _dirty := {"inc": {}, "call": {}, "veh": {}, "st": {}}
var _flush_t := 0.0
var _pos_t := 0.0
var _started := false
# Client
var _join := {}              # ip, port, password, token
var _authed := false
var _chunks: Array = []
var _chunk_total := 0
var _chunk_size := 0
var _req := 0
var _callbacks := {}
var _targets := {}
var _reconnect_n := 0
var _reconnect_t := -1.0
var _expect_close := false
var _in_game := false
var _upnp_thread: Thread

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	State.incident_changed.connect(func(id): _mark("inc", id))
	State.incident_removed.connect(func(id): _event("inc_del", id, null))
	State.call_changed.connect(func(id): _mark("call", id))
	State.call_removed.connect(func(id): _event("call_del", id, null))
	State.vehicle_changed.connect(func(id): _mark("veh", id))
	State.vehicle_removed.connect(func(id): _event("veh_del", id, null))
	State.station_changed.connect(func(id): _mark("st", id))
	State.station_removed.connect(func(id): _event("st_del", id, null))
	State.radio_added.connect(func(e): _event("radio", "", e))
	State.chat_added.connect(func(e): _event("chat", "", e))
	State.env_changed.connect(func(): _event("env", "", State.env))
	State.meta_changed.connect(func(): _event("meta", "", _public_meta()))
	State.notice.connect(func(text, level): _event("notice", level, text))
	Sim.sound_requested.connect(func(name): _event("sound", name, null))

func is_online() -> bool:
	return mode != MODE_NONE

func my_id() -> int:
	return multiplayer.get_unique_id() if mode != MODE_NONE else 1

func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.find(":") < 0 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out

# ================================================================= HOST
func host(opts: Dictionary) -> String:
	shutdown()
	var port := int(opts.get("port", Settings.get_v("net", "port")))
	var pw: String = opts.get("password", "")
	via_relay = bool(opts.get("relay", false))
	relay_code = ""
	session = {
		"name": String(opts.get("name", "Leitstelle Bavaria")).substr(0, 40), "host": Game.me["name"], "max": clampi(int(opts.get("max_players", 6)), 2, 8),
		"mode": opts.get("game_mode", "Freies Spiel"), "region": "Bavaria", "private": bool(opts.get("private", false)), "locked": pw != "", "port": port,
		"version": PROTOCOL, "relay": via_relay,
	}
	_started = bool(opts.get("started", false))
	players = {1: {"name": Game.me["name"], "role": "leitung", "token": "", "area": []}}
	Game.me["area"] = []
	if via_relay:
		var url := Data.relay_url()
		if url == "":
			return "Es ist kein Vermittlungsdienst eingetragen."
		var rp := RelayPeer.new()
		rp.relay_event.connect(_on_relay_event)
		if rp.start_host(url, _discovery_info()) != OK:
			return rp.error_text
		_peer = rp
	else:
		var ep := ENetMultiplayerPeer.new()
		var err := ep.create_server(port, clampi(int(opts.get("max_players", 6)), 2, 8) - 1 + 4)
		if err != OK:
			return "Der Spielport %d (UDP) konnte nicht geöffnet werden. Läuft bereits eine Sitzung?" % port
		_peer = ep
		discovery.start_host(_discovery_info(), port + 1, int(Settings.get_v("net", "discovery_port")))
	multiplayer.multiplayer_peer = _peer
	mode = MODE_HOST
	_pw_salt = Auth.random_bytes(16)
	_pw_key = Auth.derive(pw, _pw_salt) if pw != "" else PackedByteArray()
	Game.me["role"] = "leitung"
	Game.me["id"] = 1
	status_text = "Verbinde mit Vermittlung …" if via_relay else "Host · %d Spieler" % players.size()
	lobby_changed.emit()
	return ""

func _on_relay_event(op: String, d: Dictionary) -> void:
	match op:
		"hosted":
			relay_code = String(d.get("code", ""))
			session["code"] = relay_code
			status_text = "Host (Internet) · Code %s" % relay_code
			relay_hosted.emit(relay_code)
			lobby_changed.emit()
		"error":
			if mode == MODE_HOST and relay_code == "":
				var text := String(d.get("text", "Vermittlungsdienst nicht erreichbar."))
				shutdown()
				host_failed.emit(text)
		"host_gone":
			if mode == MODE_CLIENT:
				_expect_close = true
				_reconnect_n = 0
				var text := String(d.get("text", "Der Host hat die Sitzung beendet."))
				var was := _in_game
				_drop_peer()
				if was:
					connection_lost.emit(text)
				else:
					connect_result.emit(false, text)

func _discovery_info() -> Dictionary:
	var d: Dictionary = session.duplicate()
	d["players"] = players.size()
	d["started"] = _started
	return d

func _auth_ids() -> Array:
	var out: Array = []
	for id in players:
		if id != 1:
			out.append(id)
	return out

func _on_peer_connected(id: int) -> void:
	if mode != MODE_HOST:
		return
	var ip := "?"
	if _peer is ENetMultiplayerPeer:
		var pp: ENetPacketPeer = (_peer as ENetMultiplayerPeer).get_peer(id)
		ip = pp.get_remote_address() if pp != null else "?"
	elif _peer is RelayPeer:
		ip = (_peer as RelayPeer).peer_ip(id)
	var f: Array = _fails.get(ip, [0, 0])
	if int(f[1]) > Time.get_ticks_msec():
		c_reject.rpc_id(id, "Zu viele Fehlversuche. Bitte später erneut versuchen.")
		_kick_later(id)
		return
	var nonce := Auth.random_bytes(24)
	_pending[id] = {"nonce": nonce, "t": Time.get_ticks_msec(), "ip": ip}
	c_challenge.rpc_id(id, PROTOCOL, _pw_salt, nonce, not _pw_key.is_empty())

func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.6).timeout
	if _peer != null and mode == MODE_HOST and multiplayer.get_peers().has(id):
		_peer.disconnect_peer(id)

@rpc("any_peer", "call_remote", "reliable")
func s_auth(version: int, name: String, client_nonce: PackedByteArray, proof: PackedByteArray, token: String) -> void:
	if mode != MODE_HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _pending.has(id):
		return
	var p: Dictionary = _pending[id]
	_pending.erase(id)
	var reason := ""
	if version != PROTOCOL:
		reason = "Unterschiedliche Programmversionen (Host %d, Client %d)." % [PROTOCOL, version]
	elif players.size() >= int(session["max"]):
		reason = "Die Sitzung ist voll."
	elif not _pw_key.is_empty() and not Auth.verify(_pw_key, p["nonce"], client_nonce, proof):
		reason = "Falsches Passwort."
		var f: Array = _fails.get(p["ip"], [0, 0])
		f[0] = int(f[0]) + 1
		if int(f[0]) >= 4:
			f = [0, Time.get_ticks_msec() + 60000]
		_fails[p["ip"]] = f
	if reason != "":
		c_reject.rpc_id(id, reason)
		_kick_later(id)
		return
	_fails.erase(p["ip"])
	name = name.strip_edges().substr(0, 24)
	if name == "":
		name = "Disponent"
	var base := name
	var n := 2
	var taken := true
	while taken:
		taken = false
		for pid in players:
			if players[pid]["name"] == name:
				taken = true
				name = "%s (%d)" % [base, n]
				n += 1
	token = token.substr(0, 64)
	var role: String = _tokens.get(token, "disposition")
	var area: Array = _token_areas.get(token, [])
	players[id] = {"name": name, "role": role, "token": token, "area": area}
	if token != "":
		_tokens[token] = role
	c_accept.rpc_id(id, id, name, role, session, _started)
	_broadcast_lobby()
	if _started:
		_send_full_state(id)
		Sim.radio("Leitstelle", "%s hat den Arbeitsplatz übernommen (%s)." % [name, Data.roles.get(role, {}).get("name", role)], -1, "system", "")

func _broadcast_lobby() -> void:
	status_text = ("Host (Internet) · Code %s · %d Spieler" % [relay_code, players.size()]) if via_relay else "Host · %d Spieler" % players.size()
	discovery.update_info(_discovery_info())
	if _peer is RelayPeer:
		(_peer as RelayPeer).update_info(_discovery_info())
	var pub := {}
	for id in players:
		pub[id] = {"name": players[id]["name"], "role": players[id]["role"], "area": players[id].get("area", [])}
	for id in _auth_ids():
		c_lobby.rpc_id(id, pub, session)
	lobby_changed.emit()
	State.players = pub
	State.players_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	if mode != MODE_HOST:
		return
	_pending.erase(id)
	if players.has(id):
		var name: String = players[id]["name"]
		players.erase(id)
		if State.active:
			for cid in State.calls:
				var c: Dictionary = State.calls[cid]
				if c["taken_by"] == name and c["state"] == "active":
					c["state"] = "ringing"
					c["taken_by"] = ""
					c["wait"] = 0.0
					State.touch_call(cid)
			Sim.radio("Leitstelle", "Verbindung zu %s getrennt." % name, -1, "system", "")
		_broadcast_lobby()

func set_role(peer_id: int, role: String) -> void:
	if mode == MODE_HOST:
		_apply_role(peer_id, role)
	elif mode == MODE_CLIENT:
		s_set_role.rpc_id(1, role)

@rpc("any_peer", "call_remote", "reliable")
func s_set_role(role: String) -> void:
	if mode == MODE_HOST and players.has(multiplayer.get_remote_sender_id()):
		_apply_role(multiplayer.get_remote_sender_id(), role)

func _apply_role(peer_id: int, role: String) -> void:
	if not players.has(peer_id) or not Data.roles.has(role):
		return
	if role == "leitung" and peer_id != 1 and multiplayer.get_remote_sender_id() != 0:
		return   # Schichtführung vergibt nur der Host
	players[peer_id]["role"] = role
	if players[peer_id]["token"] != "":
		_tokens[players[peer_id]["token"]] = role
	if peer_id == 1:
		Game.me["role"] = role
	_broadcast_lobby()

## Mehrspieler-Gebiete: [] = ganze Stadt. Der Host teilt zu; Mitspieler dürfen ihr eigenes Gebiet wählen.
func set_area(peer_id: int, areas: Array) -> void:
	if mode == MODE_HOST:
		_apply_area(peer_id, areas)
	elif mode == MODE_CLIENT:
		s_set_area.rpc_id(1, areas)

@rpc("any_peer", "call_remote", "reliable")
func s_set_area(areas: Array) -> void:
	if mode == MODE_HOST and players.has(multiplayer.get_remote_sender_id()):
		_apply_area(multiplayer.get_remote_sender_id(), areas)

func _apply_area(peer_id: int, areas: Array, quiet := false) -> void:
	if not players.has(peer_id):
		return
	var clean: Array = []
	var valid: Dictionary = Data.modes.get("areas", {}).get("list", {})
	for a in areas:
		if valid.has(String(a)) and not clean.has(String(a)):
			clean.append(String(a))
	players[peer_id]["area"] = clean
	if players[peer_id]["token"] != "":
		_token_areas[players[peer_id]["token"]] = clean
	if peer_id == 1:
		Game.me["area"] = clean
	if not quiet:
		_broadcast_lobby()
	if _started and State.active:
		Sim.radio("Leitstelle", "%s ist zuständig für: %s." % [players[peer_id]["name"], Areas.names(clean)], -1, "system", "")

## Gebiete automatisch gleichmäßig auf alle Spieler verteilen (nur Host).
func auto_areas() -> void:
	if mode != MODE_HOST:
		return
	var ids: Array = players.keys()
	ids.sort()
	var parts: Array = Areas.distribute(ids.size())
	for i in ids.size():
		_apply_area(ids[i], parts[i], true)
	_broadcast_lobby()

func kick(peer_id: int) -> void:
	if mode == MODE_HOST and peer_id != 1 and players.has(peer_id):
		c_kick.rpc_id(peer_id, "Sie wurden vom Host aus der Sitzung entfernt.")
		_kick_later(peer_id)

## Host startet das Spiel für alle (Zustand muss bereits geladen/erzeugt sein).
func start_game() -> void:
	if mode != MODE_HOST:
		return
	var any_area := false
	for pid in players:
		if not players[pid].get("area", []).is_empty():
			any_area = true
	if not any_area and players.size() >= 2:
		auto_areas()
	_started = true
	discovery.update_info(_discovery_info())
	if _peer is RelayPeer:
		(_peer as RelayPeer).update_info(_discovery_info())
	for id in _auth_ids():
		_send_full_state(id)
	_broadcast_lobby()

func _send_full_state(id: int) -> void:
	var d := State.to_dict(false)
	var raw := var_to_bytes(d)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var total := int(ceil(float(packed.size()) / CHUNK))
	for i in total:
		c_state_chunk.rpc_id(id, i, total, raw.size(), packed.slice(i * CHUNK, min(packed.size(), (i + 1) * CHUNK)))

func _public_meta() -> Dictionary:
	return State.meta.duplicate(true)

func _mark(kind: String, id: String) -> void:
	if mode == MODE_HOST and _started:
		_dirty[kind][id] = true

func _event(kind: String, id: String, data) -> void:
	if mode != MODE_HOST or not _started:
		return
	for pid in _auth_ids():
		c_event.rpc_id(pid, kind, id, data)

func _flush() -> void:
	var ids := _auth_ids()
	for id in _dirty["inc"]:
		if State.incidents.has(id):
			for pid in ids:
				c_event.rpc_id(pid, "inc", id, State.incidents[id])
	for id in _dirty["call"]:
		if State.calls.has(id):
			var pc := State.public_call(State.calls[id])
			for pid in ids:
				c_event.rpc_id(pid, "call", id, pc)
	for id in _dirty["veh"]:
		if State.vehicles.has(id):
			for pid in ids:
				c_event.rpc_id(pid, "veh", id, State.vehicles[id])
	for id in _dirty["st"]:
		if State.stations.has(id):
			for pid in ids:
				c_event.rpc_id(pid, "st", id, State.stations[id])
	_dirty = {"inc": {}, "call": {}, "veh": {}, "st": {}}

func _send_positions() -> void:
	var ids := PackedStringArray()
	var data := PackedFloat32Array()
	for id in State.vehicles:
		var v: Dictionary = State.vehicles[id]
		if MOVING.has(v["state"]):
			ids.append(id)
			data.append(v["x"]); data.append(v["y"]); data.append(v["heading"]); data.append(float(v["ri"]))
	for pid in _auth_ids():
		c_positions.rpc_id(pid, State.clock, float(State.meta["speed"]), bool(State.meta["paused"]), ids, data)

@rpc("any_peer", "call_remote", "reliable")
func s_action(req: int, a: Dictionary) -> void:
	if mode != MODE_HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or not _started:
		return   # nicht authentifiziert → ignorieren
	var now := Time.get_ticks_msec()
	var r: Array = _rate.get(id, [now, 0])
	if now - int(r[0]) > 1000:
		r = [now, 0]
	r[1] = int(r[1]) + 1
	_rate[id] = r
	if int(r[1]) > 40 or a.size() > 16:
		return
	var res: Dictionary = Sim.act(a, {"id": id, "name": players[id]["name"], "role": players[id]["role"], "area": players[id].get("area", [])})
	c_action_result.rpc_id(id, req, res)

@rpc("any_peer", "call_remote", "reliable")
func s_lobby_chat(text: String) -> void:
	if mode == MODE_HOST and players.has(multiplayer.get_remote_sender_id()):
		send_lobby_chat(text, players[multiplayer.get_remote_sender_id()]["name"])

func send_lobby_chat(text: String, who := "") -> void:
	text = text.strip_edges().substr(0, 300)
	if text == "":
		return
	if mode == MODE_CLIENT:
		s_lobby_chat.rpc_id(1, text)
		return
	if who == "":
		who = Game.me["name"]
	for pid in _auth_ids():
		c_lobby_chat.rpc_id(pid, who, text)
	lobby_chat.emit(who, text)

# ================================================================= CLIENT
## Beitritt über Einladungscode (Vermittlungsdienst).
func join_code(code: String, password: String) -> String:
	shutdown()
	var url := Data.relay_url()
	if url == "":
		return "Es ist kein Vermittlungsdienst eingetragen."
	var rp := RelayPeer.new()
	rp.relay_event.connect(_on_relay_event)
	if rp.start_client(url, code) != OK:
		return rp.error_text
	_peer = rp
	via_relay = true
	multiplayer.multiplayer_peer = _peer
	mode = MODE_CLIENT
	_join = {"code": code.strip_edges().to_upper(), "password": password, "token": _token()}
	_authed = false
	_expect_close = false
	status_text = "Verbinde über Vermittlung (Code %s) …" % _join["code"]
	return ""

func _token() -> String:
	var token: String = LocalDB.fetch("profile", "net_token", "")
	if token == "":
		token = Auth.random_bytes(16).hex_encode()
		LocalDB.put("profile", "net_token", token)
	return token

func join(ip: String, port: int, password: String) -> String:
	shutdown()
	var ep := ENetMultiplayerPeer.new()
	var err := ep.create_client(ip, port)
	if err != OK:
		return "Verbindung zu %s:%d konnte nicht aufgebaut werden." % [ip, port]
	_peer = ep
	via_relay = false
	multiplayer.multiplayer_peer = _peer
	mode = MODE_CLIENT
	_join = {"ip": ip, "port": port, "password": password, "token": _token()}
	_authed = false
	_expect_close = false
	status_text = "Verbinde mit %s:%d …" % [ip, port]
	return ""

func _on_connected() -> void:
	status_text = "Verbunden – Anmeldung …"

func _on_connection_failed() -> void:
	if _reconnect_n > 0:
		_schedule_reconnect()
		return
	var text := "Host nicht erreichbar. Adresse, Port und Portfreigabe (UDP) prüfen."
	if _peer is RelayPeer:
		text = (_peer as RelayPeer).error_text
		if text == "":
			text = "Vermittlungsdienst nicht erreichbar. Bitte Internetverbindung prüfen."
	_drop_peer()
	connect_result.emit(false, text)

@rpc("authority", "call_remote", "reliable")
func c_challenge(version: int, salt: PackedByteArray, nonce: PackedByteArray, needs_pw: bool) -> void:
	if mode != MODE_CLIENT:
		return
	var cn := Auth.random_bytes(24)
	var proof := PackedByteArray()
	if needs_pw:
		proof = Auth.proof(Auth.derive(_join.get("password", ""), salt), nonce, cn)
	s_auth.rpc_id(1, PROTOCOL, Settings.get_v("profile", "name"), cn, proof, _join.get("token", ""))

@rpc("authority", "call_remote", "reliable")
func c_reject(reason: String) -> void:
	_expect_close = true
	_reconnect_n = 0
	_drop_peer()
	if _in_game:
		connection_lost.emit(reason)
	else:
		connect_result.emit(false, reason)

@rpc("authority", "call_remote", "reliable")
func c_accept(my_id_: int, name: String, role: String, sess: Dictionary, started: bool) -> void:
	_authed = true
	session = sess
	Game.me = {"id": my_id_, "name": name, "role": role, "area": []}
	status_text = "Verbunden mit %s" % sess.get("name", "Host")
	if _join.has("ip"):
		LocalDB.put("servers", "%s:%d" % [_join["ip"], int(_join["port"])], {"name": sess.get("name", ""), "ip": _join["ip"], "port": _join["port"], "last": int(Time.get_unix_time_from_system())})
	if _reconnect_n > 0:
		_reconnect_n = 0
		_reconnect_t = -1.0
	connect_result.emit(true, "")

@rpc("authority", "call_remote", "reliable")
func c_lobby(pub: Dictionary, sess: Dictionary) -> void:
	players = pub
	session = sess
	State.players = pub
	var me_id := multiplayer.get_unique_id()
	if pub.has(me_id):
		Game.me["role"] = pub[me_id]["role"]
		Game.me["name"] = pub[me_id]["name"]
		Game.me["area"] = pub[me_id].get("area", [])
	lobby_changed.emit()
	State.players_changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_lobby_chat(who: String, text: String) -> void:
	lobby_chat.emit(who, text)

@rpc("authority", "call_remote", "reliable")
func c_kick(reason: String) -> void:
	_expect_close = true
	_drop_peer()
	if _in_game:
		connection_lost.emit(reason)
	else:
		connect_result.emit(false, reason)

@rpc("authority", "call_remote", "reliable")
func c_state_chunk(idx: int, total: int, raw_size: int, data: PackedByteArray) -> void:
	if mode != MODE_CLIENT or total <= 0 or total > 4000:
		return
	if idx == 0:
		_chunks = []
		_chunk_total = total
		_chunk_size = raw_size
	_chunks.append(data)
	if _chunks.size() < _chunk_total:
		return
	var packed := PackedByteArray()
	for c in _chunks:
		packed.append_array(c)
	_chunks = []
	var raw := packed.decompress(_chunk_size, FileAccess.COMPRESSION_ZSTD)
	var d = bytes_to_var(raw)
	if typeof(d) != TYPE_DICTIONARY:
		return
	World.ensure_built()
	State.from_dict(d)
	State.players = players
	_targets = {}
	var first := not _in_game
	_in_game = true
	if first:
		Game.start_as_client()
		game_started.emit()

@rpc("authority", "call_remote", "reliable")
func c_event(kind: String, id: String, data) -> void:
	if mode != MODE_CLIENT or not State.active:
		return
	match kind:
		"inc":
			State.incidents[id] = data
			State.touch_incident(id)
		"inc_del":
			State.remove_incident(id)
		"call":
			State.calls[id] = data
			State.touch_call(id)
		"call_del":
			State.remove_call(id)
		"veh":
			var old: Dictionary = State.vehicles.get(id, {})
			if not old.is_empty() and MOVING.has(data["state"]) and MOVING.has(old["state"]):
				_targets[id] = Vector2(data["x"], data["y"])
				data["x"] = old["x"]
				data["y"] = old["y"]
			else:
				_targets.erase(id)
			State.vehicles[id] = data
			State.touch_vehicle(id)
		"veh_del":
			State.remove_vehicle(id)
		"st":
			State.stations[id] = data
			State.touch_station(id)
		"st_del":
			State.remove_station(id)
		"radio":
			State.add_radio(data)
		"chat":
			State.add_chat(data)
		"env":
			State.env = data
			State.apply_env()
			State.env_changed.emit()
		"meta":
			State.meta = data
			State.meta_changed.emit()
		"notice":
			State.notice.emit(String(data), id)
		"sound":
			Audio.play(id)

@rpc("authority", "call_remote", "unreliable_ordered")
func c_positions(clock: float, speed: float, paused: bool, ids: PackedStringArray, data: PackedFloat32Array) -> void:
	if mode != MODE_CLIENT or not State.active:
		return
	State.clock = clock
	State.meta["speed"] = speed
	State.meta["paused"] = paused
	for i in ids.size():
		var id := ids[i]
		if State.vehicles.has(id):
			var v: Dictionary = State.vehicles[id]
			_targets[id] = Vector2(data[i * 4], data[i * 4 + 1])
			v["heading"] = data[i * 4 + 2]
			v["ri"] = int(data[i * 4 + 3])

@rpc("authority", "call_remote", "reliable")
func c_action_result(req: int, res: Dictionary) -> void:
	if not res.get("ok", false) and res.get("err", "") != "":
		Game.action_failed.emit(res["err"])
	if _callbacks.has(req):
		var cb: Callable = _callbacks[req]
		_callbacks.erase(req)
		if cb.is_valid():
			cb.call(res)

func send_action(a: Dictionary, cb: Callable) -> void:
	if mode != MODE_CLIENT or not _authed:
		Game.action_failed.emit("Keine Verbindung zum Host.")
		return
	_req += 1
	if cb.is_valid():
		_callbacks[_req] = cb
	s_action.rpc_id(1, _req, a)

func _on_server_disconnected() -> void:
	if mode != MODE_CLIENT:
		return
	var was_game := _in_game
	_drop_peer(false)
	if _expect_close:
		return
	if was_game and Settings.get_v("net", "reconnect"):
		_reconnect_n = 1
		_reconnect_t = 2.0
		mode = MODE_CLIENT
		status_text = "Verbindung verloren – Wiederverbindung …"
		reconnecting.emit(_reconnect_n, 6)
	elif was_game:
		connection_lost.emit("Die Verbindung zum Host wurde getrennt.")
	else:
		connect_result.emit(false, "Die Verbindung wurde vom Host getrennt.")

func _schedule_reconnect() -> void:
	_drop_peer(false)
	mode = MODE_CLIENT
	_reconnect_n += 1
	if _reconnect_n > 6:
		_reconnect_n = 0
		_reconnect_t = -1.0
		mode = MODE_NONE
		connection_lost.emit("Der Host ist nicht mehr erreichbar. Die Sitzung wurde beendet.")
		return
	_reconnect_t = 3.0
	reconnecting.emit(_reconnect_n, 6)

func _try_reconnect() -> void:
	if _join.has("code"):
		var rp := RelayPeer.new()
		rp.relay_event.connect(_on_relay_event)
		if rp.start_client(Data.relay_url(), _join["code"]) != OK:
			_schedule_reconnect()
			return
		_peer = rp
	else:
		var ep := ENetMultiplayerPeer.new()
		if ep.create_client(_join["ip"], int(_join["port"])) != OK:
			_schedule_reconnect()
			return
		_peer = ep
	multiplayer.multiplayer_peer = _peer
	_authed = false

# ================================================================= gemeinsam
func _drop_peer(clear_game := true) -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	_authed = false
	if clear_game:
		mode = MODE_NONE
		_in_game = false
		status_text = "Einzelplatz"

func shutdown() -> void:
	if mode == MODE_HOST and _peer != null:
		for pid in _auth_ids():
			c_kick.rpc_id(pid, "Der Host hat die Sitzung beendet.")
		multiplayer.multiplayer_peer.poll()
	discovery.stop()
	_expect_close = true
	_reconnect_n = 0
	_reconnect_t = -1.0
	_drop_peer()
	players = {}
	session = {}
	relay_code = ""
	via_relay = false
	_pending = {}
	_started = false
	_callbacks = {}
	_targets = {}
	_dirty = {"inc": {}, "call": {}, "veh": {}, "st": {}}
	State.players = {}
	Game.me["id"] = 1
	lobby_changed.emit()

## Öffentliche Sitzungen beim Vermittlungsdienst abfragen (Ergebnis: Signal internet_list).
func query_internet() -> void:
	var url := Data.relay_url()
	if url == "":
		internet_list.emit([], "Kein Vermittlungsdienst eingetragen.")
		return
	_dir_ws = WebSocketPeer.new()
	_dir_t = 0.0
	_dir_sent = false
	if _dir_ws.connect_to_url(url) != OK:
		_dir_ws = null
		internet_list.emit([], "Vermittlungsdienst nicht erreichbar.")

func _poll_directory(delta: float) -> void:
	if _dir_ws == null:
		return
	_dir_ws.poll()
	_dir_t += delta
	var st := _dir_ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _dir_sent:
		_dir_sent = true
		_dir_ws.send_text(JSON.stringify({"op": "list"}))
	while st == WebSocketPeer.STATE_OPEN and _dir_ws.get_available_packet_count() > 0:
		var d = JSON.parse_string(_dir_ws.get_packet().get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY and d.get("op", "") == "list":
			_dir_ws.close()
			_dir_ws = null
			internet_list.emit(d.get("sessions", []), "")
			return
	if st == WebSocketPeer.STATE_CLOSED or _dir_t > 8.0:
		_dir_ws = null
		internet_list.emit([], "Vermittlungsdienst nicht erreichbar. Internet-Spiele sind derzeit nicht möglich – im lokalen Netzwerk geht es weiterhin.")

func start_browser() -> void:
	if mode == MODE_NONE:
		discovery.start_listen(int(Settings.get_v("net", "discovery_port")))

func stop_browser() -> void:
	if mode != MODE_HOST:
		discovery.stop()

func _process(delta: float) -> void:
	_poll_directory(delta)
	if discovery.hosting or discovery.listening:
		if discovery.poll(delta):
			servers_changed.emit()
	if mode == MODE_HOST:
		# nicht authentifizierte Verbindungen nach 8 s trennen
		var now := Time.get_ticks_msec()
		for id in _pending.keys():
			if now - int(_pending[id]["t"]) > 8000:
				_pending.erase(id)
				if _peer != null and multiplayer.get_peers().has(id):
					_peer.disconnect_peer(id)
		if _started and State.active:
			_flush_t += delta
			if _flush_t >= 0.12:
				_flush_t = 0.0
				_flush()
			_pos_t += delta
			if _pos_t >= 0.2:
				_pos_t = 0.0
				_send_positions()
	elif mode == MODE_CLIENT:
		if _reconnect_t >= 0.0:
			_reconnect_t -= delta
			if _reconnect_t < 0.0 and _peer == null:
				_try_reconnect()
		if _in_game and State.active:
			if not State.meta["paused"]:
				State.clock += delta * float(State.meta["speed"])
			var k: float = clampf(delta * 6.0, 0.0, 1.0)
			for id in _targets:
				if State.vehicles.has(id):
					var v: Dictionary = State.vehicles[id]
					var p := Vector2(v["x"], v["y"]).lerp(_targets[id], k)
					v["x"] = p.x
					v["y"] = p.y
			for cid in State.calls:
				var c: Dictionary = State.calls[cid]
				if c["state"] == "ringing":
					c["wait"] = float(c["wait"]) + delta
				elif c["state"] == "active":
					c["talk"] = float(c["talk"]) + delta
			if _peer is ENetMultiplayerPeer and (_peer as ENetMultiplayerPeer).get_peer(1) != null:
				last_ping = int((_peer as ENetMultiplayerPeer).get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			elif _peer is RelayPeer:
				last_ping = (_peer as RelayPeer).rtt_ms

# ---------------------------------------------------------------- UPnP (optional)
func try_upnp() -> void:
	if _upnp_thread != null and _upnp_thread.is_alive():
		return
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
	var port := int(session.get("port", Settings.get_v("net", "port")))
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(port))

func _upnp_work(port: int) -> void:
	var upnp := UPNP.new()
	var text := ""
	var err := upnp.discover(2500, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		text = "Kein UPnP-fähiger Router gefunden. Bitte Port %d (UDP) manuell am Router freigeben." % port
	else:
		var res := upnp.add_port_mapping(port, port, "LEITSTELLE 112", "UDP", 0)
		if res == UPNP.UPNP_RESULT_SUCCESS:
			text = "Portfreigabe eingerichtet. Öffentliche Adresse: %s:%d" % [upnp.query_external_address(), port]
		else:
			text = "UPnP-Portfreigabe abgelehnt (Fehler %d). Bitte Port %d (UDP) manuell freigeben." % [res, port]
	upnp_result.emit.call_deferred(text)

func _exit_tree() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
