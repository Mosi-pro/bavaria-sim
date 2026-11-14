extends Node
var out := "user://screenshots"
var f := 0
var cid := ""
var cid2 := ""
var iid := ""
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	LocalDB.put("profile", "seen_intro", true)
	add_child(load("res://scenes/main.tscn").instantiate())
func shot(name):
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)
func close_all():
	for w in Game.ui.get_children():
		if w is Window and not (w is PopupMenu): w.queue_free()
func _process(_d):
	f += 1
	match f:
		10: get_window().size = Vector2i(1600, 900)
		20: Game.start_new({"mode": "frei", "difficulty": "leicht", "seed": 3})
		30:
			State.meta.next_call = 1e12
			cid = Sim.CallGen.spawn_event("brand_wohnung", {"district": "westend", "variant": 1, "loc_level": 2})
			Sim.act({"a": "call_take", "id": cid}, Game.me)
			var c = State.calls[cid]
			var r = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": "B 3", "x": c.loc.x, "y": c.loc.y}}, Game.me)
			iid = r.id
			Sim.act({"a": "call_end", "id": cid}, Game.me)
			Sim.act({"a": "inc_alarm", "id": iid, "vehicles": Sim.Advisor.suggest(State.incidents[iid]).suggested}, Game.me)
			for i in 400: Sim.step(0.5)
			cid2 = Sim.CallGen.make_call(State.incidents[iid].truth, false, 1)
			Game.ui.take_call(cid2)
		40: Game.act({"a": "call_ask", "id": cid2, "q": "q_was"})
		200: shot("d1_duplicate")
		205:
			close_all()
			var c3 = Sim.CallGen.spawn_event("brand_wohnung", {"district": "suedstadt", "variant": 2, "loc_level": 2})
			Sim.act({"a": "call_take", "id": c3}, Game.me)
			var c = State.calls[c3]
			var r = Sim.act({"a": "call_create", "id": c3, "form": {"keyword": "B 3", "x": c.loc.x, "y": c.loc.y}}, Game.me)
			Sim.act({"a": "call_end", "id": c3}, Game.me)
			Game.ui.open_dispatch(r.id)
		240: shot("d2_dispatch")
		245:
			print("Funk-Beispiel:")
			for e in State.radio.slice(-6): print("  ", e.src, " ", e.get("tag", ""), " ", e.text.substr(0, 70))
			get_tree().quit()
