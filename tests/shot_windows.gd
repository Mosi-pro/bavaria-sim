extends Node
## Entwicklungswerkzeug: alle wichtigen Fenster bei kleiner Auflösung öffnen und prüfen,
## ob sie vollständig im Bild liegen.
const UI = preload("res://src/ui/kit.gd")
var out := "user://screenshots"
var f := 0
var cid := ""
var problems: Array = []
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	LocalDB.put("profile", "seen_intro", true)
	add_child(load("res://scenes/main.tscn").instantiate())
func close_all():
	for w in Game.ui.get_children():
		if w is Window and not (w is PopupMenu): w.queue_free()
func check_windows(tag):
	var vp: Vector2 = get_viewport().get_visible_rect().size
	for w in Game.ui.get_children() if Game.ui != null else []:
		if w is Window and w.visible and not (w is PopupMenu):
			var r := Rect2(Vector2(w.position) - Vector2(0, 26), Vector2(w.size) + Vector2(0, 26))
			if r.position.y < 0 or r.end.y > vp.y + 1 or r.position.x < 0 or r.end.x > vp.x + 1:
				problems.append("%s: Fenster »%s« ragt aus dem Bild (%s)" % [tag, w.title, str(r)])
func shot(name):
	check_windows(name)
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)
func _process(_d):
	f += 1
	match f:
		10:
			get_window().size = Vector2i(1280, 720)
		30: Game.start_new({"mode": "frei", "seed": 3, "name": "Test"})
		40:
			for i in 1200: Sim.step(0.5)
			cid = Sim.CallGen.spawn_event("brand_wohnung", {"district": "westend", "variant": 1})
			Game.ui.take_call(cid)
		60:
			for q in ["q_wo", "q_was", "q_personen", "q_gefahr", "q_zustand", "q_rueckruf"]:
				Game.act({"a": "call_ask", "id": cid, "q": q})
		300: shot("w1_call")
		305:
			var c = State.calls[cid]
			Game.act({"a": "call_create", "id": cid, "form": {"keyword": "B 3", "x": c.loc.x, "y": c.loc.y}}, func(r):
				Game.act({"a": "call_end", "id": cid})
				close_all()
				Game.ui.open_dispatch(r.id))
		330: shot("w2_dispatch")
		335:
			close_all()
			Game.ui.open_stations("fw1")
		360: shot("w3_stations")
		365:
			close_all()
			Game.ui._menu_action("settings")
		385: shot("w4_settings")
		390:
			close_all()
			Game.ui._first_visit_force()
		410: shot("w5_message")
		415:
			close_all()
			UI.confirm(Game.ui, "Test", "Eine sehr lange Frage ".repeat(120), func(): pass)
		435: shot("w6_confirm_long")
		440:
			close_all()
			Game.ui._menu_action("h_stichworte")
		460: shot("w7_help")
		465:
			close_all()
			Game.ui._menu_action("stats")
		485: shot("w8_stats")
		490:
			close_all()
			Game.ui.open_vehicle(State.vehicles.keys()[5])
		510: shot("w9_vehicle")
		515:
			for p in problems: print("PROBLEM ", p)
			print("PRUEFUNG ", "OK" if problems.is_empty() else "FEHLER")
			get_tree().quit()
