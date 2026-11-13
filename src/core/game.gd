extends Node
## Sitzungssteuerung: Spielstart, Laden/Speichern, Weiterleitung von Aktionen
## (lokal an die Simulation oder über das Netzwerk an den Host).

const SaveSystem = preload("res://src/save/save_system.gd")

signal session_started
signal session_ended(reason)
signal action_failed(text)

var in_session := false
var ui: Control = null
var me := {"id": 1, "name": "Disponent", "role": "leitung"}

func _ready() -> void:
	me["name"] = Settings.get_v("profile", "name")
	Sim.autosave_due.connect(_on_autosave)
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_client() -> bool:
	return Net.mode == Net.MODE_CLIENT

func is_host() -> bool:
	return Net.mode == Net.MODE_HOST

func is_authority() -> bool:
	return Net.mode != Net.MODE_CLIENT

func my_role() -> Dictionary:
	return Data.roles.get(me["role"], {})

func start_new(opts: Dictionary) -> void:
	me["name"] = Settings.get_v("profile", "name")
	if not is_host():
		me["role"] = "leitung"
	Sim.new_game(opts)
	in_session = true
	session_started.emit()

func load_game(id: String) -> String:
	var err := SaveSystem.load_game(id)
	if err != "":
		return err
	me["name"] = Settings.get_v("profile", "name")
	if not is_host():
		me["role"] = "leitung"
	State.meta["paused"] = false
	Sim.resume_loaded()
	in_session = true
	session_started.emit()
	return ""

## Client: Sitzung beginnt, sobald der vollständige Zustand vom Host vorliegt.
func start_as_client() -> void:
	Sim.stop()
	World.ensure_built()
	Sim._build_hospitals()
	in_session = true
	session_started.emit()

func save(name: String) -> String:
	if is_client():
		return "Im Mehrspielermodus verwaltet der Host den Spielstand."
	return SaveSystem.save(name)

func _on_autosave() -> void:
	if in_session and is_authority():
		var name: String = State.meta.get("name", "Schicht")
		var err := SaveSystem.save("Autosave – " + name.trim_prefix("Autosave – "))
		if err == "":
			Sim.radio("Leitstelle", "Automatische Speicherung durchgeführt.", -1, "system", "")

func leave(reason := "") -> void:
	if not in_session:
		return
	in_session = false
	Sim.stop()
	Net.shutdown()
	State.reset()
	session_ended.emit(reason)

## Aktion ausführen. callback(result: Dictionary) wird nach Ausführung aufgerufen.
func act(a: Dictionary, callback: Callable = Callable()) -> void:
	if is_client():
		Net.send_action(a, callback)
		return
	var res: Dictionary = Sim.act(a, me)
	if not res.get("ok", false) and res.get("err", "") != "":
		action_failed.emit(res["err"])
	if callback.is_valid():
		callback.call(res)
