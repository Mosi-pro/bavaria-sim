extends VBoxContainer
## Linke Seitenleiste: wartende/aktive Notrufe und Einsatzübersicht.

const Areas = preload("res://src/simulation/areas.gd")
const UI = preload("res://src/ui/kit.gd")
const IL = preload("res://src/incidents/incident_logic.gd")

signal call_activated(id)
signal incident_activated(id)
signal incident_selected(id)

const STATUS_COL := {
	"neu": Color("#C83D3D"), "in_bearbeitung": Color("#D6A83B"), "alarmiert": Color("#D98A2B"), "anfahrt": Color("#497FA8"),
	"vor_ort": Color("#3F9AA8"), "laeuft": Color("#4C9868"), "rueckfahrt": Color("#6B737B"), "abgeschlossen": Color("#4a5159"),
}

var inc_tree: Tree
var inc_head: PanelContainer
var _dirty := true
var _t := 0.0
var selected_incident := ""

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	inc_head = UI.header("Laufende Einsätze")
	add_child(inc_head)
	inc_tree = UI.tree([{"title": "Stichwort", "width": 74}, {"title": "Einsatzort"}, {"title": "Status", "width": 96}, {"title": "Fzg.", "width": 34}])
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
	var hint := UI.label("Doppelklick öffnet die Einsatzakte.", Color("#6b737b"), 10)
	add_child(UI.margin(hint, 3))
	for s in [State.incident_changed, State.incident_removed, State.vehicle_changed]:
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
	if _dirty and _t > 0.3:
		_t = 0.0
		_dirty = false
		_rebuild()

func _rebuild() -> void:
	inc_tree.clear()
	var root := inc_tree.create_item()
	var ids: Array = State.incidents.keys()
	ids.sort_custom(func(a, b): return float(State.incidents[a]["t_created"]) > float(State.incidents[b]["t_created"]))
	var sel_item: TreeItem = null
	for id in ids:
		var inc: Dictionary = State.incidents[id]
		var it := inc_tree.create_item(root)
		it.set_metadata(0, id)
		it.set_text(0, inc["keyword"])
		it.set_custom_color(0, Data.keyword_color(inc["keyword"]))
		it.set_tooltip_text(0, "%s – Priorität %d" % [Data.keywords.get(inc["keyword"], {}).get("name", ""), int(inc["prio"])])
		it.set_text(1, String(inc["address"]).get_slice(",", 0))
		var ia: String = String(inc.get("area", ""))
		var foreign: bool = not Areas.mine(Game.me, ia) and not Areas.owners(ia).is_empty()
		it.set_tooltip_text(1, "Einsatz %s\n%s\n%s%s" % [inc["nr"], inc["address"], inc["lage"], ("\nGebiet %s – zuständig: %s" % [Areas.name(ia), ", ".join(Areas.owners(ia))]) if foreign else ""])
		if foreign:
			it.set_custom_color(1, UI.TEXT2.darkened(0.25))
			it.set_text(1, "[%s] %s" % [Areas.name(ia), it.get_text(1)])
		var st: String = inc["status"]
		it.set_text(2, IL.STATUS_NAMES.get(st, st))
		var col: Color = STATUS_COL.get(st, UI.TEXT2)
		it.set_custom_bg_color(2, Color(col, 0.55))
		it.set_text(3, str(State.incident_vehicles(id).size()))
		it.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)
		if not inc.get("need", {}).is_empty() and not IL.shortage(inc["need"], IL.caps_assigned(id)).is_empty():
			it.set_custom_color(3, UI.RED)
			it.set_tooltip_text(3, "Kräfte fehlen: " + IL.need_text(IL.shortage(inc["need"], IL.caps_assigned(id))))
		if id == selected_incident:
			sel_item = it
	if sel_item != null:
		sel_item.select(0)
	inc_head.get_meta("label").text = "Laufende Einsätze   (%d)" % ids.size()

func select_incident(id: String) -> void:
	selected_incident = id
	_dirty = true
