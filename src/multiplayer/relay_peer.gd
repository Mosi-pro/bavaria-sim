extends MultiplayerPeerExtension
## Mehrspieler-Verbindung über den Vermittlungsdienst (WebSocket).
## Host und Mitspieler bauen jeweils eine ausgehende Verbindung zum Vermittlungsdienst
## auf – dadurch ist beim Kunden keine Portfreigabe nötig. Der Dienst reicht die
## Pakete nur weiter; die Simulation läuft weiterhin ausschließlich beim Host.
##
## Rahmenformat (binär):  [u8 1][i32 peer][u8 modus][u8 kanal][nutzdaten]
##   Host → Dienst:  peer = Ziel (>0 einzeln, 0 alle, <0 alle außer |peer|)
##   Dienst → Host:  peer = Absender;  Mitspieler ↔ Dienst: peer = 1
## Steuermeldungen sind JSON-Textrahmen (op = host, hosted, join, joined, peer_join, …).

signal relay_event(op, data)

const BUFFER := 8 * 1024 * 1024

var ws := WebSocketPeer.new()
var url := ""
var role := ""                 # "host" oder "client"
var code := ""
var my_id := 0
var status := CONNECTION_DISCONNECTED
var error_text := ""
var rtt_ms := -1
var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false
var _in: Array = []            # [peer, modus, kanal, daten]
var _peers := {}               # peer_id -> ip (nur Host)
var _pending_op := {}
var _ping_t := 0.0
var _ping_sent := 0
var _opened := false

func _init() -> void:
	ws.inbound_buffer_size = BUFFER
	ws.outbound_buffer_size = BUFFER
	ws.max_queued_packets = 16384

func start_host(p_url: String, info: Dictionary) -> int:
	role = "host"
	my_id = 1
	_pending_op = {"op": "host", "info": info, "v": 1}
	return _connect(p_url)

func start_client(p_url: String, p_code: String) -> int:
	role = "client"
	code = p_code.strip_edges().to_upper()
	_pending_op = {"op": "join", "code": code, "v": 1}
	return _connect(p_url)

func _connect(p_url: String) -> int:
	url = p_url
	status = CONNECTION_CONNECTING
	var err := ws.connect_to_url(url)
	if err != OK:
		status = CONNECTION_DISCONNECTED
		error_text = "Vermittlungsdienst nicht erreichbar (%s)." % url
	return err

func update_info(info: Dictionary) -> void:
	_send_json({"op": "update", "info": info})

func peer_ip(id: int) -> String:
	return String(_peers.get(id, "relay"))

func _send_json(d: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))

# ---------------------------------------------------------------- MultiplayerPeer
func _poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _opened:
		_opened = true
		_send_json(_pending_op)
	if st == WebSocketPeer.STATE_CLOSED:
		if status != CONNECTION_DISCONNECTED:
			_drop_all("Verbindung zum Vermittlungsdienst getrennt." if _opened else "Vermittlungsdienst nicht erreichbar.")
		return
	while ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		if ws.was_string_packet():
			_on_control(pkt.get_string_from_utf8())
		elif pkt.size() >= 7 and pkt[0] == 1:
			var peer := pkt.decode_s32(1)
			_in.append([peer, int(pkt[5]), int(pkt[6]), pkt.slice(7)])
	if status == CONNECTION_CONNECTED:
		_ping_t += 0.016
		if _ping_t > 3.0:
			_ping_t = 0.0
			_ping_sent = Time.get_ticks_msec()
			_send_json({"op": "ping"})

func _on_control(text: String) -> void:
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		return
	var op: String = d.get("op", "")
	match op:
		"hosted":
			code = String(d.get("code", ""))
			status = CONNECTION_CONNECTED
		"joined":
			my_id = int(d.get("peer", 0))
			status = CONNECTION_CONNECTED
			peer_connected.emit(1)
		"peer_join":
			var id := int(d.get("peer", 0))
			if id > 1:
				_peers[id] = String(d.get("ip", ""))
				peer_connected.emit(id)
		"peer_leave":
			var id := int(d.get("peer", 0))
			if _peers.has(id):
				_peers.erase(id)
				peer_disconnected.emit(id)
		"pong":
			rtt_ms = Time.get_ticks_msec() - _ping_sent
		"error", "host_gone":
			error_text = String(d.get("text", "Sitzung nicht mehr vorhanden."))
			_drop_all(error_text)
			ws.close()
	relay_event.emit(op, d)

func _drop_all(reason: String) -> void:
	if error_text == "":
		error_text = reason
	var was := status
	status = CONNECTION_DISCONNECTED
	if role == "host":
		for id in _peers.keys():
			peer_disconnected.emit(id)
		_peers = {}
	elif was == CONNECTION_CONNECTED:
		peer_disconnected.emit(1)

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var target := _target if role == "host" else 1
	var head := PackedByteArray([1, 0, 0, 0, 0, _mode, _channel])
	head.encode_s32(1, target)
	head.append_array(buffer)
	return ws.send(head)

func _get_available_packet_count() -> int:
	return _in.size()

func _get_packet_script() -> PackedByteArray:
	if _in.is_empty():
		return PackedByteArray()
	var p: Array = _in[0]
	_cur = p
	_in.pop_front()
	return p[3]

var _cur: Array = [0, 0, 0, PackedByteArray()]

func _get_packet_peer() -> int:
	if not _in.is_empty():
		return int(_in[0][0])
	return int(_cur[0])

func _get_packet_mode() -> TransferMode:
	return int(_in[0][1]) if not _in.is_empty() else int(_cur[1])

func _get_packet_channel() -> int:
	return int(_in[0][2]) if not _in.is_empty() else int(_cur[2])

func _get_max_packet_size() -> int:
	return BUFFER / 2

func _set_transfer_mode(p_mode: TransferMode) -> void:
	_mode = p_mode

func _get_transfer_mode() -> TransferMode:
	return _mode

func _set_transfer_channel(p_channel: int) -> void:
	_channel = p_channel

func _get_transfer_channel() -> int:
	return _channel

func _set_target_peer(p_peer: int) -> void:
	_target = p_peer

func _get_unique_id() -> int:
	return my_id

func _is_server() -> bool:
	return role == "host"

func _is_server_relay_supported() -> bool:
	return false

func _get_connection_status() -> ConnectionStatus:
	return status

func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse = p_enable

func _is_refusing_new_connections() -> bool:
	return _refuse

func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	if role == "host":
		_send_json({"op": "kick", "peer": p_peer})
		if _peers.has(p_peer):
			_peers.erase(p_peer)
			peer_disconnected.emit(p_peer)

func _close() -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.close(1000, "bye")
	status = CONNECTION_DISCONNECTED
	_peers = {}
