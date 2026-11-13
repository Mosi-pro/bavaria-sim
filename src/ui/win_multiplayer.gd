extends RefCounted
## Mehrspieler-Fenster: Spiel erstellen (Host), Serverübersicht (LAN/Direkt-IP), Lobby.

const UI = preload("res://src/ui/kit.gd")
const SaveSystem = preload("res://src/save/save_system.gd")

static var pending_game := {}

# ---------------------------------------------------------------- Spiel erstellen
static func host_dialog(parent: Node, in_session: bool) -> void:
	var name := UI.line_edit("", "Leitstelle %s" % Settings.get_v("profile", "name"))
	name.max_length = 40
	var player := UI.line_edit("", String(Settings.get_v("profile", "name")))
	player.max_length = 24
	var pw := UI.line_edit("leer = ohne Passwort")
	pw.secret = true
	var maxp := SpinBox.new()
	maxp.min_value = 2
	maxp.max_value = 8
	maxp.value = int(Settings.get_v("net", "max_players"))
	var port := SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = int(Settings.get_v("net", "port"))
	var modes: Array = [["frei", "Freies Spiel"], ["realismus", "Realismusmodus"], ["karriere", "Karriere"]]
	for sc in Data.scenarios:
		modes.append(["szenario:" + String(sc["id"]), "Szenario: " + String(sc["name"])])
	for s in SaveSystem.list():
		modes.append(["save:" + String(s["id"]), "Spielstand: " + String(s["name"])])
	var mode := UI.option(modes.map(func(m): return m[1]), 0)
	mode.clip_text = true
	var diffs: Array = Data.modes["difficulties"].keys()
	var diff := UI.option(diffs.map(func(d): return Data.modes["difficulties"][d]["name"]), 1)
	var region := UI.option(["Bavaria (Stadtgebiet und Umland)"], 0)
	var private := CheckBox.new()
	private.text = "Private Sitzung (nicht in der LAN-Serverliste anzeigen)"
	private.focus_mode = Control.FOCUS_NONE
	var rows: Array = [["Servername", name], ["Spielername", player], ["Passwort", pw], ["Maximale Spielerzahl", maxp]]
	if not in_session:
		rows.append(["Spielmodus", mode])
		rows.append(["Schwierigkeit", diff])
	rows.append_array([["Region", region], ["Spielport (UDP)", port], ["", private]])
	var box := UI.vbox([UI.form(rows)])
	var hint := UI.label("Der eigene PC wird Host und führt die Simulation aus. Mitspieler im selben Netzwerk finden die Sitzung in der Serverliste; über das Internet verbinden sie sich direkt mit IP-Adresse und Port (UDP-Portfreigabe am Router erforderlich).", UI.TEXT2)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sp)
	box.add_child(UI.hbox([UI.spacer(), UI.accent(UI.button("Spiel erstellen" if not in_session else "Sitzung öffnen", func():
		if player.text.strip_edges() != "":
			Settings.set_v("profile", "name", player.text.strip_edges())
			Game.me["name"] = player.text.strip_edges()
		Settings.set_v("net", "port", int(port.value))
		Settings.set_v("net", "max_players", int(maxp.value))
		Settings.save()
		var m: String = modes[mode.selected][0]
		var err: String = Net.host({"name": name.text, "password": pw.text, "max_players": int(maxp.value), "port": int(port.value), "private": private.button_pressed,
			"game_mode": Data.modes["modes"].get(State.meta["mode"], {}).get("name", "") if in_session else modes[mode.selected][1], "started": in_session})
		if err != "":
			UI.message(parent, "Spiel erstellen", err)
			return
		pending_game = {"mode": m, "difficulty": diffs[diff.selected], "name": name.text}
		box.get_window().queue_free()
		if in_session:
			Net.start_game()
			Sim.radio("Leitstelle", "Sitzung »%s« für Mitspieler geöffnet." % name.text, -1, "system", "")
		lobby(parent)), UI.BLUE), UI.button("Abbrechen", func(): box.get_window().queue_free())]))
	UI.window(parent, "Spiel erstellen" if not in_session else "Laufendes Spiel für Mitspieler öffnen", Vector2i(560, 400 if not in_session else 350), box, "host_dialog")

static func _start_pending() -> void:
	var m: String = pending_game.get("mode", "frei")
	if m.begins_with("save:"):
		var err: String = Game.load_game(m.substr(5))
		if err != "":
			Game.action_failed.emit(err)
			return
	elif m.begins_with("szenario:"):
		Game.start_new({"mode": "szenario", "scenario": m.substr(9), "difficulty": pending_game.get("difficulty", "mittel"), "name": pending_game.get("name", "Sitzung")})
	else:
		Game.start_new({"mode": m, "difficulty": pending_game.get("difficulty", "mittel"), "name": pending_game.get("name", "Sitzung")})
	Net.start_game()

# ---------------------------------------------------------------- Lobby / Mitspieler
static func lobby(parent: Node) -> void:
	var info := UI.rich(false)
	info.scroll_following = false
	info.custom_minimum_size.y = 96
	info.size_flags_vertical = Control.SIZE_FILL
	var tree := UI.tree([{"title": "Spieler"}, {"title": "Rolle", "width": 240}, {"title": "", "width": 70}])
	var chat := UI.rich(false)
	chat.custom_minimum_size.y = 90
	var chat_in := UI.line_edit("Nachricht an die Mitspieler …")
	var role_ids: Array = Data.roles.keys()
	var role_opt := UI.option(role_ids.map(func(r): return Data.roles[r]["name"]), 0)
	var status := UI.label("", UI.TEXT2)
	var start_btn := UI.accent(UI.button("Spiel starten", func(): _start_pending()), UI.GREEN)
	var box := UI.vbox([])
	var fill := func():
		if not is_instance_valid(tree) or not tree.is_inside_tree():
			return
		var s: Dictionary = Net.session
		var t := "[b]%s[/b]    Host: %s    Modus: %s    Region: %s\n" % [s.get("name", "–"), s.get("host", "–"), s.get("mode", "–"), s.get("region", "Bavaria")]
		t += "[color=#a4adb5]Spieler[/color] %d / %d    [color=#a4adb5]Passwortschutz[/color] %s    [color=#a4adb5]Sichtbarkeit[/color] %s\n" % [Net.players.size(), int(s.get("max", 0)), "ja" if s.get("locked", false) else "nein", "privat" if s.get("private", false) else "LAN-Serverliste"]
		if Net.mode == Net.MODE_HOST:
			var addrs: Array = Net.local_addresses()
			t += "[color=#a4adb5]Verbindungsdaten für Mitspieler[/color]  %s    Port %d (UDP)\n" % [",  ".join(addrs) if addrs.size() > 0 else "keine Netzwerkadresse gefunden", int(s.get("port", 0))]
			t += "[color=#6b737b]Internet: öffentliche IP-Adresse des Routers weitergeben und Port %d (UDP) auf diesen PC weiterleiten.[/color]" % int(s.get("port", 0))
		else:
			t += "[color=#a4adb5]Verbindung[/color]  %s    [color=#a4adb5]Ping[/color] %s" % [Net.status_text, ("%d ms" % Net.last_ping) if Net.last_ping >= 0 else "–"]
		info.text = t
		tree.clear()
		var root := tree.create_item()
		var ids: Array = Net.players.keys()
		ids.sort()
		for id in ids:
			var p: Dictionary = Net.players[id]
			var it := tree.create_item(root)
			it.set_metadata(0, id)
			it.set_text(0, "%s%s%s" % [p["name"], "  (Host)" if int(id) == 1 else "", "  (ich)" if int(id) == Net.my_id() else ""])
			it.set_text(1, Data.roles.get(p["role"], {}).get("name", p["role"]))
			if Net.mode == Net.MODE_HOST and int(id) != 1:
				it.set_text(2, "entfernen")
				it.set_custom_color(2, UI.RED)
		start_btn.visible = Net.mode == Net.MODE_HOST and not Game.in_session
		status.text = "Warten auf den Spielstart durch den Host …" if (Net.mode == Net.MODE_CLIENT and not Game.in_session) else ""
		if Net.mode == Net.MODE_NONE and box.is_inside_tree():
			box.get_window().queue_free()
	tree.item_selected.connect(func():
		var it := tree.get_selected()
		if it != null and Net.players.has(it.get_metadata(0)):
			role_opt.select(max(0, role_ids.find(Net.players[it.get_metadata(0)]["role"]))))
	tree.item_mouse_selected.connect(func(_pos, _btn):
		var it := tree.get_selected()
		if it != null and tree.get_selected_column() == 2 and Net.mode == Net.MODE_HOST:
			Net.kick(int(it.get_metadata(0))))
	var apply_role := UI.button("Rolle zuweisen", func():
		var it := tree.get_selected()
		var target: int = Net.my_id() if it == null else int(it.get_metadata(0))
		if Net.mode != Net.MODE_HOST:
			target = Net.my_id()
		Net.set_role(target, role_ids[role_opt.selected]), "Eigene Rolle wählen; der Host kann allen Spielern Rollen zuweisen.")
	var send := func():
		if chat_in.text.strip_edges() != "":
			Net.send_lobby_chat(chat_in.text)
			chat_in.text = ""
	chat_in.text_submitted.connect(func(_t): send.call())
	var on_chat := func(who, text):
		if is_instance_valid(chat) and chat.is_inside_tree():
			chat.append_text("[color=#8fb7d6]%s:[/color]  %s\n" % [String(who).replace("[", "[lb]"), String(text).replace("[", "[lb]")])
	var on_upnp := func(text):
		if is_instance_valid(status) and status.is_inside_tree():
			status.text = text
	Net.lobby_changed.connect(fill)
	Net.lobby_chat.connect(on_chat)
	Net.upnp_result.connect(on_upnp)
	box.tree_exiting.connect(func():
		Net.lobby_changed.disconnect(fill)
		Net.lobby_chat.disconnect(on_chat)
		Net.upnp_result.disconnect(on_upnp))
	box.add_child(info)
	box.add_child(tree)
	box.add_child(UI.hbox([UI.label("Rolle:", UI.TEXT2), role_opt, apply_role, UI.spacer()]))
	box.add_child(UI.caption("Chat"))
	box.add_child(chat)
	box.add_child(UI.hbox([chat_in, UI.button("Senden", send)]))
	var leave := UI.button("Sitzung verlassen" if not Game.in_session else "Fenster schließen", func():
		if not Game.in_session:
			Net.shutdown()
		if box.is_inside_tree():
			box.get_window().queue_free())
	var upnp := UI.button("Portfreigabe per UPnP versuchen", func():
		status.text = "Suche UPnP-Router …"
		Net.try_upnp())
	upnp.visible = Net.mode == Net.MODE_HOST
	box.add_child(UI.hbox([status, UI.spacer(), upnp, start_btn, leave]))
	var w := UI.window(parent, "Sitzung – Mitspieler und Rollen", Vector2i(680, 560), box, "lobby")
	if w != null and not Game.in_session:
		w.close_requested.connect(func(): Net.shutdown())
	fill.call()

# ---------------------------------------------------------------- Serverübersicht
static func browser(parent: Node) -> void:
	Net.start_browser()
	var tree := UI.tree([{"title": "Servername"}, {"title": "Host", "width": 110}, {"title": "Spieler", "width": 54}, {"title": "Max.", "width": 40}, {"title": "Spielmodus", "width": 150}, {"title": "Region", "width": 70}, {"title": "Ping", "width": 54}, {"title": "Passwort", "width": 64}, {"title": "Status", "width": 90}])
	var ip := UI.line_edit("IP-Adresse oder Hostname", String(Settings.get_v("net", "last_host")))
	var port := SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = int(Settings.get_v("net", "port"))
	var pw := UI.line_edit("Passwort (falls erforderlich)")
	pw.secret = true
	var player := UI.line_edit("", String(Settings.get_v("profile", "name")))
	player.max_length = 24
	player.custom_minimum_size.x = 160
	player.size_flags_horizontal = Control.SIZE_FILL
	var status := UI.label(Net.discovery.listen_error if Net.discovery.listen_error != "" else "Suche nach Sitzungen im lokalen Netzwerk …", UI.TEXT2)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UI.vbox([])
	var fill := func():
		if not is_instance_valid(tree) or not tree.is_inside_tree():
			return
		var sel := ""
		if tree.get_selected() != null:
			sel = tree.get_selected().get_metadata(0)
		tree.clear()
		var root := tree.create_item()
		for key in Net.discovery.servers:
			var s: Dictionary = Net.discovery.servers[key]
			var it := tree.create_item(root)
			it.set_metadata(0, key)
			it.set_text(0, String(s.get("name", "?")))
			it.set_text(1, String(s.get("host", "?")))
			it.set_text(2, str(int(s.get("players", 0))))
			it.set_text(3, str(int(s.get("max", 0))))
			it.set_text(4, String(s.get("mode", "")))
			it.set_text(5, String(s.get("region", "")))
			it.set_text(6, ("%d ms" % int(s["ping"])) if int(s.get("ping", -1)) >= 0 else "–")
			it.set_text(7, "ja" if s.get("locked", false) else "nein")
			var full: bool = int(s.get("players", 0)) >= int(s.get("max", 0))
			it.set_text(8, "voll" if full else ("läuft" if s.get("started", false) else "Lobby"))
			it.set_custom_color(8, UI.RED if full else UI.GREEN)
			if key == sel:
				it.select(0)
	tree.item_selected.connect(func():
		var it := tree.get_selected()
		if it != null and Net.discovery.servers.has(it.get_metadata(0)):
			var s: Dictionary = Net.discovery.servers[it.get_metadata(0)]
			ip.text = s["ip"]
			port.value = int(s["port"]))
	var connect_fn := func():
		if ip.text.strip_edges() == "":
			status.text = "Bitte eine Sitzung auswählen oder eine IP-Adresse eingeben."
			return
		if player.text.strip_edges() != "":
			Settings.set_v("profile", "name", player.text.strip_edges())
		Settings.set_v("net", "last_host", ip.text.strip_edges())
		Settings.save()
		Net.discovery.stop()
		var err: String = Net.join(ip.text.strip_edges(), int(port.value), pw.text)
		status.text = err if err != "" else "Verbinde mit %s:%d …" % [ip.text.strip_edges(), int(port.value)]
	tree.item_activated.connect(connect_fn)
	var on_result := func(ok, text):
		if not is_instance_valid(status) or not status.is_inside_tree():
			return
		if ok:
			box.get_window().queue_free()
			if not Game.in_session:
				lobby(parent)
		else:
			status.text = "Verbindung fehlgeschlagen: %s" % text
			status.add_theme_color_override("font_color", UI.RED)
			Net.start_browser()
	Net.servers_changed.connect(fill)
	Net.connect_result.connect(on_result)
	box.tree_exiting.connect(func():
		Net.servers_changed.disconnect(fill)
		Net.connect_result.disconnect(on_result)
		Net.stop_browser())
	box.add_child(UI.caption("Sitzungen im lokalen Netzwerk"))
	box.add_child(tree)
	var recent: Dictionary = LocalDB.table("servers")
	if not recent.is_empty():
		var names: Array = ["Zuletzt verwendet …"]
		var keys: Array = recent.keys()
		for k in keys:
			names.append("%s  (%s)" % [recent[k].get("name", ""), k])
		var ro := UI.option(names, 0)
		ro.item_selected.connect(func(i):
			if i > 0:
				ip.text = String(recent[keys[i - 1]]["ip"])
				port.value = int(recent[keys[i - 1]]["port"]))
		box.add_child(ro)
	box.add_child(UI.caption("Direkte Verbindung (Internet / IP-Adresse)"))
	box.add_child(UI.hbox([UI.label("Adresse", UI.TEXT2), ip, UI.label("Port", UI.TEXT2), port]))
	box.add_child(UI.hbox([UI.label("Spielername", UI.TEXT2), player, UI.label("Passwort", UI.TEXT2), pw]))
	box.add_child(UI.hbox([status, UI.accent(UI.button("Verbinden", connect_fn), UI.BLUE), UI.button("Schließen", func(): box.get_window().queue_free())]))
	var w := UI.window(parent, "Multiplayer – Serverübersicht", Vector2i(900, 520), box, "browser")
	if w != null:
		w.close_requested.connect(func():
			if Net.mode == Net.MODE_CLIENT and not Game.in_session:
				Net.shutdown())
	fill.call()
