extends Node
## Mehrspieler-Integrationstest mit getrennten Prozessen (siehe tools/test_multiplayer.sh).
const Advisor = preload("res://src/dispatch/advisor.gd")
const CallGen = preload("res://src/incidents/call_generator.gd")
var role := "host"
var port := 24555
var step := 0
var t := 0.0
var wait := 0.0
var fails := 0
var inc_id := ""
var call_id := ""
var veh_id := ""
var veh_start := Vector2.ZERO
var result := {}
var relay := ""
var codefile := ""
var code := ""
var inet := {}

func ok(cond: bool, name: String) -> void:
	print("%s [%s] %s" % ["PASS" if cond else "FAIL", role, name])
	if not cond:
		fails += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="): role = a.substr(7)
		if a.begins_with("--port="): port = int(a.substr(7))
		if a.begins_with("--relay="): relay = a.substr(8)
		if a.begins_with("--codefile="): codefile = a.substr(11)
	if relay != "":
		Settings.set_v("net", "relay_url", relay)
		Net.internet_list.connect(func(arr, err): inet = {"list": arr, "err": err})
	Settings.set_v("game", "autosave", false)
	Settings.set_v("net", "discovery_port", port + 7)
	Settings.set_v("profile", "name", "Disponent")
	Net.connect_result.connect(func(success, text): result = {"ok": success, "text": text})
	if role == "host":
		var err: String = Net.host({"name": "Testsitzung", "password": "geheim112", "port": port, "max_players": 4, "relay": relay != ""})
		ok(err == "", "Host erstellt Sitzung" + (" über Vermittlung" if relay != "" else " auf Port %d" % port))
		ok(Net._pw_key.size() == 32 and Net.session.get("locked", false), "Passwort liegt nur als Schlüsselableitung vor")
		Game.start_new({"mode": "frei", "difficulty": "leicht", "seed": 1})
		State.meta["next_call"] = 1e12
		Net.start_game()
	elif role == "client":
		if relay != "":
			Net.query_internet()
		else:
			Net.start_browser()

func _process(delta: float) -> void:
	t += delta
	wait += delta
	if t > 90.0:
		ok(false, "Zeitüberschreitung in Schritt %d" % step)
		_finish()
		return
	match role:
		"host": _host()
		"badclient": _bad()
		"client": _client()

func _next() -> void:
	step += 1
	wait = 0.0

func _finish() -> void:
	print("RESULT [%s] %s" % [role, "OK" if fails == 0 else "FEHLER"])
	Net.shutdown()
	get_tree().quit(1 if fails > 0 else 0)

func _host() -> void:
	if relay != "" and code == "":
		if Net.relay_code != "":
			code = Net.relay_code
			ok(code.length() == 6, "Einladungscode vom Vermittlungsdienst erhalten (%s)" % code)
			var f := FileAccess.open(codefile, FileAccess.WRITE)
			f.store_string(code)
			f.close()
		return
	match step:
		0:
			if Net.players.size() >= 2:
				ok(true, "Client authentifiziert und in Spielerliste")
				ok(Net.players.values()[1]["name"] != Net.players.values()[0]["name"], "Doppelte Spielernamen werden unterschieden")
				call_id = CallGen.spawn_event("brand_muell", {"district": "altstadt", "variant": 0})
				_next()
		1:
			for e in State.chat:
				if e["text"] == "CLIENT-DONE":
					ok(State.incidents.size() >= 1, "Host hat den vom Client angelegten Einsatz")
					var alarmed := 0
					for v in State.vehicles.values():
						if v["incident"] != "":
							alarmed += 1
					ok(alarmed >= 1, "Host hat die vom Client alarmierten Fahrzeuge in Bewegung gesetzt")
					ok(is_equal_approx(float(State.meta["speed"]), 2.0), "Unberechtigte Aktion des Clients wurde nicht ausgeführt")
					_next()
		2:
			if Net.players.size() < 2:
				ok(Net._tokens.values().has("feuerwehr"), "Rolle des Clients für Wiederverbindung gemerkt")
				_next()
		3:
			if Net.players.size() >= 2:
				var p: Dictionary = Net.players.values()[1]
				ok(p["role"] == "feuerwehr", "Client nach Verbindungsabbruch wieder angemeldet (Rolle erhalten)")
				_next()
		4:
			if wait > 6.0:
				_finish()

func _bad() -> void:
	match step:
		0:
			if relay != "":
				code = FileAccess.get_file_as_string(codefile).strip_edges()
				ok(Net.join_code(code, "falsch") == "", "Verbindungsaufbau über Code gestartet")
			else:
				ok(Net.join("127.0.0.1", port, "falsch") == "", "Verbindungsaufbau gestartet")
			_next()
		1:
			if not result.is_empty():
				ok(result["ok"] == false and String(result["text"]).find("Passwort") >= 0, "Falsches Passwort wird abgelehnt (%s)" % result["text"])
				ok(not State.active and Net.mode == Net.MODE_NONE, "Kein Spielzustand ohne Authentifizierung")
				_finish()

func _client() -> void:
	match step:
		0:
			if relay != "":
				if inet.is_empty():
					return
				var found := {}
				for sx in inet["list"]:
					if sx.get("name", "") == "Testsitzung":
						found = sx
				ok(not found.is_empty() and found.get("locked", false), "Internet-Serverliste zeigt die Sitzung (mit Passwortschutz)")
				code = FileAccess.get_file_as_string(codefile).strip_edges()
				ok(found.get("code", "") == code, "Code in der Serverliste stimmt")
				ok(Net.join_code(code, "geheim112") == "", "Beitritt über Code gestartet")
				_next()
				return
			if Net.discovery.servers.size() > 0 or wait > 6.0:
				ok(Net.discovery.servers.size() > 0, "LAN-Servererkennung findet die Sitzung")
				if Net.discovery.servers.size() > 0:
					var s: Dictionary = Net.discovery.servers.values()[0]
					ok(s["name"] == "Testsitzung" and s["locked"] == true and int(s["port"]) == port, "Serverliste: Name, Passwortschutz, Port")
				Net.stop_browser()
				ok(Net.join("127.0.0.1", port, "geheim112") == "", "Verbindungsaufbau gestartet")
				_next()
		1:
			if not result.is_empty() and State.active and Game.in_session:
				ok(result["ok"], "Anmeldung mit richtigem Passwort")
				ok(State.vehicles.size() > 200 and State.stations.size() > 50, "Vollständiger Spielzustand empfangen (%d Fahrzeuge)" % State.vehicles.size())
				ok(State.truths.is_empty(), "Verdeckte Lagen werden nicht an Clients übertragen")
				ok(Game.me["role"] == "disposition", "Standardrolle Disposition")
				_next()
		2:
			if State.calls.size() > 0:
				call_id = State.calls.keys()[0]
				ok(not State.calls[call_id].has("truth"), "Notruf enthält keine verdeckten Daten")
				Game.act({"a": "call_take", "id": call_id})
				_next()
		3:
			if State.calls.has(call_id) and State.calls[call_id]["state"] == "active" and State.calls[call_id]["transcript"].size() >= 2:
				ok(State.calls[call_id]["taken_by"] == Game.me["name"], "Notrufannahme durch Client synchronisiert")
				var c: Dictionary = State.calls[call_id]
				Game.act({"a": "call_create", "id": call_id, "form": {"keyword": "B 1", "x": c["loc"]["x"], "y": c["loc"]["y"], "address": c["loc"]["text"]}}, func(res):
					inc_id = res.get("id", ""))
				_next()
		4:
			if inc_id != "" and State.incidents.has(inc_id):
				ok(true, "Einsatz vom Client angelegt und synchronisiert")
				Game.act({"a": "call_end", "id": call_id})
				var s := Advisor.suggest(State.incidents[inc_id])
				veh_id = s["suggested"][0]
				veh_start = State.veh_pos(State.vehicles[veh_id])
				Game.act({"a": "inc_alarm", "id": inc_id, "vehicles": s["suggested"]})
				_next()
		5:
			var v: Dictionary = State.vehicles[veh_id]
			if int(v["status"]) == 3 and State.veh_pos(v).distance_to(veh_start) > 60.0:
				ok(true, "Fahrzeugstatus 3 und Fahrzeugposition werden laufend synchronisiert")
				ok(State.incidents[inc_id]["status"] == "anfahrt", "Einsatzstatus synchronisiert (Anfahrt)")
				var has_radio := false
				for e in State.radio:
					if e["kind"] == "alarm":
						has_radio = true
				ok(has_radio, "Funkprotokoll synchronisiert")
				Game.act({"a": "set_speed", "speed": 8.0}, func(res):
					ok(not res.get("ok", true), "Host lehnt unberechtigte Aktion ab (Rolle)"))
				Net.set_role(Net.my_id(), "feuerwehr")
				_next()
		6:
			if Game.me["role"] == "feuerwehr" and wait > 1.0:
				ok(true, "Rollenwechsel synchronisiert")
				Game.act({"a": "chat", "text": "CLIENT-DONE"})
				_next()
		7:
			if wait > 1.0:
				# harter Verbindungsabbruch auf Client-Seite, danach Wiederverbindung
				Net._drop_peer(false)
				Net.mode = Net.MODE_CLIENT
				Net._reconnect_n = 1
				Net._reconnect_t = 0.5
				result = {}
				_next()
		8:
			if not result.is_empty() and Net._authed and wait > 3.0:
				ok(result["ok"] and Game.me["role"] == "feuerwehr", "Wiederverbindung mit gemerkter Rolle")
				ok(State.active and State.incidents.has(inc_id), "Spielzustand nach Wiederverbindung vorhanden")
				_finish()
