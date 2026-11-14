extends Control
## Wurzel der Anwendung: wechselt zwischen Hauptmenü und Leitstellenarbeitsplatz.

const UI = preload("res://src/ui/kit.gd")
const MainMenu = preload("res://src/ui/main_menu.gd")
const Workstation = preload("res://src/ui/workstation.gd")

var screen: Control

func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if args.has("--vermittlung"):
		_run_relay(args)
		return
	theme = UI.theme()
	get_window().title = "LEITSTELLE 112 – Integrierte Leitstelle Bavaria"
	get_window().min_size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var loading := UI.label("Stadt Bavaria wird aufgebaut …", UI.TEXT2, 14)
	loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(loading)
	await get_tree().process_frame
	await get_tree().process_frame
	World.ensure_built()
	loading.queue_free()
	if OS.get_cmdline_args().has("--selbsttest") or OS.get_cmdline_user_args().has("--selbsttest"):
		_selftest()
		return
	Game.session_started.connect(_show_workstation)
	Game.session_ended.connect(_on_session_ended)
	Net.connection_lost.connect(func(text): Game.leave(text))
	Net.game_started.connect(func(): pass)
	get_tree().set_auto_accept_quit(false)
	_show_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if Game.in_session:
			UI.confirm(self, "Programm beenden", "LEITSTELLE 112 beenden? Nicht gespeicherter Fortschritt geht verloren.", func():
				Net.shutdown()
				get_tree().quit())
		else:
			get_tree().quit()

func _swap(next: Control) -> void:
	if screen != null:
		screen.queue_free()
	screen = next
	add_child(screen)

func _show_menu() -> void:
	Game.ui = null
	var m := Control.new()
	m.set_script(MainMenu)
	_swap(m)

func _show_workstation() -> void:
	var w := Control.new()
	w.set_script(Workstation)
	_swap(w)

func _on_session_ended(reason: String) -> void:
	if reason == "__reload__":
		return
	_show_menu()
	if reason != "":
		UI.message(screen, "Sitzung beendet", reason)

## Selbsttest der installierten Anwendung (Aufruf: LEITSTELLE112.exe --headless --selbsttest).
## Prüft Konfiguration, Stadtaufbau, Notruf → Einsatz → Alarmierung → Anfahrt sowie Speichern/Laden.
func _selftest() -> void:
	const Advisor = preload("res://src/dispatch/advisor.gd")
	const CallGen = preload("res://src/incidents/call_generator.gd")
	const SaveSystem = preload("res://src/save/save_system.gd")
	var me := {"name": "Selbsttest", "role": "leitung"}
	var ok := true
	var report := func(cond: bool, text: String):
		print(("[OK]     " if cond else "[FEHLER] ") + text)
		if not cond:
			ok = false
	report.call(Data.vehicle_types.size() > 30 and Data.stations.size() > 50 and Data.incident_types.size() > 20, "Konfiguration geladen (%d Fahrzeugtypen, %d Wachen, %d Einsatzarten)" % [Data.vehicle_types.size(), Data.stations.size(), Data.incident_types.size()])
	report.call(World.edge_a.size() > 8000, "Stadt Bavaria aufgebaut (%d Straßenabschnitte)" % World.edge_a.size())
	Settings.set_v("game", "autosave", false)
	Sim.new_game({"mode": "frei", "seed": 112})
	Sim.running = false
	State.meta["next_call"] = 1e12
	var cid := CallGen.spawn_event("brand_wohnung", {"district": "altstadt", "variant": 1})
	report.call(Sim.act({"a": "call_take", "id": cid}, me)["ok"], "Notruf angenommen")
	var c: Dictionary = State.calls[cid]
	CallGen._set_loc_level(c, State.truths[c["truth"]], 2)
	var res: Dictionary = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": "B 3", "x": c["loc"]["x"], "y": c["loc"]["y"]}}, me)
	report.call(res.get("ok", false), "Einsatz angelegt")
	var inc: Dictionary = State.incidents[res["id"]]
	var sug: Array = Advisor.suggest(inc)["suggested"]
	report.call(Sim.act({"a": "inc_alarm", "id": inc["id"], "vehicles": sug}, me)["ok"], "%d Fahrzeuge alarmiert" % sug.size())
	for i in 1200:
		Sim.step(0.5)
		if inc["revealed"]:
			break
	report.call(inc["revealed"], "Fahrzeuge an der Einsatzstelle eingetroffen, Lagemeldung erhalten")
	report.call(SaveSystem.save("Selbsttest") == "" and SaveSystem.load_game("selbsttest") == "", "Spielstand gespeichert und geladen")
	SaveSystem.delete("selbsttest")
	var key := Sim.Personnel != null
	report.call(key, "Module vollständig")
	print("SELBSTTEST " + ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))
	get_tree().quit(0 if ok else 1)

## Vermittlungsdienst ohne Oberfläche (z. B. auf dem Dell Wyse).
func _run_relay(args: Array) -> void:
	const RelayServer = preload("res://src/multiplayer/relay_server.gd")
	var port := int(Data.network.get("relay_port", 24180))
	for a in args:
		if String(a).begins_with("--port="):
			port = int(String(a).substr(7))
	Audio.enabled = false
	var srv := Node.new()
	srv.set_script(RelayServer)
	add_child(srv)
	if srv.start(port) != OK:
		get_tree().quit(1)
