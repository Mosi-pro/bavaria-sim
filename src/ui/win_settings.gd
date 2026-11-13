extends VBoxContainer
## Einstellungsmenü (Anzeige, Audio, Spiel, Karte, Steuerung, Netzwerk, Profil).

const UI = preload("res://src/ui/kit.gd")

var _capture := ""
var _key_buttons := {}

func setup() -> void:
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	# Anzeige
	var mode := _opt("video", "mode", [["fenster", "Fenstermodus"], ["rahmenlos", "Vollbild (rahmenloses Fenster)"], ["vollbild", "Vollbild (exklusiv)"]])
	var res := _opt("video", "resolution", Settings.RESOLUTIONS.map(func(r): return [r, r.replace("x", " × ")]))
	var qual := _opt("video", "quality", [["niedrig", "Niedrig (keine Kantenglättung)"], ["mittel", "Mittel"], ["hoch", "Hoch"]])
	var scale := _opt("video", "ui_scale", [[0.85, "85 %"], [1.0, "100 %"], [1.15, "115 %"], [1.3, "130 %"], [1.5, "150 %"]])
	tabs.add_child(_page("Anzeige", [["Darstellung", mode], ["Auflösung (Fenster)", res], ["Grafikqualität", qual], ["Skalierung der Oberfläche", scale], ["Vertikale Synchronisation", _check("video", "vsync")]]))
	# Audio
	tabs.add_child(_page("Audio", [["Gesamtlautstärke", _slider("audio", "master")], ["Signale und Alarmierung", _slider("audio", "effects")], ["Telefon", _slider("audio", "phone")], ["Funk", _slider("audio", "radio")], ["Hintergrund Leitstelle", _slider("audio", "ambient")], ["Tastaturgeräusche", _check("audio", "keys")], ["Stumm bei inaktivem Fenster", _check("audio", "mute_unfocused")]]))
	# Spiel
	var speed := _opt("game", "speed", [[1.0, "1× (Echtzeit)"], [2.0, "2×"], [4.0, "4×"], [8.0, "8×"]])
	var autosave := _opt("game", "autosave_min", [[2, "alle 2 Minuten"], [5, "alle 5 Minuten"], [10, "alle 10 Minuten"], [20, "alle 20 Minuten"]])
	var lang := UI.option(["Deutsch", "English (nicht verfügbar)"], 0)
	lang.set_item_disabled(1, true)
	tabs.add_child(_page("Spiel", [["Standard-Spielgeschwindigkeit", speed], ["Automatisches Speichern", _check("game", "autosave")], ["Autosave-Intervall", autosave], ["Sprache", lang]]))
	# Karte
	tabs.add_child(_page("Karte", [["Straßen- und Gebietsnamen", _check("map", "labels")], ["Gebäude (hohe Zoomstufe)", _check("map", "buildings")], ["Stadtteilgrenzen", _check("map", "districts")], ["Verkehrslage, Baustellen, Sperrungen", _check("map", "traffic")], ["Besondere Objekte", _check("map", "pois")], ["Wachen und Krankenhäuser", _check("map", "stations")], ["Routen ausgewählter Fahrzeuge", _check("map", "routes")], ["Fahrzeuge auf der Wache anzeigen", _check("map", "idle_vehicles")]]))
	# Steuerung
	var rows: Array = []
	for action in Settings.KEY_LABELS:
		var b := UI.button(OS.get_keycode_string(int(Settings.get_v("keys", action))), Callable(), "Klicken und neue Taste drücken")
		b.custom_minimum_size.x = 160
		b.pressed.connect(func():
			_capture = action
			b.text = "Taste drücken …")
		_key_buttons[action] = b
		rows.append([Settings.KEY_LABELS[action], b])
	rows.append(["Karte", UI.label("Ziehen: verschieben · Mausrad: zoomen · Doppelklick: hineinzoomen · Rechtsklick: Kontextmenü", UI.TEXT2)])
	tabs.add_child(_page("Steuerung", rows))
	# Netzwerk
	tabs.add_child(_page("Netzwerk", [["Spielport (UDP)", _spin("net", "port", 1024, 65535)], ["Port für LAN-Suche (UDP)", _spin("net", "discovery_port", 1024, 65535)], ["Maximale Spielerzahl (Host)", _spin("net", "max_players", 2, 8)], ["Automatische Wiederverbindung", _check("net", "reconnect")],
		["Hinweis", UI.label("Für Internetspiele muss der Spielport am Router des Hosts als UDP-Portfreigabe eingerichtet sein.", UI.TEXT2)]]))
	# Profil
	tabs.add_child(_page("Benutzerprofil", [["Name des Disponenten", _edit("profile", "name")], ["Dienstnummer", _edit("profile", "dienstnummer")]]))
	add_child(UI.hbox([UI.button("Standardwerte", func():
		Settings.reset_defaults()
		get_window().queue_free()), UI.spacer(),
		UI.accent(UI.button("Übernehmen und speichern", func():
			Settings.apply_all()
			Settings.save()
			Game.me["name"] = Settings.get_v("profile", "name")
			Audio.refresh_volumes()), UI.BLUE),
		UI.button("Schließen", func(): get_window().queue_free())]))

func _page(title: String, rows: Array) -> Control:
	var m := UI.margin(UI.form(rows), 10)
	m.name = title
	return m

func _opt(sec: String, key: String, items: Array) -> OptionButton:
	var o := UI.option(items.map(func(i): return i[1]), 0)
	var cur = Settings.get_v(sec, key)
	for i in items.size():
		if typeof(items[i][0]) == TYPE_STRING:
			if String(cur) == items[i][0]:
				o.select(i)
		elif is_equal_approx(float(cur), float(items[i][0])):
			o.select(i)
	o.item_selected.connect(func(i): Settings.set_v(sec, key, items[i][0]))
	return o

func _check(sec: String, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = bool(Settings.get_v(sec, key))
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on): Settings.set_v(sec, key, on))
	return c

func _slider(sec: String, key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get_v(sec, key))
	s.custom_minimum_size = Vector2(260, 18)
	s.value_changed.connect(func(v):
		Settings.set_v(sec, key, v)
		Settings.apply_audio()
		Audio.refresh_volumes())
	s.drag_ended.connect(func(_c): Audio.play("system"))
	return s

func _spin(sec: String, key: String, lo: int, hi: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = int(Settings.get_v(sec, key))
	s.value_changed.connect(func(v): Settings.set_v(sec, key, int(v)))
	return s

func _edit(sec: String, key: String) -> LineEdit:
	var e := UI.line_edit("", String(Settings.get_v(sec, key)))
	e.max_length = 24
	e.text_changed.connect(func(t):
		if t.strip_edges() != "":
			Settings.set_v(sec, key, t.strip_edges()))
	return e

func _input(event: InputEvent) -> void:
	if _capture != "" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.keycode != KEY_ESCAPE:
			Settings.set_v("keys", _capture, int(event.keycode))
		_key_buttons[_capture].text = OS.get_keycode_string(int(Settings.get_v("keys", _capture)))
		_capture = ""
