extends Node
## Screenshot: Stadtkarte mit Wachen (Prüfung der Wachenanordnung)
var out := "user://screenshots"
var f := 0
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	LocalDB.put("profile", "seen_intro", true)
	add_child(load("res://scenes/main.tscn").instantiate())
func _process(_d):
	f += 1
	match f:
		10: get_window().size = Vector2i(1600, 900)
		20: Game.start_new({"mode": "frei", "difficulty": "leicht", "seed": 3, "start_hour": 13})
		40:
			State.meta.next_call = 1e12
			var m = Game.ui.map
			m.center = Vector2(-200, -600)
			m.zoom = m.size.x / 17500.0
			m._dirty = true
		200:
			get_viewport().get_texture().get_image().save_png(out + "/m1_wachen.png")
			get_tree().quit()
