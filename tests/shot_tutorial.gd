extends Node
## Entwicklungswerkzeug: Screenshots der Einweisung und der neuen Fenster.
var out := "user://screenshots"
var f := 0
var cid := ""
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	LocalDB.put("profile", "seen_intro", true)
	add_child(load("res://scenes/main.tscn").instantiate())
func shot(name):
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)
func _process(_d):
	f += 1
	match f:
		30: shot("t0_menu")
		35: Game.start_new({"mode": "einweisung", "name": "Einweisung", "speed": 1.0})
		45:
			for i in 20: Sim.step(0.5)
		60: shot("t1_call_waiting")
		65:
			cid = State.meta.tutorial.call
			Game.ui.take_call(cid)
		90: Game.act({"a": "call_ask", "id": cid, "q": "q_wo"})
		150: Game.act({"a": "call_ask", "id": cid, "q": "q_was"})
		300: shot("t2_call_window")
		305:
			for w in Game.ui.get_children():
				if w is Window and w.visible and not (w is PopupMenu):
					var wc = w.get_child(1).get_child(0)
					if wc.has_method("_create"):
						wc._create()
		340: shot("t3_dispatch")
		345:
			var iid = State.meta.tutorial.inc
			Game.act({"a": "inc_alarm", "id": iid, "vehicles": Sim.Advisor.suggest(State.incidents[iid]).suggested})
			for w in Game.ui.get_children():
				if w is Window and w.visible and not (w is PopupMenu): w.queue_free()
			for i in 600:
				Sim.step(0.5)
		380: shot("t4_running")
		390: get_tree().quit()
