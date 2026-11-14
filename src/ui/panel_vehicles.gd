extends VBoxContainer
## Rechte Seitenleiste: sämtliche Einsatzmittel mit Filter und Sortierung.

const UI = preload("res://src/ui/kit.gd")

signal vehicle_activated(id)
signal vehicle_selected(id)
signal vehicle_context(id, pos)

const FILTERS := [["Alle", ""], ["FW", "feuerwehr"], ["RD", "rettungsdienst"], ["POL", "polizei"], ["KatS", "katastrophenschutz"], ["Sonst.", "sonstige"]]
const SORTS := ["Status", "Funkrufname", "Wache", "Fahrzeugtyp"]

var tree: Tree
var head: PanelContainer
var filter := ""
var sort_mode := 0
var search := ""
var only_free := false
var _dirty := true
var _t := 0.0
var _buttons: Array = []
var selected := ""

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	head = UI.header("Einsatzmittel")
	add_child(head)
	var fb := UI.hbox([], 2)
	for f in FILTERS:
		var b := UI.button(f[0], Callable(), "Filter: " + (f[1] if f[1] != "" else "alle Organisationen"))
		b.toggle_mode = true
		b.button_pressed = f[1] == filter
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			filter = f[1]
			for x in _buttons:
				x[0].button_pressed = x[1] == filter
			_dirty = true)
		_buttons.append([b, f[1]])
		fb.add_child(b)
	add_child(UI.margin(fb, 3))
	var se := UI.line_edit("Suche (Funkrufname, Typ, Wache)")
	se.text_changed.connect(func(t):
		search = t.to_lower()
		_dirty = true)
	var so := UI.option(SORTS, 0)
	so.tooltip_text = "Sortierung"
	so.item_selected.connect(func(i):
		sort_mode = i
		_dirty = true)
	var fr := CheckBox.new()
	fr.text = "frei"
	fr.tooltip_text = "Nur einsatzbereite Fahrzeuge (Status 1/2)"
	fr.focus_mode = Control.FOCUS_NONE
	fr.toggled.connect(func(on):
		only_free = on
		_dirty = true)
	add_child(UI.margin(UI.hbox([se, so, fr]), 3))
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 8)
	for e in [[2, "frei"], [3, "Anfahrt"], [4, "vor Ort"], [5, "Sprechwunsch"], [7, "Transport"], [6, "außer Dienst"]]:
		var chip := UI.label(" %d " % e[0], Color.WHITE, 10)
		chip.add_theme_stylebox_override("normal", UI.box(Data.fms_color(e[0]).darkened(0.15), Color(0, 0, 0, 0), 0, 2))
		legend.add_child(UI.hbox([chip, UI.label(e[1], UI.TEXT2, 10)], 3))
	legend.tooltip_text = "FMS-Status: 1/2 einsatzbereit, 3 Einsatz übernommen, 4 an der Einsatzstelle, 5 Sprechwunsch, 6 nicht einsatzbereit, 7 Patient aufgenommen, 8 am Krankenhaus"
	add_child(UI.margin(legend, 4))
	tree = UI.tree([{"title": "St", "width": 24}, {"title": "Funkrufname", "width": 150}, {"title": "Typ", "width": 62}, {"title": "Standort / Auftrag"}])
	tree.item_selected.connect(func():
		var it := tree.get_selected()
		if it != null:
			selected = it.get_metadata(0)
			vehicle_selected.emit(selected))
	tree.item_activated.connect(func():
		var it := tree.get_selected()
		if it != null:
			vehicle_activated.emit(it.get_metadata(0)))
	tree.item_mouse_selected.connect(func(pos, button):
		if button == MOUSE_BUTTON_RIGHT:
			var it := tree.get_selected()
			if it != null:
				vehicle_context.emit(it.get_metadata(0), tree.get_screen_position() + pos))
	add_child(tree)
	for s in [State.vehicle_changed, State.vehicle_removed, State.station_changed]:
		s.connect(func(_id): _dirty = true)
	State.reset_done.connect(func(): _dirty = true)

func _process(delta: float) -> void:
	_t += delta
	if _dirty and _t > 0.3:
		_t = 0.0
		_dirty = false
		_rebuild()

static func status_rank(v: Dictionary) -> int:
	return {5: 0, 0: 0, 9: 1, 3: 2, 4: 3, 7: 4, 8: 5, 1: 6, 2: 7, 6: 8}.get(int(v["status"]), 9)

func _rebuild() -> void:
	var scroll := tree.get_scroll()
	tree.clear()
	var root := tree.create_item()
	var list: Array = []
	var free := 0
	for id in State.vehicles:
		var v: Dictionary = State.vehicles[id]
		var cat: String = Data.organisations.get(v["org"], {}).get("cat", "sonstige")
		if int(v["status"]) == 1 or int(v["status"]) == 2:
			free += 1
		if filter != "" and cat != filter:
			continue
		if only_free and not (int(v["status"]) == 1 or int(v["status"]) == 2):
			continue
		if search != "":
			var hay: String = (String(v["callsign"]) + " " + String(Data.vehicle_types[v["type"]]["short"]) + " " + String(State.stations[v["station"]]["name"])).to_lower()
			if hay.find(search) < 0:
				continue
		list.append(v)
	match sort_mode:
		0: list.sort_custom(func(a, b): return [status_rank(a), a["callsign"]] < [status_rank(b), b["callsign"]])
		1: list.sort_custom(func(a, b): return a["callsign"].naturalnocasecmp_to(b["callsign"]) < 0)
		2: list.sort_custom(func(a, b): return [State.stations[a["station"]]["name"], a["callsign"]] < [State.stations[b["station"]]["name"], b["callsign"]])
		3: list.sort_custom(func(a, b): return [a["type"], a["callsign"]] < [b["type"], b["callsign"]])
	var sel_item: TreeItem = null
	for v in list:
		var it := tree.create_item(root)
		it.set_metadata(0, v["id"])
		var st := int(v["status"])
		it.set_text(0, str(st))
		it.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
		it.set_custom_bg_color(0, Color(Data.fms_color(st), 0.75))
		it.set_custom_color(0, Color.WHITE)
		it.set_tooltip_text(0, "Status %d – %s" % [st, Data.fms_text(st)])
		it.set_text(1, v["callsign"])
		it.set_custom_color(1, Data.org_color(v["org"]).lightened(0.35))
		it.set_text(2, Data.vehicle_types[v["type"]]["short"])
		var where: String = State.stations[v["station"]]["name"]
		if v["incident"] != "" and State.incidents.has(v["incident"]):
			where = "→ %s %s" % [State.incidents[v["incident"]]["keyword"], State.incidents[v["incident"]]["address"]]
		elif v["state"] == "transport" or v["state"] == "hospital":
			where = "→ %s" % v["dest_name"]
		elif v["state"] == "returning":
			where = "Rückfahrt " + where
		it.set_text(3, where)
		it.set_tooltip_text(3, where)
		if v["talk"] != "":
			for col in 4:
				it.set_custom_bg_color(col, Color(0.79, 0.48, 0.82, 0.35))
		if v["id"] == selected:
			sel_item = it
	if sel_item != null:
		sel_item.select(1)
	for c in tree.get_children(true):
		if c is VScrollBar:
			c.set_deferred("value", scroll.y)
	head.get_meta("label").text = "Einsatzmittel   (%d frei / %d gesamt)" % [free, State.vehicles.size()]
