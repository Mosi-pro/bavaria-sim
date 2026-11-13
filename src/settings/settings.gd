extends Node
## Einstellungen (lokal gespeichert in user://settings.cfg).

signal changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"video": {"mode": "fenster", "resolution": "1600x900", "quality": "hoch", "vsync": true, "ui_scale": 1.0},
	"audio": {"master": 0.8, "effects": 0.8, "radio": 0.7, "ambient": 0.35, "phone": 0.9, "keys": true, "mute_unfocused": false},
	"game": {"speed": 2.0, "autosave_min": 5, "autosave": true, "language": "de", "pause_on_call": false, "confirm_alarm": false},
	"map": {"labels": true, "buildings": true, "districts": true, "traffic": true, "pois": true, "stations": true, "routes": true, "idle_vehicles": false},
	"net": {"port": 24112, "discovery_port": 24113, "max_players": 6, "last_host": "", "reconnect": true},
	"profile": {"name": "Disponent", "dienstnummer": "ILS-0112", "role": "leitung"},
	"keys": {"call_take": KEY_F2, "dispatch": KEY_F3, "radio_focus": KEY_F4, "quick_save": KEY_F5, "pause": KEY_PAUSE, "speed_up": KEY_KP_ADD, "speed_down": KEY_KP_SUBTRACT, "fullscreen": KEY_F11, "map_home": KEY_HOME, "talk_ack": KEY_F6},
}
const KEY_LABELS := {"call_take": "Notruf annehmen", "dispatch": "Einsatz disponieren", "radio_focus": "Funk-/Texteingabe", "quick_save": "Schnellspeichern", "pause": "Pause", "speed_up": "Spielgeschwindigkeit erhöhen", "speed_down": "Spielgeschwindigkeit verringern", "fullscreen": "Vollbild umschalten", "map_home": "Karte: Gesamtansicht", "talk_ack": "Sprechwunsch annehmen"}
const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]

var data: Dictionary = {}

func _ready() -> void:
	data = DEFAULTS.duplicate(true)
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for sec in cf.get_sections():
			if not data.has(sec):
				data[sec] = {}
			for key in cf.get_section_keys(sec):
				data[sec][key] = cf.get_value(sec, key)
	apply_all()

func get_v(sec: String, key: String):
	return data.get(sec, {}).get(key, DEFAULTS.get(sec, {}).get(key))

func set_v(sec: String, key: String, value) -> void:
	if not data.has(sec):
		data[sec] = {}
	data[sec][key] = value

func save() -> void:
	var cf := ConfigFile.new()
	for sec in data:
		for key in data[sec]:
			cf.set_value(sec, key, data[sec][key])
	cf.save(PATH)
	changed.emit()

func reset_defaults() -> void:
	data = DEFAULTS.duplicate(true)
	apply_all()
	save()

func apply_all() -> void:
	apply_keys()
	apply_audio()
	if DisplayServer.get_name() != "headless":
		apply_video()

func apply_video() -> void:
	var win := get_window()
	var mode: String = get_v("video", "mode")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_v("video", "vsync") else DisplayServer.VSYNC_DISABLED)
	if mode == "vollbild":
		win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	elif mode == "rahmenlos":
		win.mode = Window.MODE_FULLSCREEN
	else:
		if win.mode != Window.MODE_WINDOWED and win.mode != Window.MODE_MAXIMIZED:
			win.mode = Window.MODE_WINDOWED
		var parts: PackedStringArray = String(get_v("video", "resolution")).split("x")
		if parts.size() == 2 and win.mode == Window.MODE_WINDOWED:
			var size := Vector2i(int(parts[0]), int(parts[1]))
			var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
			size.x = min(size.x, screen.size.x)
			size.y = min(size.y, screen.size.y)
			win.size = size
			win.position = screen.position + (screen.size - size) / 2
	var q: String = get_v("video", "quality")
	get_viewport().msaa_2d = {"niedrig": Viewport.MSAA_DISABLED, "mittel": Viewport.MSAA_2X, "hoch": Viewport.MSAA_4X}.get(q, Viewport.MSAA_2X)
	win.content_scale_factor = clampf(float(get_v("video", "ui_scale")), 0.75, 2.0)

func apply_audio() -> void:
	var master := AudioServer.get_bus_index("Master")
	var vol: float = get_v("audio", "master")
	AudioServer.set_bus_volume_db(master, linear_to_db(max(vol, 0.0001)))
	AudioServer.set_bus_mute(master, vol <= 0.001)

func apply_keys() -> void:
	for action in DEFAULTS["keys"]:
		var name := "ls_" + String(action)
		if InputMap.has_action(name):
			InputMap.action_erase_events(name)
		else:
			InputMap.add_action(name)
		var ev := InputEventKey.new()
		ev.keycode = int(get_v("keys", action))
		InputMap.action_add_event(name, ev)

func quality_level() -> int:
	return {"niedrig": 0, "mittel": 1, "hoch": 2}.get(get_v("video", "quality"), 1)
