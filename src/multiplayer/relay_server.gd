extends Node
## Vermittlungsdienst (läuft z. B. auf einem kleinen Linux-PC wie einem Dell Wyse).
## Start:  leitstelle112.x86_64 --headless --vermittlung [--port=24180]
##
## Aufgaben:
##  * Serverliste der offenen Sitzungen (nur Name, Spielerzahl usw.)
##  * Weiterleitung der Pakete zwischen Host und Mitspielern
## Der Dienst führt KEINE Simulation aus und kennt keine Passwörter – die Anmeldung
## läuft verschlüsselt per Challenge-Response direkt zwischen Host und Mitspieler.

const MAX_CONN := 300
const MAX_SESSIONS := 60
const MAX_PER_SESSION := 12
const MAX_FRAME := 4 * 1024 * 1024
const MAX_TEXT := 8192
const RATE_BYTES := 6 * 1024 * 1024   # je Verbindung und 10 s
const IDLE_NO_ROLE := 20.0
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var port := 24180
var tcp := TCPServer.new()
var conns := {}            # conn_id -> {ws, ip, role, session, peer, t0, bytes, win}
var sessions := {}         # code -> {host, info, clients: {peer: conn_id}, created}
var _next_conn := 1
var _stat_t := 0.0
var _total_bytes := 0
var rng := RandomNumberGenerator.new()

func start(p_port: int) -> int:
	port = p_port
	rng.randomize()
	var err := tcp.listen(port, "*")
	if err != OK:
		_log("FEHLER: Port %d kann nicht geöffnet werden (%s)." % [port, error_string(err)])
		return err
	_log("Vermittlungsdienst LEITSTELLE 112 gestartet, Port %d (TCP/WebSocket)." % port)
	return OK

func _log(text: String) -> void:
	print("[%s] %s" % [Time.get_datetime_string_from_system(true, true), text])

func _process(delta: float) -> void:
	while tcp.is_connection_available():
		var stream := tcp.take_connection()
		if conns.size() >= MAX_CONN:
			stream.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 8 * 1024 * 1024
		ws.outbound_buffer_size = 8 * 1024 * 1024
		ws.max_queued_packets = 16384
		if ws.accept_stream(stream) != OK:
			continue
		var id := _next_conn
		_next_conn += 1
		conns[id] = {"ws": ws, "ip": stream.get_connected_host(), "role": "", "session": "", "peer": 0, "t0": Time.get_ticks_msec(), "bytes": 0, "win": Time.get_ticks_msec()}
	var now := Time.get_ticks_msec()
	for id in conns.keys():
		if not conns.has(id):
			continue
		var c: Dictionary = conns[id]
		var ws: WebSocketPeer = c["ws"]
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			_drop(id)
			continue
		if c["role"] == "" and now - int(c["t0"]) > IDLE_NO_ROLE * 1000.0:
			ws.close(1008, "timeout")
			_drop(id)
			continue
		while st == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if now - int(c["win"]) > 10000:
				c["win"] = now
				c["bytes"] = 0
			c["bytes"] = int(c["bytes"]) + pkt.size()
			_total_bytes += pkt.size()
			if int(c["bytes"]) > RATE_BYTES:
				_send(id, {"op": "error", "text": "Datenmenge überschritten."})
				ws.close(1008, "rate")
				break
			if ws.was_string_packet():
				if pkt.size() <= MAX_TEXT:
					_on_text(id, pkt.get_string_from_utf8())
			elif pkt.size() <= MAX_FRAME:
				_on_data(id, pkt)
	_stat_t += delta
	if _stat_t > 600.0:
		_stat_t = 0.0
		_log("Status: %d Verbindungen, %d Sitzungen, %.1f MB weitergeleitet." % [conns.size(), sessions.size(), _total_bytes / 1048576.0])

func _send(id: int, d: Dictionary) -> void:
	if conns.has(id):
		var ws: WebSocketPeer = conns[id]["ws"]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(JSON.stringify(d))

func _public(code: String) -> Dictionary:
	var s: Dictionary = sessions[code]
	var info: Dictionary = s["info"]
	var out := {"code": code, "players": 1 + s["clients"].size()}
	for k in ["name", "host", "max", "mode", "region", "locked", "started", "version"]:
		if info.has(k):
			out[k] = info[k]
	return out

func _clean_info(info) -> Dictionary:
	var out := {}
	if typeof(info) != TYPE_DICTIONARY:
		return out
	for k in ["name", "host", "max", "mode", "region", "locked", "started", "private", "version"]:
		if info.has(k):
			var v = info[k]
			if typeof(v) == TYPE_STRING:
				v = String(v).substr(0, 48)
			out[k] = v
	return out

func _on_text(id: int, text: String) -> void:
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		return
	var c: Dictionary = conns[id]
	match String(d.get("op", "")):
		"ping":
			_send(id, {"op": "pong"})
		"list":
			var arr: Array = []
			for code in sessions:
				if not sessions[code]["info"].get("private", false):
					arr.append(_public(code))
			_send(id, {"op": "list", "sessions": arr})
		"host":
			if c["role"] != "":
				return
			if sessions.size() >= MAX_SESSIONS:
				_send(id, {"op": "error", "text": "Der Vermittlungsdienst ist ausgelastet. Bitte später erneut versuchen."})
				return
			var code := ""
			while code == "" or sessions.has(code):
				code = ""
				for i in 6:
					code += CODE_CHARS[rng.randi() % CODE_CHARS.length()]
			sessions[code] = {"host": id, "info": _clean_info(d.get("info", {})), "clients": {}, "created": Time.get_ticks_msec()}
			c["role"] = "host"
			c["session"] = code
			_send(id, {"op": "hosted", "code": code})
			_log("Sitzung %s eröffnet (%s)." % [code, sessions[code]["info"].get("name", "?")])
		"update":
			if c["role"] == "host" and sessions.has(c["session"]):
				sessions[c["session"]]["info"] = _clean_info(d.get("info", {}))
		"join":
			if c["role"] != "":
				return
			var code := String(d.get("code", "")).strip_edges().to_upper()
			if not sessions.has(code):
				_send(id, {"op": "error", "text": "Sitzung %s nicht gefunden. Code prüfen – oder der Host hat die Sitzung beendet." % code})
				return
			var s: Dictionary = sessions[code]
			if s["clients"].size() + 1 >= MAX_PER_SESSION:
				_send(id, {"op": "error", "text": "Die Sitzung ist voll."})
				return
			var peer := 0
			while peer < 2 or s["clients"].has(peer):
				peer = rng.randi_range(2, 2000000000)
			s["clients"][peer] = id
			c["role"] = "client"
			c["session"] = code
			c["peer"] = peer
			_send(id, {"op": "joined", "peer": peer, "code": code})
			_send(int(s["host"]), {"op": "peer_join", "peer": peer, "ip": c["ip"]})
		"kick":
			if c["role"] == "host" and sessions.has(c["session"]):
				var s: Dictionary = sessions[c["session"]]
				var peer := int(d.get("peer", 0))
				if s["clients"].has(peer):
					var cid: int = s["clients"][peer]
					s["clients"].erase(peer)
					if conns.has(cid):
						conns[cid]["role"] = "kicked"
						conns[cid]["ws"].close(1000, "kick")

func _on_data(id: int, pkt: PackedByteArray) -> void:
	if pkt.size() < 7 or pkt[0] != 1:
		return
	var c: Dictionary = conns[id]
	if not sessions.has(c["session"]):
		return
	var s: Dictionary = sessions[c["session"]]
	if c["role"] == "host":
		var target := pkt.decode_s32(1)
		pkt.encode_s32(1, 1)
		if target > 0:
			if s["clients"].has(target):
				_forward(int(s["clients"][target]), pkt)
		else:
			for peer in s["clients"]:
				if target < 0 and peer == -target:
					continue
				_forward(int(s["clients"][peer]), pkt)
	elif c["role"] == "client":
		pkt.encode_s32(1, int(c["peer"]))
		_forward(int(s["host"]), pkt)

func _forward(cid: int, pkt: PackedByteArray) -> void:
	if conns.has(cid):
		var ws: WebSocketPeer = conns[cid]["ws"]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send(pkt)

func _drop(id: int) -> void:
	if not conns.has(id):
		return
	var c: Dictionary = conns[id]
	conns.erase(id)
	var code: String = c["session"]
	if not sessions.has(code):
		return
	var s: Dictionary = sessions[code]
	if c["role"] == "host":
		for peer in s["clients"]:
			var cid: int = s["clients"][peer]
			_send(cid, {"op": "host_gone", "text": "Der Host hat die Sitzung beendet."})
			if conns.has(cid):
				conns[cid]["ws"].close(1000, "host_gone")
		sessions.erase(code)
		_log("Sitzung %s beendet." % code)
	elif c["role"] == "client" and s["clients"].get(c["peer"], -1) == id:
		s["clients"].erase(c["peer"])
		_send(int(s["host"]), {"op": "peer_leave", "peer": c["peer"]})
