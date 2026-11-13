extends VBoxContainer
## Linke Seitenleiste: wartende/aktive Notrufe und Einsatzübersicht.

const UI = preload("res://src/ui/kit.gd")
const IL = preload("res://src/incidents/incident_logic.gd")

signal call_activated(id)
signal incident_activated(id)
signal incident_selected(id)

const STATUS_COL := {
	"neu": Color("#C83D3D"), "in_bearbeitung": Color("#D6A83B"), "alarmiert": Color("#D98A2B"), "anfahrt": Color("#497FA8"),
	"vor_ort": Color("#3F9AA8"), "laeuft": Color("#4C9868"), "rueckfahrt": Color("#6B737B"), "abgeschlossen": Color("#4a5159"),
}

var calls_tree: Tree
var inc_tree: Tree
var calls_head: PanelContainer
var inc_head: PanelContainer
var _dirty := true
var _t := 0.0
var selected_incident := ""

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	calls_head = UI.header("Notrufe")
	add_child(calls_head)
	calls_tree = UI.tree([{"title": "Ltg.", "width": 38}, {"title": "Wartet", "width": 52}, {"title": "Anrufer / Zustand"}])
	calls_tree.custom_minimum_size.y = 118
	calls_tree.size_flags_vertical = Control.SIZE_FILL
	calls_tree.item_activated.connect(func():
		var it := calls_tree.get_selected()
		if it != null:
			call_activated.emit(it.get_metadata(0)))
	add_child(calls_tree)
	var take := UI.accent(UI.button("Notruf annehmen  (F2)", func(): call_activated.emit(next_call())), UI.RED)
	add_child(UI.margin(take, 4))
	inc_head = UI.header("Einsatzübersicht")
	add_child(inc_head)
	inc_tree = UI.tree([{"title": "Nr.", "width": 46}, {"title": "Stichwort", "width": 74}, {"title": "Einsatzort"}, {"title": "Alarm", "width": 44}, {"title": "P", "width": 18}, {"title": "Status", "width": 82}, {"title": "EM", "width": 26}])
	inc_tree.item_selected.connect(func():
		var it := inc_tree.get_selected()
		if it != null:
			selected_incident = it.get_metadata(0)
			incident_selected.emit(selected_incident))
	inc_tree.item_activated.connect(func():
		var it := inc_tree.get_selected()
		if it != null:
			incident_activated.emit(it.get_metadata(0)))
	add_child(inc_tree)
	for s in [State.incident_changed, State.incident_removed, State.call_changed, State.call_removed, State.vehicle_changed]:
		s.connect(func(_id): _dirty = true)
	State.reset_done.connect(func(): _dirty = true)

## Nächster wartender Notruf (längste Wartezeit) oder eigener aktiver Notruf.
func next_call() -> String:
	var best := ""
	var bw := -1.0
	for id in State.calls:
		var c: Dictionary = State.calls[id]
		if c["state"] == "ringing" and float(c["wait"]) > bw:
			bw = float(c["wait"])
			best = id
	if best == "":
		for id in State.calls:
			if State.calls[id]["taken_by"] == Game.me["name"]:
				return id
	return best

func _process(delta: float) -> void:
	_t += delta
	if _dirty and _t > 0.2:
		_t = 0.0
		_dirty = false
		_rebuild()
	elif _t > 1.0:
		_t = 0.0
		_update_wait()

func _update_wait() -> void:
	var root := calls_tree.get_root()
	if root == null:
		return
	for it in root.get_children():
		var id: String = it.get_metadata(0)
		if State.calls.has(id):
			var c: Dictionary = State.calls[id]
			it.set_text(1, State.dur_str(float(c["wait"]) if c["state"] == "ringing" else float(c["talk"])))

func _rebuild() -> void:
	calls_tree.clear()
	var root := calls_tree.create_item()
	var ringing := 0
	var ids: Array = State.calls.keys()
	ids.sort_custom(func(a, b): return float(State.calls[a]["t"]) < float(State.calls[b]["t"]))
	for id in ids:
		var c: Dictionary = State.calls[id]
		var it := calls_tree.create_item(root)
		it.set_metadata(0, id)
		it.set_text(0, c["line"])
		it.set_text(1, State.dur_str(float(c["wait"]) if c["state"] == "ringing" else float(c["talk"])))
		if c["state"] == "ringing":
			ringing += 1
			it.set_text(2, "ANRUF WARTET" + ("  (erneuter Anruf)" if c.get("recall", false) else ""))
			for col in 3:
				it.set_custom_bg_color(col, Color(0.78, 0.24, 0.24, 0.35))
		else:
			it.set_text(2, "im Gespräch: %s" % c["taken_by"])
			it.set_custom_color(2, UI.TEXT2)
	calls_head.get_meta("label").text = "Notrufe   (%d wartend)" % ringing
	inc_tree.clear()
	root = inc_tree.create_item()
	ids = State.incidents.keys()
	ids.sort_custom(func(a, b): return float(State.incidents[a]["t_created"]) > float(State.incidents[b]["t_created"]))
	var sel_item: TreeItem = null
	for id in ids:
		var inc: Dictionary = State.incidents[id]
		var it := inc_tree.create_item(root)
		it.set_metadata(0, id)
		it.set_text(0, String(inc["nr"]).substr(7))
		it.set_text(1, inc["keyword"])
		it.set_text(2, inc["address"])
		it.set_tooltip_text(2, "%s\n%s\n%s" % [inc["address"], inc["object"], inc["lage"]])
		it.set_text(3, State.time_str(float(inc["t_alarm"])).substr(0, 5) if float(inc["t_alarm"]) >= 0.0 else "–")
		it.set_text(4, str(int(inc["prio"])))
		it.set_custom_color(4, [UI.RED, UI.RED, UI.YELLOW, UI.BLUE][clampi(int(inc["prio"]), 1, 3)])
		var st: String = inc["status"]
		it.set_text(5, IL.STATUS_NAMES.get(st, st))
		var col: Color = STATUS_COL.get(st, UI.TEXT2)
		it.set_custom_bg_color(5, Color(col, 0.55))
		it.set_text(6, str(State.incident_vehicles(id).size()))
		if not inc.get("need", {}).is_empty() and not IL.shortage(inc["need"], IL.caps_assigned(id)).is_empty():
			it.set_custom_color(6, UI.RED)
			it.set_tooltip_text(6, "Kräfte fehlen: " + IL.need_text(IL.shortage(inc["need"], IL.caps_assigned(id))))
		if id == selected_incident:
			sel_item = it
	if sel_item != null:
		sel_item.select(0)
	inc_head.get_meta("label").text = "Einsatzübersicht   (%d aktiv)" % ids.size()

func select_incident(id: String) -> void:
	selected_incident = id
	_dirty = true
