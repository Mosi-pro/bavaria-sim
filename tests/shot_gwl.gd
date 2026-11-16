extends Node
## Screenshot: Alarmierung mit GW-L-Rollcontainer und Stichwortfarben in der Einsatzliste
var out := "user://screenshots"
var f := 0
var iid := ""
func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	LocalDB.put("profile", "seen_intro", true)
	add_child(load("res://scenes/main.tscn").instantiate())
func shot(name):
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)
func _process(_d):
	f += 1
	match f:
		10: get_window().size = Vector2i(1600, 900)
		20: Game.start_new({"mode": "frei", "difficulty": "leicht", "seed": 3, "start_hour": 13})
		30:
			State.meta.next_call = 1e12
			var g := {}
			for vid in State.vehicles:
				if State.vehicles[vid].type == "GWL":
					g = State.vehicles[vid]
					break
			var kws := ["RD 2", "B 2", "RD 1", "POL 1", "THL 4", "ABC 1", "POL 2"]
			for i in kws.size():
				Sim.act({"a": "inc_create", "form": {"keyword": kws[i], "x": float(g.x) + 900.0 * i, "y": float(g.y) + 500.0}}, Game.me)
			var r = Sim.act({"a": "inc_create", "form": {"keyword": "THL UNWETTER", "x": float(g.x) + 400.0, "y": float(g.y)}}, Game.me)
			iid = r.id
			State.incidents[iid].revealed = true
			State.incidents[iid].need = {"pumpen": 2, "atemschutz": 1}
			Game.ui.open_dispatch(iid)
		200: shot("g1_dispatch_gwl")
		205: get_tree().quit()
