extends Node
## Entwicklungswerkzeug: begehbare Leitstelle aus mehreren Blickwinkeln fotografieren.
## Aufruf (mit Grafik): godot --path . res://tests/shot_building.tscn -- --out=<ordner>
var out := "user://screenshots"
var f := 0
var main
var b
var views := [
	["b_warmup", Vector3(33.5, 4.7, 12.8), PI / 2 - 0.32, -0.36],
	["b_overview", Vector3(33.5, 4.7, 12.8), PI / 2 - 0.32, -0.36],
	["b_wall", Vector3(19.0, 1.65, 8.0), -PI / 2 + 0.05, 0.06],
	["b_desk", Vector3(6.4, 1.65, 4.9), -PI / 2 + 0.3, -0.32],
	["b_gallery", Vector3(31.0, 1.65, 4.5), PI - 0.25, 0.25],
	["b_logo", Vector3(12.0, 2.2, 11.0), PI / 2 + 0.25, 0.12],
]
var vi := 0
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	Settings.set_v("game", "walkable", true)
	Settings.set_v("video", "quality", "hoch")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
func shot(name):
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)
func _process(_d):
	f += 1
	if f == 20:
		Game.start_new({"mode": "frei", "difficulty": "mittel", "seed": 7, "name": "Testschicht"})
	if f == 30:
		b = main.screen
		for i in 600: Sim.step(0.5)
	if f == 60:
		var sv = b._screens["wall"][0]
		sv.get_texture().get_image().save_png(out + "/tex_wall.png")
		b._screens["map"][0].get_texture().get_image().save_png(out + "/tex_map.png")
	if f > 72 and vi < views.size() and f % 12 == 0:
		var v = views[vi]
		b.mode = "lounge_debug"
		b.cam.global_transform = Transform3D(Basis(Vector3.UP, v[2]) * Basis(Vector3.RIGHT, v[3]), v[1])
		b._toast_t = 0
	if f > 72 and vi < views.size() and f % 12 == 10:
		shot(views[vi][0])
		vi += 1
	if vi >= views.size() and f % 12 == 11:
		# Hinsetzen am Arbeitsplatz 1 → bestehendes UI muss erscheinen
		if not b.has_meta("sat"):
			b.set_meta("sat", true)
			b.mode = "walk"
			b.body.position = Vector3(6.8, 0.05, 3.4)
			b.yaw = -PI / 2
			b.pending_seat = "ws1"
			Presence.request_seat("ws1")
	if b != null and b.has_meta("sat") and b.mode == "desk" and not b.has_meta("desk_shot"):
		b.set_meta("desk_shot", true)
		for w in Game.ui.get_children():
			if w is Window and not (w is PopupMenu): w.queue_free()
		await get_tree().create_timer(0.5).timeout
		shot("b_seated_ui")
		b.stand_up()
		await get_tree().create_timer(1.2).timeout
		shot("b_after_stand")
		print("MODE ", b.mode, " seat ", Presence.my_seat())
		get_tree().quit()
	if f > 2000:
		get_tree().quit()
