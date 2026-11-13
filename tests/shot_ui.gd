extends Node
## Entwicklungswerkzeug: fährt die Oberfläche automatisch durch und speichert Screenshots.
var out := "user://screenshots"
var f := 0
var main
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
func shot(name):
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)
func _process(_d):
	f += 1
	match f:
		30: shot("ui_menu")
		35: Game.start_new({"mode": "frei", "difficulty": "mittel", "seed": 7, "name": "Testschicht"})
		45:
			for i in 2400: Sim.step(0.5)
		70: shot("ui_work")
		75:
			var id = Game.ui.left.next_call()
			if id == "":
				Sim.CallGen.spawn_event("brand_wohnung", {"district": "westend"})
				id = Game.ui.left.next_call()
			Game.ui.take_call(id)
		80, 90, 100, 110:
			for cid in State.calls:
				if State.calls[cid].state == "active":
					Game.act({"a": "call_ask", "id": cid, "q": ["q_wo", "q_was", "q_personen", "q_gefahr"][(f - 80) / 10]})
		400: shot("ui_call")
		405:
			for cid in State.calls.keys():
				if State.calls[cid].state == "active":
					var c = State.calls[cid]
					Game.act({"a": "call_create", "id": cid, "form": {"keyword": "B 3", "x": c.loc.x, "y": c.loc.y, "address": c.loc.text, "radius": c.loc.r, "object": "Mehrfamilienhaus"}}, func(res):
						Game.act({"a": "call_end", "id": cid})
						Game.ui.open_dispatch(res.id))
		430: shot("ui_dispatch")
		435:
			var iid = Game.ui.left.selected_incident
			var s = Sim.Advisor.suggest(State.incidents[iid])
			Game.act({"a": "inc_alarm", "id": iid, "vehicles": s.suggested})
			for w in Game.ui.get_children():
				if w is Window and w.visible and not (w is PopupMenu): w.queue_free()
			Game.ui.map.focus_on(Vector2(State.incidents[iid].x, State.incidents[iid].y), 0.22)
			Game.ui.map.select("incident", iid)
		440:
			for i in 300: Sim.step(0.5)
		470: shot("ui_route")
		475: Game.ui.open_stations("fw1")
		500: shot("ui_stations")
		505:
			for w in Game.ui.get_children():
				if w is Window and w.visible and not (w is PopupMenu): w.queue_free()
			Game.ui.open_vehicle(State.vehicles.keys()[3])
			Game.ui._menu_action("settings")
		530: shot("ui_misc")
		540: get_tree().quit()
