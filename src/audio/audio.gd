extends Node
## Audio: selbst erzeugte, zurückhaltende Signale (siehe tools/gen_audio.py).
## Kategorien mit eigener Lautstärke: effects, phone, radio, keys, ambient.

const FILES := {
	"alarm": ["effects", "alarm"], "system": ["effects", "system"], "error": ["effects", "error"], "talk": ["effects", "talk"],
	"radio": ["radio", "radio"], "voice": ["phone", "voice"], "key": ["keys", "key1"], "phone": ["phone", "phone"],
}
var _streams := {}
var _players := {}
var _ring: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _last := {}
var _key_i := 0
var enabled := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in ["alarm", "system", "error", "talk", "radio", "voice", "key1", "key2", "key3", "phone", "ambient"]:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for cat in ["effects", "radio", "phone", "keys"]:
		var arr: Array = []
		for i in 3:
			var p := AudioStreamPlayer.new()
			add_child(p)
			arr.append(p)
		_players[cat] = arr
	_ring = AudioStreamPlayer.new()
	add_child(_ring)
	_ambient = AudioStreamPlayer.new()
	add_child(_ambient)
	_loop(_ambient, "ambient")
	Sim.sound_requested.connect(play)
	refresh_volumes()

func _loop(p: AudioStreamPlayer, name: String) -> void:
	if not _streams.has(name):
		return
	var s: AudioStreamWAV = _streams[name].duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = s.data.size() / 2
	p.stream = s

func _vol(cat: String) -> float:
	var v := float(Settings.get_v("audio", cat))
	return linear_to_db(max(v, 0.0001))

func refresh_volumes() -> void:
	_ring.volume_db = _vol("phone")
	_ambient.volume_db = _vol("ambient") - 6.0

func play(name: String) -> void:
	if not enabled:
		return
	var def: Array = FILES.get(name, [])
	if def.is_empty():
		return
	var cat: String = def[0]
	var file: String = def[1]
	if cat == "keys":
		if not Settings.get_v("audio", "keys"):
			return
		_key_i = (_key_i + 1) % 3
		file = "key%d" % (_key_i + 1)
	if float(Settings.get_v("audio", cat)) <= 0.001 or not _streams.has(file):
		return
	var now := Time.get_ticks_msec()
	var gap := 900 if name == "radio" else (120 if name == "key" else (1500 if name == "phone" else 250))
	if now - int(_last.get(name, -10000)) < gap:
		return
	_last[name] = now
	for p in _players[cat]:
		if not p.playing:
			p.stream = _streams[file]
			p.volume_db = _vol(cat)
			p.play()
			return

func _process(_delta: float) -> void:
	var session: bool = State.active and Game.in_session
	var muted: bool = Settings.get_v("audio", "mute_unfocused") and not get_window().has_focus()
	AudioServer.set_bus_mute(0, muted or float(Settings.get_v("audio", "master")) <= 0.001)
	if session and float(Settings.get_v("audio", "ambient")) > 0.001:
		if not _ambient.playing and _ambient.stream != null:
			_ambient.play()
	elif _ambient.playing:
		_ambient.stop()
