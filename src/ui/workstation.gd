extends Control
## Leitstellenarbeitsplatz: Menüleiste, Werkzeugleiste, Einsatzübersicht, Lagekarte,
## Einsatzmittel, Kommunikationsfenster und alle Programmfenster.

const UI = preload("res://src/ui/kit.gd")
const MapView = preload("res://src/map/map_view.gd")
const PanelIncidents = preload("res://src/ui/panel_incidents.gd")
const PanelTasks = preload("res://src/ui/panel_tasks.gd")
const Tutorial = preload("res://src/simulation/tutorial.gd")
const PanelVehicles = preload("res://src/ui/panel_vehicles.gd")
const PanelComms = preload("res://src/ui/panel_comms.gd")
const WinCall = preload("res://src/ui/win_call.gd")
const WinDispatch = preload("res://src/ui/win_dispatch.gd")
const WinVehicle = preload("res://src/ui/win_vehicle.gd")
const WinStations = preload("res://src/ui/win_stations.gd")
const WinForm = preload("res://src/ui/win_incident_form.gd")
const WinSettings = preload("res://src/ui/win_settings.gd")
const WinMisc = preload("res://src/ui/win_misc.gd")
const WinMP = preload("res://src/ui/win_multiplayer.gd")
const SaveSystem = preload("res://src/save/save_system.gd")
const Modes = preload("res://src/simulation/modes.gd")

var map: Control
var tasks: VBoxContainer
var _tut_panel: PanelContainer
var _tut_title: Label
var _tut_text: Label
var _tut_step := -2
var left: VBoxContainer
var right: VBoxContainer
var comms: VBoxContainer
var _status_labels := {}
var _statusbar: Label
var _statusbar_t := 0.0
var _speed_buttons: Array = []
var _pause_btn: Button
var _menus := {}
var _ctx: PopupMenu
var _ctx_id := ""
var _overlay: PanelContainer
var _overlay_label: Label
var _t := 0.0

func _ready() -> void:
	Game.ui = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := UI.vbox([], 0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_topbar())
	root.add_child(_build_toolbar())
	left = VBoxContainer.new()
	left.set_script(PanelIncidents)
	left.custom_minimum_size.x = 250
	right = VBoxContainer.new()
	right.set_script(PanelVehicles)
	right.custom_minimum_size.x = 250
	map = Control.new()
	map.set_script(MapView)
	map.custom_minimum_size = Vector2(300, 200)
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comms = VBoxContainer.new()
	comms.set_script(PanelComms)
	comms.custom_minimum_size.y = 120
	var center := VSplitContainer.new()
	center.add_child(map)
	center.add_child(comms)
	center.split_offset = -210
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := HSplitContainer.new()
	inner.add_child(center)
	inner.add_child(right)
	inner.split_offset = -150
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outer := HSplitContainer.new()
	tasks = VBoxContainer.new()
	tasks.set_script(PanelTasks)
	tasks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_split := VSplitContainer.new()
	left_split.custom_minimum_size.x = 250
	left_split.add_child(tasks)
	left_split.add_child(left)
	left_split.split_offset = 60
	outer.add_child(left_split)
	outer.add_child(inner)
	outer.split_offset = 360
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.name = "Split"
	root.add_child(outer)
	_statusbar = UI.label("Bereit.", UI.TEXT2, 11)
	_statusbar.clip_text = true
	_statusbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := PanelContainer.new()
	sb.add_theme_stylebox_override("panel", UI.box(UI.SEC, UI.BORDER, 1, 6))
	_statusbar.custom_minimum_size.x = 100
	_status_labels["counts"] = UI.label("", UI.TEXT2, 11)
	_status_labels["career"] = UI.label("", UI.TEXT2, 11)
	sb.add_child(UI.hbox([_statusbar, _status_labels["career"], VSeparator.new(), _status_labels["counts"]], 10))
	root.add_child(sb)
	_ctx = PopupMenu.new()
	_ctx.id_pressed.connect(_on_ctx)
	add_child(_ctx)
	# Verbindungs-Overlay (Wiederverbindung)
	_overlay = PanelContainer.new()
	_overlay.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.11, 0.12, 0.94), UI.YELLOW, 1, 18))
	_overlay_label = UI.label("", UI.TEXT, 14)
	_overlay.add_child(_overlay_label)
	_overlay.visible = false
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# Signale
	left.call_activated.connect(func(id): take_call(id))
	left.incident_activated.connect(open_dispatch)
	left.incident_selected.connect(func(id):
		map.select("incident", id)
		if State.incidents.has(id):
			map.focus_on(Vector2(State.incidents[id]["x"], State.incidents[id]["y"]), map.zoom))
	right.vehicle_activated.connect(func(id):
		show_vehicle(id)
		open_vehicle(id))
	right.vehicle_selected.connect(func(id): map.select("vehicle", id))
	right.vehicle_context.connect(func(id, pos): _vehicle_menu(id, pos))
	map.object_clicked.connect(_on_map_object)
	map.object_context.connect(func(kind, id, pos):
		if kind == "vehicle":
			_vehicle_menu(id, pos)
		else:
			_on_map_object(kind, id))
	State.notice.connect(_on_notice)
	Game.action_failed.connect(func(text):
		set_status(text, UI.RED)
		Audio.play("error"))
	Net.reconnecting.connect(func(n, m):
		_overlay_label.text = "Verbindung zum Host verloren.\nWiederverbindung wird versucht (%d/%d) …" % [n, m]
		_overlay.visible = true)
	Net.connect_result.connect(func(ok, _text):
		if ok:
			_overlay.visible = false
			set_status("Verbindung zum Host wiederhergestellt.", UI.GREEN))
	State.meta_changed.connect(_update_speed_buttons)
	_update_speed_buttons()
	_build_tutorial_panel()
	call_deferred("_intro")

func _build_tutorial_panel() -> void:
	_tut_panel = PanelContainer.new()
	_tut_panel.add_theme_stylebox_override("panel", UI.box(Color(0.13, 0.14, 0.15, 0.96), UI.YELLOW, 2, 12))
	_tut_title = UI.label("", UI.YELLOW, 14)
	_tut_title.add_theme_font_override("font", UI.bold())
	_tut_text = UI.label("", UI.TEXT, 13)
	_tut_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_text.custom_minimum_size.x = 380
	var close := UI.button("Einweisung ausblenden", func(): _tut_panel.visible = false)
	_tut_panel.add_child(UI.vbox([UI.label("EINWEISUNG", UI.TEXT2, 10), _tut_title, _tut_text, UI.hbox([UI.spacer(), close])], 6))
	_tut_panel.visible = false
	map.add_child(_tut_panel)
	_tut_panel.position = Vector2(12, 12)

func _update_tutorial() -> void:
	if not Tutorial.active():
		_tut_panel.visible = false
		return
	var step := int(State.meta["tutorial"]["step"])
	if step == _tut_step:
		return
	_tut_step = step
	var d: Array = Tutorial.STEPS[clampi(step, 0, Tutorial.STEPS.size() - 1)]
	_tut_title.text = "%s   (%d/%d)" % [d[0], min(step, Tutorial.LAST), Tutorial.LAST] if step > 0 else d[0]
	_tut_text.text = d[1]
	_tut_panel.visible = true
	_tut_panel.reset_size()
	Audio.play("system")
	if step == 7 or step == 6:
		var inc_id: String = State.meta["tutorial"].get("inc", "")
		if State.incidents.has(inc_id):
			show_incident(inc_id)

func _first_visit() -> void:
	if LocalDB.fetch("profile", "seen_intro", false) or Tutorial.active():
		return
	LocalDB.put("profile", "seen_intro", true)
	UI.message(self, "Dein Arbeitsplatz", "So ist der Leitstellenarbeitsplatz aufgebaut:\n\n• Links oben – Was ist zu tun?  Alle offenen Aufgaben mit einem Knopf für den nächsten Schritt. Hier startest du am besten.\n• Links unten – Laufende Einsätze.\n• Mitte – Karte von Bavaria (ziehen, Mausrad zum Zoomen, Klick auf Fahrzeuge und Einsätze).\n• Rechts – Alle Fahrzeuge mit ihrem Status (Farblegende oben).\n• Unten – Funkprotokoll mit allen Meldungen.\n\nNeu hier? Starte im Hauptmenü die »Einweisung«. Hilfe gibt es jederzeit über den Knopf »Hilfe«.")

func _intro() -> void:
	_first_visit()
	var ils := Vector2(-850, -1750)
	map.zoom_fit()
	if State.meta["mode"] == "szenario":
		var sc := Modes.scenario()
		if not sc.is_empty() and State.clock < 5.0:
			UI.message(self, "Szenario: %s" % sc["name"], "%s\n\nAuftrag: %s" % [sc["desc"], sc["goal"]])
	elif State.meta["mode"] == "karriere" and State.clock < 5.0:
		map.focus_on(Vector2.ZERO, 0.09)
		UI.message(self, "Karriere", "Sie übernehmen die Leitstelle zunächst für die Innenstadt von Bavaria. Für abgeschlossene Einsätze erhalten Sie Budget und Erfahrung. Unter Fahrzeuge → Wachen- und Standortverwaltung beschaffen Sie Fahrzeuge, richten Standorte ein und übernehmen weitere Regionen.")
	set_status("Integrierte Leitstelle Bavaria – Arbeitsplatz bereit. Standort der Leitstelle: %s." % World.address_at(ils)["text"])

# ---------------------------------------------------------------- Aufbau
func _build_topbar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.box(UI.MAIN, UI.BORDER, 1, 2))
	var mb := MenuBar.new()
	mb.flat = true
	var defs := [
		["Datei", [["save", "Speichern", "F5"], ["save_as", "Speichern unter …"], ["load", "Spiel laden …"], null, ["settings", "Einstellungen …"], null, ["menu", "Sitzung beenden (Hauptmenü)"], ["quit", "Programm beenden"]]],
		["Bearbeiten", [["inc_edit", "Markierten Einsatz bearbeiten …"], ["inc_note", "Einsatznotiz zum markierten Einsatz …"], null, ["deselect", "Auswahl aufheben"]]],
		["Ansicht", [["v_left", "Einsatzübersicht", "", true], ["v_right", "Einsatzmittel", "", true], ["v_bottom", "Kommunikationsfenster", "", true], null,
			["l_labels", "Karte: Namen", "", true], ["l_buildings", "Karte: Gebäude", "", true], ["l_districts", "Karte: Stadtteilgrenzen", "", true], ["l_traffic", "Karte: Verkehrslage und Sperrungen", "", true], ["l_pois", "Karte: Besondere Objekte", "", true], ["l_stations", "Karte: Wachen und Kliniken", "", true], ["l_routes", "Karte: Routen", "", true], ["l_idle_vehicles", "Karte: Fahrzeuge auf Wache", "", true], null,
			["map_home", "Gesamtansicht Bavaria", "Pos1"], ["map_ils", "Zur Leitstelle springen"], ["fullscreen", "Vollbild umschalten", "F11"]]],
		["Leitstelle", [["pause", "Pause / Fortsetzen", "Pause"], ["speed1", "Spielgeschwindigkeit 1× (Echtzeit)"], ["speed2", "Spielgeschwindigkeit 2×"], ["speed4", "Spielgeschwindigkeit 4×"], ["speed8", "Spielgeschwindigkeit 8×"], null, ["situation", "Wetter- und Lageinformation …"], ["closure", "Straßensperrung setzen / aufheben"], ["stats", "Statistik / Schichtübersicht …"]]],
		["Einsatzverwaltung", [["call_take", "Nächsten Notruf annehmen", "F2"], ["inc_new", "Neuer Einsatz (ohne Notruf) …"], ["dispatch", "Markierten Einsatz disponieren …", "F3"], ["inc_close", "Markierten Einsatz abschließen"], null, ["archive", "Einsatzarchiv …"]]],
		["Fahrzeuge", [["veh_info", "Fahrzeuginformation …"], ["veh_show", "Fahrzeug auf Karte zeigen"], ["veh_oos", "Status 6 / Status 2 setzen"], ["veh_recall", "Fahrzeug aus Einsatz abziehen"], null, ["stations", "Wachen- und Standortverwaltung …"]]],
		["Personal", [["personnel", "Personalübersicht …"]]],
		["Kommunikation", [["talk", "Sprechwunsch annehmen", "F6"], ["radio_focus", "Textnachricht eingeben", "F4"], ["veh_msg", "Nachricht an markiertes Fahrzeug …"], null, ["tab_funk", "Funkprotokoll"], ["tab_talk", "Sprechwünsche"], ["tab_system", "Systemmeldungen"], ["tab_notes", "Einsatznotizen"], ["tab_chat", "Chat"]]],
		["Multiplayer", [["mp_open", "Laufendes Spiel für Mitspieler öffnen …"], ["mp_lobby", "Sitzung: Mitspieler und Rollen …"], ["mp_leave", "Sitzung verlassen"]]],
		["Einstellungen", [["settings", "Einstellungen …"]]],
		["Hilfe", [["h_anleitung", "Kurzanleitung …"], ["h_stichworte", "Einsatzstichwörter und Alarmierungsvorschlag …"], ["h_fms", "FMS-Status und Funkrufnamen …"], null, ["h_about", "Über LEITSTELLE 112 …"]]],
	]
	for d in defs:
		var pm := PopupMenu.new()
		pm.name = d[0]
		var ids: Array = []
		for item in d[1]:
			if item == null:
				pm.add_separator()
				ids.append("")
				continue
			var label: String = item[1]
			if item.size() > 3 and item[3]:
				pm.add_check_item(label)
			else:
				pm.add_item(label)
			var idx := pm.item_count - 1
			if item.size() > 2 and item[2] != "":
				pm.set_item_text(idx, "%s\t%s" % [label, item[2]])
				pm.set_item_text(idx, label + "      " + item[2])
			ids.append(item[0])
		pm.index_pressed.connect(func(i): _menu_action(ids[i]))
		pm.about_to_popup.connect(func(): _refresh_menu(pm, ids))
		mb.add_child(pm)
		_menus[d[0]] = [pm, ids]
	for key in ["status", "conn", "player", "weather", "date", "time"]:
		var l := UI.label("", UI.TEXT2 if key != "time" else UI.TEXT, 12)
		if key == "time":
			l.add_theme_font_override("font", UI.mono())
			l.add_theme_font_size_override("font_size", 14)
		_status_labels[key] = l
	# Reihenfolge von rechts: Uhrzeit, Datum, Leitstellenstatus, Verbindung, Spielername
	var right_box := UI.hbox([_status_labels["player"], VSeparator.new(), _status_labels["conn"], VSeparator.new(), _status_labels["status"], VSeparator.new(), _status_labels["date"], _status_labels["time"]], 8)
	right_box.alignment = BoxContainer.ALIGNMENT_END
	var clip := Control.new()
	clip.clip_contents = true
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.custom_minimum_size = Vector2(120, 22)
	clip.add_child(right_box)
	right_box.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.add_child(UI.hbox([mb, clip, Control.new()], 6))
	return bar

func _build_toolbar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.box(UI.SEC, UI.BORDER, 1, 4))
	var h := UI.hbox([], 3)
	h.add_child(UI.accent(UI.button("Notruf annehmen  (F2)", func(): _menu_action("call_take"), "Nächsten wartenden Notruf annehmen"), UI.RED))
	h.add_child(UI.button("Sprechwunsch  (F6)", func(): _menu_action("talk"), "Sprechaufforderung an das nächste Fahrzeug mit Status 5"))
	h.add_child(UI.button("Neuer Einsatz", func(): _menu_action("inc_new"), "Einsatz ohne Notruf anlegen (z. B. nach Meldung über Funk)"))
	h.add_child(VSeparator.new())
	h.add_child(UI.button("Wachen und Fahrzeuge", func(): _menu_action("stations"), "Wachen verwalten, Fahrzeuge beschaffen und verlegen"))
	h.add_child(UI.button("Gesamtansicht", func(): map.zoom_fit(), "Gesamtes Stadtgebiet anzeigen (Pos1)"))
	h.add_child(VSeparator.new())
	h.add_child(UI.button("Hilfe", func(): WinMisc.help(self, "anleitung"), "Kurzanleitung"))
	h.add_child(UI.spacer())
	_pause_btn = UI.button("Pause", func(): _menu_action("pause"), "Simulation anhalten/fortsetzen (nur Schichtführung)")
	_pause_btn.toggle_mode = true
	h.add_child(UI.label("Zeitraffer:", UI.TEXT2))
	h.add_child(_pause_btn)
	for s in [1, 2, 4, 8]:
		var b := UI.button("%d×" % s, func(): Game.act({"a": "set_speed", "speed": float(s)}))
		b.toggle_mode = true
		b.custom_minimum_size.x = 34
		_speed_buttons.append([b, float(s)])
		h.add_child(b)
	bar.add_child(h)
	return bar

func _update_speed_buttons() -> void:
	if not State.active:
		return
	for sb in _speed_buttons:
		sb[0].set_pressed_no_signal(is_equal_approx(float(State.meta["speed"]), sb[1]))
	_pause_btn.set_pressed_no_signal(bool(State.meta["paused"]))
	_pause_btn.text = "Fortsetzen" if State.meta["paused"] else "Pause"

func _refresh_menu(pm: PopupMenu, ids: Array) -> void:
	var manage: bool = Game.my_role().get("manage", false)
	for i in ids.size():
		var id: String = ids[i]
		match id:
			"v_left": pm.set_item_checked(i, left.visible)
			"v_right": pm.set_item_checked(i, right.visible)
			"v_bottom": pm.set_item_checked(i, comms.visible)
			"save", "save_as", "load": pm.set_item_disabled(i, Game.is_client())
			"mp_open": pm.set_item_disabled(i, Net.is_online())
			"mp_lobby", "mp_leave": pm.set_item_disabled(i, not Net.is_online())
			"pause", "speed1", "speed2", "speed4", "speed8", "closure": pm.set_item_disabled(i, not manage)
		if id.begins_with("l_"):
			pm.set_item_checked(i, map.layers.get(id.substr(2), true))

# ---------------------------------------------------------------- Menüaktionen
func _selected_incident() -> String:
	if left.selected_incident != "" and State.incidents.has(left.selected_incident):
		return left.selected_incident
	if map.sel["kind"] == "incident" and State.incidents.has(map.sel["id"]):
		return map.sel["id"]
	return ""

func _selected_vehicle() -> String:
	if map.sel["kind"] == "vehicle" and State.vehicles.has(map.sel["id"]):
		return map.sel["id"]
	if right.selected != "" and State.vehicles.has(right.selected):
		return right.selected
	return ""

func _need_incident() -> String:
	var id := _selected_incident()
	if id == "":
		set_status("Bitte zuerst einen Einsatz in der Einsatzübersicht markieren.", UI.YELLOW)
	return id

func _need_vehicle() -> String:
	var id := _selected_vehicle()
	if id == "":
		set_status("Bitte zuerst ein Fahrzeug in der Liste oder auf der Karte markieren.", UI.YELLOW)
	return id

func _menu_action(id: String) -> void:
	match id:
		"save": quick_save()
		"save_as": save_dialog()
		"load": load_dialog(self)
		"settings": open_settings(self)
		"menu":
			UI.confirm(self, "Sitzung beenden", "Sitzung beenden und zum Hauptmenü zurückkehren?\nNicht gespeicherter Fortschritt geht verloren." + ("\n\nAls Host beenden Sie damit die Sitzung für alle Mitspieler." if Game.is_host() else ""), func(): Game.leave(""))
		"quit":
			UI.confirm(self, "Programm beenden", "LEITSTELLE 112 wirklich beenden?", func(): get_tree().quit())
		"inc_edit":
			var iid := _need_incident()
			if iid != "":
				var f := VBoxContainer.new()
				f.set_script(WinForm)
				f.setup(iid)
				UI.window(self, "Einsatzdaten bearbeiten", Vector2i(560, 300), f, "form_" + iid)
		"inc_note":
			var iid := _need_incident()
			if iid != "":
				_text_prompt("Einsatznotiz", "Notiz zu Einsatz %s" % State.incidents[iid]["nr"], func(t): Game.act({"a": "inc_note", "id": iid, "text": t}))
		"deselect":
			map.select("", "")
			left.selected_incident = ""
			right.selected = ""
		"v_left": left.visible = not left.visible
		"v_right": right.visible = not right.visible
		"v_bottom": comms.visible = not comms.visible
		"map_home": map.zoom_fit()
		"map_ils": map.focus_on(Vector2(-850, -1750), 0.8)
		"fullscreen":
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode != Window.MODE_WINDOWED and w.mode != Window.MODE_MAXIMIZED else Window.MODE_FULLSCREEN
		"pause": Game.act({"a": "pause", "paused": not State.meta["paused"]})
		"speed1", "speed2", "speed4", "speed8": Game.act({"a": "set_speed", "speed": float(id.substr(5))})
		"situation": WinMisc.situation(self)
		"closure":
			if not Game.my_role().get("manage", false):
				set_status("Straßensperrungen darf nur die Schichtführung eintragen.", UI.YELLOW)
			else:
				map.set_tool("closure", "Straßenabschnitt anklicken, um eine Sperrung zu setzen oder aufzuheben", func(p):
					var ne: Dictionary = World.nearest_edge(p, 60.0)
					if not ne.is_empty():
						Game.act({"a": "closure", "edge": int(ne["edge"])}))
		"stats": WinMisc.stats(self)
		"call_take": take_call(left.next_call())
		"inc_new":
			var f := VBoxContainer.new()
			f.set_script(WinForm)
			f.setup("")
			UI.window(self, "Neuer Einsatz", Vector2i(560, 300), f, "form_new")
		"dispatch":
			var iid := _need_incident()
			if iid != "":
				open_dispatch(iid)
		"inc_close":
			var iid := _need_incident()
			if iid != "":
				Game.act({"a": "inc_close", "id": iid})
		"archive": WinMisc.archive(self)
		"veh_info":
			var vid := _need_vehicle()
			if vid != "":
				open_vehicle(vid)
		"veh_show":
			var vid := _need_vehicle()
			if vid != "":
				show_vehicle(vid)
		"veh_oos":
			var vid := _need_vehicle()
			if vid != "":
				Game.act({"a": "veh_status", "id": vid, "status": 2 if State.vehicles[vid]["state"] == "oos" else 6})
		"veh_recall":
			var vid := _need_vehicle()
			if vid != "":
				Game.act({"a": "veh_recall", "id": vid})
		"veh_msg":
			var vid := _need_vehicle()
			if vid != "":
				_text_prompt("Textnachricht", "Nachricht an %s" % State.vehicles[vid]["callsign"], func(t): Game.act({"a": "veh_msg", "id": vid, "text": t}))
		"stations": open_stations("")
		"personnel": WinMisc.personnel(self)
		"talk": comms.ack_next()
		"radio_focus": comms.focus_input()
		"tab_funk": comms.tabs.current_tab = 0
		"tab_talk": comms.tabs.current_tab = 1
		"tab_system": comms.tabs.current_tab = 2
		"tab_notes": comms.tabs.current_tab = 3
		"tab_chat": comms.tabs.current_tab = 4
		"mp_open": WinMP.host_dialog(self, true)
		"mp_lobby": WinMP.lobby(self)
		"mp_leave":
			UI.confirm(self, "Sitzung verlassen", "Mehrspielersitzung verlassen?" + (" Als Host beenden Sie die Sitzung für alle; das Spiel läuft als Einzelplatz weiter." if Game.is_host() else ""), func():
				if Game.is_host():
					Net.shutdown()
					set_status("Mehrspielersitzung beendet. Das Spiel läuft als Einzelplatz weiter.")
				else:
					Game.leave(""))
		"h_anleitung", "h_stichworte", "h_fms", "h_about": WinMisc.help(self, id.substr(2))
		_:
			if id.begins_with("l_"):
				var k := id.substr(2)
				map.set_layer(k, not map.layers.get(k, true))
				Settings.save()

func _text_prompt(title: String, label: String, cb: Callable) -> void:
	var e := UI.line_edit(label)
	var box := UI.vbox([UI.label(label, UI.TEXT2), e])
	var ok := func():
		if e.text.strip_edges() != "":
			cb.call(e.text.strip_edges())
		box.get_window().queue_free()
	e.text_submitted.connect(func(_t): ok.call())
	box.add_child(UI.hbox([UI.spacer(), UI.button("OK", ok), UI.button("Abbrechen", func(): box.get_window().queue_free())]))
	UI.window(self, title, Vector2i(460, 130), box, "prompt")
	e.grab_focus.call_deferred()

# ---------------------------------------------------------------- Fenster
func take_call(id: String) -> void:
	if id == "" or not State.calls.has(id):
		set_status("Kein wartender Notruf.")
		return
	var c: Dictionary = State.calls[id]
	if c["state"] == "ringing":
		Game.act({"a": "call_take", "id": id}, func(res):
			if res.get("ok", false):
				_open_call(id))
	elif c["taken_by"] == Game.me["name"]:
		_open_call(id)
	else:
		set_status("Der Notruf wird bereits von %s bearbeitet." % c["taken_by"], UI.YELLOW)

func _open_call(id: String) -> void:
	if not State.calls.has(id):
		return
	var w := VBoxContainer.new()
	w.set_script(WinCall)
	w.setup(id)
	var win := UI.window(self, "Notrufabfrage – Leitung %s" % State.calls[id]["line"], Vector2i(900, 640), w, "call_" + id)
	if win != null:
		win.close_requested.disconnect(win.queue_free)
		win.close_requested.connect(func(): set_status("Das Gespräch läuft noch. Bitte Einsatz anlegen oder das Gespräch beenden.", UI.YELLOW))

func open_dispatch(id: String) -> void:
	if not State.incidents.has(id):
		return
	left.select_incident(id)
	map.select("incident", id)
	var w := VBoxContainer.new()
	w.set_script(WinDispatch)
	w.setup(id)
	UI.window(self, "Einsatzakte %s" % State.incidents[id]["nr"], Vector2i(900, 640), w, "inc_" + id)

func open_vehicle(id: String) -> void:
	if not State.vehicles.has(id):
		return
	var w := VBoxContainer.new()
	w.set_script(WinVehicle)
	w.setup(id)
	UI.window(self, "Fahrzeug – %s" % State.vehicles[id]["callsign"], Vector2i(620, 400), w, "veh_" + id)

func open_stations(id: String) -> void:
	var w := HBoxContainer.new()
	w.set_script(WinStations)
	w.setup(id)
	UI.window(self, "Wachen- und Standortverwaltung", Vector2i(1000, 640), w, "stations")

func show_vehicle(id: String) -> void:
	if State.vehicles.has(id):
		map.select("vehicle", id)
		right.selected = id
		map.focus_on(State.veh_pos(State.vehicles[id]), 0.45)

func show_incident(id: String) -> void:
	if State.incidents.has(id):
		map.select("incident", id)
		map.focus_on(Vector2(State.incidents[id]["x"], State.incidents[id]["y"]), 0.45)

static func open_settings(parent: Node) -> void:
	var w := VBoxContainer.new()
	w.set_script(WinSettings)
	w.setup()
	UI.window(parent, "Einstellungen", Vector2i(680, 440), w, "settings")

func quick_save() -> void:
	if Game.is_client():
		set_status("Im Mehrspielermodus verwaltet der Host den Spielstand.", UI.YELLOW)
		return
	var name: String = State.meta["name"] if String(State.meta["name"]) != "" else "Schicht"
	var err: String = Game.save(name.trim_prefix("Autosave – "))
	set_status("Spielstand »%s« gespeichert." % name if err == "" else err, UI.GREEN if err == "" else UI.RED)

func save_dialog() -> void:
	var e := UI.line_edit("Name des Spielstands", String(State.meta["name"]).trim_prefix("Autosave – "))
	var tree := UI.tree([{"title": "Vorhandene Spielstände"}, {"title": "Gespeichert", "width": 140}])
	var root := tree.create_item()
	for s in SaveSystem.list():
		var it := tree.create_item(root)
		it.set_text(0, s["name"])
		it.set_text(1, Time.get_datetime_string_from_unix_time(int(s["saved_unix"]), true))
	tree.item_selected.connect(func(): e.text = tree.get_selected().get_text(0))
	var box := UI.vbox([UI.hbox([UI.label("Name", UI.TEXT2), e]), tree])
	box.add_child(UI.hbox([UI.spacer(), UI.accent(UI.button("Speichern", func():
		if e.text.strip_edges() == "":
			return
		var err: String = Game.save(e.text.strip_edges())
		set_status("Spielstand »%s« gespeichert." % e.text if err == "" else err, UI.GREEN if err == "" else UI.RED)
		box.get_window().queue_free()), UI.BLUE), UI.button("Abbrechen", func(): box.get_window().queue_free())]))
	UI.window(self, "Spiel speichern", Vector2i(520, 380), box, "save")

static func load_dialog(parent: Node) -> void:
	var tree := UI.tree([{"title": "Spielstand"}, {"title": "Modus", "width": 110}, {"title": "Spielzeit", "width": 150}, {"title": "Einsätze", "width": 60}, {"title": "Gespeichert", "width": 140}])
	var box := UI.vbox([tree])
	var fill := func():
		tree.clear()
		var root := tree.create_item()
		for s in SaveSystem.list():
			var it := tree.create_item(root)
			it.set_metadata(0, s["id"])
			it.set_text(0, s["name"])
			it.set_text(1, Data.modes["modes"].get(s.get("mode", ""), {}).get("name", s.get("mode", "")))
			it.set_text(2, s.get("game_time", ""))
			it.set_text(3, str(int(s.get("incidents_done", 0))))
			it.set_text(4, Time.get_datetime_string_from_unix_time(int(s["saved_unix"]), true))
	fill.call()
	var do_load := func():
		var it := tree.get_selected()
		if it == null:
			return
		var id: String = it.get_metadata(0)
		var was_host: bool = Game.is_host()
		if Game.in_session and not was_host:
			Game.leave("__reload__")
		var err: String = Game.load_game(id)
		if err != "":
			UI.message(parent, "Spiel laden", err)
		elif was_host:
			Net.start_game()
		if is_instance_valid(box) and box.is_inside_tree():
			box.get_window().queue_free()
	tree.item_activated.connect(do_load)
	box.add_child(UI.hbox([UI.button("Spielstand löschen", func():
		var it := tree.get_selected()
		if it != null:
			var id: String = it.get_metadata(0)
			UI.confirm(parent, "Spielstand löschen", "Spielstand »%s« endgültig löschen?" % it.get_text(0), func():
				SaveSystem.delete(id)
				fill.call())), UI.spacer(), UI.accent(UI.button("Laden", do_load), UI.BLUE), UI.button("Abbrechen", func(): box.get_window().queue_free())]))
	UI.window(parent, "Spiel laden", Vector2i(760, 420), box, "load")

# ---------------------------------------------------------------- Karte / Kontext
func _on_map_object(kind: String, id: String) -> void:
	match kind:
		"vehicle":
			right.selected = id
			open_vehicle(id)
		"incident":
			open_dispatch(id)
		"station":
			open_stations(id)
		"call":
			take_call(id)
		"hospital":
			for h in Sim.hospitals:
				if h["id"] == id:
					var n := 0
					for vid in State.vehicles:
						if State.vehicles[vid]["hospital"] == id:
							n += 1
					UI.message(self, h["name"], "%s\n\nVersorgungsstufe %d  ·  %d Betten\nAdresse: %s\nRettungsmittel aktuell im Zulauf / vor Ort: %d" % [h["name"], int(h["level"]), int(h["beds"]), World.address_at(h["p"])["text"], n])
		"poi":
			for p in World.pois:
				if p["id"] == id:
					set_status("%s  ·  %s" % [p["name"], World.address_at(p["p"])["text"]])

func _vehicle_menu(id: String, pos: Vector2) -> void:
	if not State.vehicles.has(id):
		return
	var v: Dictionary = State.vehicles[id]
	_ctx_id = id
	_ctx.clear()
	_ctx.add_item("%s  (%s)" % [v["callsign"], Data.vehicle_types[v["type"]]["short"]], 99)
	_ctx.set_item_disabled(0, true)
	_ctx.add_separator()
	_ctx.add_item("Fahrzeuginformation …", 0)
	_ctx.add_item("Auf Karte zeigen", 1)
	if v["talk"] != "":
		_ctx.add_item("Sprechaufforderung geben", 2)
	if v["incident"] != "":
		_ctx.add_item("Einsatz öffnen …", 3)
		_ctx.add_item("Aus Einsatz abziehen", 4)
	if v["state"] == "station":
		_ctx.add_item("Außer Dienst nehmen (Status 6)", 5)
	elif v["state"] == "oos":
		_ctx.add_item("Wieder in Dienst nehmen (Status 2)", 5)
	_ctx.add_item("Heimatwache anzeigen …", 6)
	_ctx.position = Vector2i(pos)
	_ctx.reset_size()
	_ctx.popup()

func _on_ctx(idx: int) -> void:
	if not State.vehicles.has(_ctx_id):
		return
	var v: Dictionary = State.vehicles[_ctx_id]
	match idx:
		0: open_vehicle(_ctx_id)
		1: show_vehicle(_ctx_id)
		2: Game.act({"a": "veh_talk", "id": _ctx_id})
		3: open_dispatch(v["incident"])
		4: Game.act({"a": "veh_recall", "id": _ctx_id})
		5: Game.act({"a": "veh_status", "id": _ctx_id, "status": 2 if v["state"] == "oos" else 6})
		6: open_stations(v["station"])

# ---------------------------------------------------------------- Status / Eingaben
func set_status(text: String, col: Color = UI.TEXT2) -> void:
	_statusbar.text = text.replace("\n", "  ")
	_statusbar.add_theme_color_override("font_color", col)
	_statusbar_t = 0.0

func _on_notice(text: String, level: String) -> void:
	if level == "result":
		UI.message(self, "Szenario abgeschlossen", text)
	elif level == "warn":
		set_status(text, UI.YELLOW)
		UI.message(self, "Warnmeldung", text)
	else:
		set_status(text, UI.GREEN)

func _process(delta: float) -> void:
	_t += delta
	_statusbar_t += delta
	if _t < 0.25 or not State.active:
		return
	_t = 0.0
	_update_tutorial()
	var ringing := 0
	for id in State.calls:
		if State.calls[id]["state"] == "ringing":
			ringing += 1
	var talks := 0
	var free := 0
	for id in State.vehicles:
		var s := int(State.vehicles[id]["status"])
		if s == 5:
			talks += 1
		elif s == 1 or s == 2:
			free += 1
	var st := "Normalbetrieb"
	var col := UI.GREEN
	if State.meta["paused"]:
		st = "PAUSE"
		col = UI.YELLOW
	elif ringing >= 3 or State.incidents.size() >= 14:
		st = "Hohes Einsatzaufkommen"
		col = UI.RED
	elif ringing >= 1 or State.incidents.size() >= 7:
		st = "Erhöhtes Aufkommen"
		col = UI.YELLOW
	_status_labels["status"].text = "ILS Bavaria: " + st
	_status_labels["status"].add_theme_color_override("font_color", col)
	var conn: String = Net.status_text
	if Game.is_client() and Net.last_ping >= 0:
		conn += "  ·  %d ms" % Net.last_ping
	_status_labels["conn"].text = conn
	_status_labels["conn"].add_theme_color_override("font_color", UI.TEXT2 if not Net.is_online() else UI.BLUE.lightened(0.3))
	_status_labels["player"].text = Game.me["name"]
	_status_labels["player"].tooltip_text = "Rolle: %s" % Game.my_role().get("name", "")
	_status_labels["player"].mouse_filter = Control.MOUSE_FILTER_STOP
	_status_labels["date"].text = State.date_str()
	_status_labels["time"].text = State.time_str()
	_status_labels["counts"].text = "%s   ·   Notrufe wartend: %d   ·   Einsätze: %d   ·   Sprechwünsche: %d   ·   frei: %d/%d   ·   %.0f×" % [Data.modes.get("weather", {}).get(State.env["weather"], {}).get("name", ""), ringing, State.incidents.size(), talks, free, State.vehicles.size(), float(State.meta["speed"])]
	if State.meta["mode"] == "karriere":
		_status_labels["career"].text = "Budget %s   ·   Stufe %d (%d XP)" % [UI.money(int(State.meta["budget"])), int(State.meta["level"]), int(State.meta["xp"])]
	else:
		_status_labels["career"].text = "Stufe %d" % int(State.meta["level"])
	if _statusbar_t > 12.0 and _statusbar.text != "":
		_statusbar.add_theme_color_override("font_color", Color("#6b737b"))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var typing := get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit
	for action in ["call_take", "dispatch", "radio_focus", "quick_save", "pause", "fullscreen", "map_home", "talk_ack", "speed_up", "speed_down"]:
		if event.is_action_pressed("ls_" + action):
			if typing and action in ["speed_up", "speed_down", "map_home"]:
				return
			match action:
				"call_take": _menu_action("call_take")
				"dispatch": _menu_action("dispatch")
				"radio_focus": comms.focus_input()
				"quick_save": quick_save()
				"pause": _menu_action("pause")
				"fullscreen": _menu_action("fullscreen")
				"map_home": map.zoom_fit()
				"talk_ack": comms.ack_next()
				"speed_up": Game.act({"a": "set_speed", "speed": min(8.0, float(State.meta["speed"]) * 2.0)})
				"speed_down": Game.act({"a": "set_speed", "speed": max(1.0, float(State.meta["speed"]) * 0.5)})
			get_viewport().set_input_as_handled()
			return
