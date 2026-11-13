extends RefCounted
## LAN-Servererkennung per UDP-Broadcast sowie Ping-Messung.
## Host: sendet periodisch eine Ankündigung an den Discovery-Port und beantwortet
## Ping-Anfragen auf dem Abfrage-Port (Spielport + 1). Client: lauscht auf dem
## Discovery-Port und misst die Laufzeit zu gefundenen Hosts.

const MAGIC := "LS112"

var udp := PacketPeerUDP.new()
var hosting := false
var listening := false
var listen_error := ""
var servers := {}
var _t := 0.0
var _ping_t := 0.0
var _info := {}
var _disc_port := 24113

func start_host(info: Dictionary, query_port: int, disc_port: int) -> void:
	stop()
	_info = info
	_disc_port = disc_port
	udp = PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	if udp.bind(query_port) == OK:
		hosting = true
		_t = 10.0

func update_info(info: Dictionary) -> void:
	_info = info

func start_listen(disc_port: int) -> void:
	stop()
	_disc_port = disc_port
	udp = PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	var err := udp.bind(disc_port)
	listening = err == OK
	listen_error = "" if listening else "Port %d für die LAN-Suche ist belegt (läuft ein weiteres Spiel auf diesem PC?)." % disc_port
	servers = {}

func stop() -> void:
	if udp.is_bound():
		udp.close()
	hosting = false
	listening = false

## Rückgabe true, wenn sich die Serverliste geändert hat.
func poll(delta: float) -> bool:
	var changed := false
	if hosting:
		_t += delta
		if _t >= 1.5 and not _info.get("private", false):
			_t = 0.0
			var pkt := JSON.stringify({"magic": MAGIC, "q": "announce", "info": _info}).to_utf8_buffer()
			for addr in ["255.255.255.255", "127.0.0.1"]:
				udp.set_dest_address(addr, _disc_port)
				udp.put_packet(pkt)
		while udp.get_available_packet_count() > 0:
			var data := udp.get_packet()
			var ip := udp.get_packet_ip()
			var port := udp.get_packet_port()
			var msg = JSON.parse_string(data.get_string_from_utf8())
			if typeof(msg) == TYPE_DICTIONARY and msg.get("magic", "") == MAGIC and msg.get("q", "") == "ping":
				udp.set_dest_address(ip, port)
				udp.put_packet(JSON.stringify({"magic": MAGIC, "q": "pong", "t": msg.get("t", 0), "info": _info}).to_utf8_buffer())
	elif listening:
		var now := Time.get_ticks_msec()
		while udp.get_available_packet_count() > 0:
			var data := udp.get_packet()
			var ip := udp.get_packet_ip()
			if data.size() > 2000:
				continue
			var msg = JSON.parse_string(data.get_string_from_utf8())
			if typeof(msg) != TYPE_DICTIONARY or msg.get("magic", "") != MAGIC or typeof(msg.get("info")) != TYPE_DICTIONARY:
				continue
			var info: Dictionary = msg["info"]
			var key := "%s:%d" % [ip, int(info.get("port", 0))]
			if not servers.has(key):
				servers[key] = {"ping": -1}
				changed = true
			var s: Dictionary = servers[key]
			for k in ["name", "host", "players", "max", "mode", "region", "locked", "started"]:
				if s.get(k) != info.get(k):
					changed = true
				s[k] = info.get(k)
			s["ip"] = ip
			s["port"] = int(info.get("port", 0))
			s["last"] = now
			if msg.get("q", "") == "pong":
				var rtt := now - int(msg.get("t", now))
				if rtt != s["ping"]:
					s["ping"] = rtt
					changed = true
		_ping_t += delta
		if _ping_t >= 2.0:
			_ping_t = 0.0
			for key in servers.keys():
				var s: Dictionary = servers[key]
				if now - int(s["last"]) > 6000:
					servers.erase(key)
					changed = true
					continue
				udp.set_dest_address(s["ip"], int(s["port"]) + 1)
				udp.put_packet(JSON.stringify({"magic": MAGIC, "q": "ping", "t": now}).to_utf8_buffer())
	return changed
