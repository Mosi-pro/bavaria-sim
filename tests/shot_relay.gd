extends Node
var out := "user://screenshots"
var f := 0
const WinMP = preload("res://src/ui/win_multiplayer.gd")
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--relay="): Settings.set_v("net", "relay_url", a.substr(8))
	LocalDB.put("profile", "seen_intro", true)
	add_child(load("res://scenes/main.tscn").instantiate())
func shot(name):
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)
func _process(_d):
	f += 1
	var menu = get_child(0).screen
	match f:
		10: get_window().size = Vector2i(1280, 720)
		30: WinMP.host_dialog(menu, false)
		45: shot("r1_host_dialog")
		50:
			for w in menu.get_children():
				if w is Window: w.queue_free()
			Net.host({"name": "Leitstelle Testgruppe", "password": "x", "relay": true, "game_mode": "Freies Spiel"})
			WinMP.lobby(menu)
		120: shot("r2_lobby")
		125:
			for w in menu.get_children():
				if w is Window: w.queue_free()
			WinMP.browser(menu)
		200: shot("r3_browser")
		205: get_tree().quit()
