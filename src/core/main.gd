extends Control
## Wurzel der Anwendung: wechselt zwischen Hauptmenü und Leitstellenarbeitsplatz.

const UI = preload("res://src/ui/kit.gd")
const MainMenu = preload("res://src/ui/main_menu.gd")
const Workstation = preload("res://src/ui/workstation.gd")

var screen: Control

func _ready() -> void:
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
