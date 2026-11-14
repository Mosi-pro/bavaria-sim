extends Control
## Hauptmenü.

const UI = preload("res://src/ui/kit.gd")
const MapView = preload("res://src/map/map_view.gd")
const Workstation = preload("res://src/ui/workstation.gd")
const WinMP = preload("res://src/ui/win_multiplayer.gd")
const WinMisc = preload("res://src/ui/win_misc.gd")
const SaveSystem = preload("res://src/save/save_system.gd")

var map: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map = Control.new()
	map.set_script(MapView)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map)
	var dim := ColorRect.new()
	dim.color = Color(0.125, 0.137, 0.149, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.MAIN, UI.BORDER, 1, 0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = 380
	add_child(panel)
	var v := UI.vbox([], 6)
	panel.add_child(UI.margin(v, 26))
	var stripe := ColorRect.new()
	stripe.color = UI.RED
	stripe.custom_minimum_size = Vector2(0, 4)
	v.add_child(stripe)
	var title := UI.label("LEITSTELLE 112", UI.TEXT, 30)
	title.add_theme_font_override("font", UI.bold())
	v.add_child(title)
	v.add_child(UI.label("Integrierte Leitstelle Bavaria", UI.TEXT2, 14))
	v.add_child(UI.label("Feuerwehr  ·  Rettungsdienst  ·  Polizei  ·  Katastrophenschutz", Color("#6b737b"), 11))
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	v.add_child(gap)
	v.add_child(UI.caption("Neu hier?"))
	var tut := UI.accent(_btn("Einweisung – geführte erste Schicht", _start_tutorial, "Schritt für Schritt vom ersten Notruf bis zur Nachalarmierung (ca. 15 Minuten)"), UI.GREEN)
	v.add_child(tut)
	v.add_child(UI.caption("Einzelspieler"))
	v.add_child(_btn("Freies Spiel", func(): _new_game("frei"), "Unbegrenztes Spielen mit dynamisch erzeugten Einsätzen"))
	v.add_child(_btn("Karriere", func(): _new_game("karriere"), "Aufbau der Leitstelle: Regionen, Wachen, Fahrzeuge, Organisationen"))
	v.add_child(_btn("Realismusmodus", func(): _new_game("realismus"), "Echtzeit, realistische Verfügbarkeit, keine automatische Vorauswahl"))
	v.add_child(_btn("Szenarien", _scenarios, "Vordefinierte Einsatzlagen"))
	v.add_child(_btn("Spiel laden", func(): Workstation.load_dialog(self), "Gespeicherten Spielstand fortsetzen"))
	v.add_child(UI.caption("Mehrspieler (Peer-to-Peer)"))
	v.add_child(_btn("SPIEL ERSTELLEN", func(): WinMP.host_dialog(self, false), "Eigene Sitzung hosten – der eigene PC führt die Simulation aus"))
	v.add_child(_btn("MULTIPLAYER", func(): WinMP.browser(self), "Sitzung im LAN suchen oder per IP-Adresse beitreten"))
	v.add_child(UI.caption("Programm"))
	v.add_child(_btn("Einstellungen", func(): Workstation.open_settings(self)))
	v.add_child(_btn("Kurzanleitung", func(): WinMisc.help(self, "anleitung")))
	v.add_child(_btn("Beenden", func(): get_tree().quit()))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var foot := UI.label("Version %s   ·   Stadt Bavaria: %d Straßenabschnitte, %d Straßennamen\nAlle Orte, Wachen und Personen sind frei erfunden." % [ProjectSettings.get_setting("application/config/version", "1.0"), World.edge_a.size(), World.names.size()], Color("#6b737b"), 10)
	v.add_child(foot)
	Game.action_failed.connect(_on_fail)

func _on_fail(text: String) -> void:
	if is_inside_tree():
		UI.message(self, "Hinweis", text)

func _btn(text: String, cb: Callable, tip := "") -> Button:
	var b := UI.button(text, cb, tip)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 30
	return b

func _start_tutorial() -> void:
	Game.start_new({"mode": "einweisung", "name": "Einweisung", "speed": 1.0})

func _new_game(mode: String) -> void:
	var md: Dictionary = Data.modes["modes"][mode]
	var name := UI.line_edit("", "%s %s" % [md["name"], Time.get_date_string_from_system()])
	var diffs: Array = Data.modes["difficulties"].keys()
	var diff := UI.option(diffs.map(func(d): return Data.modes["difficulties"][d]["name"]), 1)
	var hours: Array = [[7, "Frühdienst – 07:30 Uhr"], [13, "Spätdienst – 13:30 Uhr"], [21, "Nachtdienst – 21:30 Uhr"]]
	var hour := UI.option(hours.map(func(h): return h[1]), 0)
	var desc := UI.label(md["desc"], UI.TEXT2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ddesc := UI.label("", UI.TEXT2, 11)
	ddesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var upd := func(i): ddesc.text = Data.modes["difficulties"][diffs[i]].get("desc", "")
	diff.item_selected.connect(upd)
	upd.call(diff.selected)
	var box := UI.vbox([desc, UI.form([["Name der Schicht", name], ["Schwierigkeit", diff], ["", ddesc], ["Dienstbeginn", hour]])])
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sp)
	box.add_child(UI.hbox([UI.spacer(), UI.accent(UI.button("Schicht beginnen", func():
		Game.start_new({"mode": mode, "difficulty": diffs[diff.selected], "name": name.text.strip_edges() if name.text.strip_edges() != "" else md["name"], "start_hour": hours[hour.selected][0], "speed": float(md.get("speed", Settings.get_v("game", "speed"))) if mode == "realismus" else float(Settings.get_v("game", "speed"))})), UI.BLUE),
		UI.button("Abbrechen", func(): box.get_window().queue_free())]))
	UI.window(self, md["name"], Vector2i(540, 300), box, "newgame")

func _scenarios() -> void:
	var tree := UI.tree([{"title": "Szenario"}], false)
	tree.custom_minimum_size.x = 260
	tree.size_flags_horizontal = Control.SIZE_FILL
	var root := tree.create_item()
	for sc in Data.scenarios:
		var it := tree.create_item(root)
		it.set_text(0, sc["name"])
		it.set_metadata(0, sc["id"])
	var desc := UI.rich(false)
	desc.scroll_following = false
	var diffs: Array = Data.modes["difficulties"].keys()
	var diff := UI.option(diffs.map(func(d): return Data.modes["difficulties"][d]["name"]), 1)
	tree.item_selected.connect(func():
		var id: String = tree.get_selected().get_metadata(0)
		for sc in Data.scenarios:
			if sc["id"] == id:
				desc.text = "[b]%s[/b]\n\n%s\n\n[color=#a4adb5]Auftrag:[/color] %s\n\n[color=#a4adb5]Beginn:[/color] %02d:00 Uhr   [color=#a4adb5]Wetter:[/color] %s   [color=#a4adb5]Dauer:[/color] ca. %d Minuten Spielzeit" % [sc["name"], sc["desc"], sc["goal"], int(sc["start_hour"]), Data.modes["weather"].get(sc["weather"], {}).get("name", ""), int(sc["duration"]) / 60])
	var box := UI.vbox([UI.hbox([tree, desc], 8)])
	box.get_child(0).size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(UI.hbox([UI.label("Schwierigkeit", UI.TEXT2), diff, UI.spacer(), UI.accent(UI.button("Szenario starten", func():
		var it := tree.get_selected()
		if it != null:
			Game.start_new({"mode": "szenario", "scenario": it.get_metadata(0), "difficulty": diffs[diff.selected], "name": it.get_text(0)})), UI.BLUE),
		UI.button("Abbrechen", func(): box.get_window().queue_free())]))
	UI.window(self, "Szenarien", Vector2i(780, 420), box, "scenarios")
	tree.get_root().get_child(0).select(0)
