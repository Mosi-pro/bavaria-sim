extends VBoxContainer
## Aufgabenliste „Was ist zu tun?“: zeigt die offenen Arbeitsschritte nach Dringlichkeit
## mit einem Knopf für die nächste Aktion. Bei leichten Schwierigkeitsgraden mit Erklärung.

const UI = preload("res://src/ui/kit.gd")
const IL = preload("res://src/incidents/incident_logic.gd")

var head: PanelContainer
var list: VBoxContainer
var empty: Label
var _sig := ""
var _t := 1.0

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	head = UI.header("Was ist zu tun?")
	add_child(head)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UI.box(UI.TABLE, UI.BORDER, 1, 3))
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.add_child(sc)
	add_child(bg)
	list = UI.vbox([], 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	empty = UI.label("Alles erledigt. Neue Notrufe erscheinen hier automatisch.", UI.TEXT2)
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.custom_minimum_size.x = 200

func _explain() -> bool:
	return State.meta.get("mode", "") == "einweisung" or Data.modes.get("difficulties", {}).get(State.meta.get("difficulty", ""), {}).get("hint", "none") != "none"

## Offene Aufgaben: [prio, farbe, titel, erklärung, knopf, aktion, id]
func tasks() -> Array:
	var out: Array = []
	var role: Dictionary = Game.my_role()
	var me: String = Game.me["name"]
	if role.get("calls", false):
		for cid in State.calls:
			var c: Dictionary = State.calls[cid]
			if c["state"] == "ringing":
				out.append([0, UI.RED, "Notruf wartet  (%s)" % State.dur_str(float(c["wait"])), "Anrufer legt sonst auf. Annehmen und Ort/Lage erfragen.", "Annehmen", "call", cid])
			elif c["taken_by"] == me:
				out.append([1, UI.YELLOW, "Notruf im Gespräch", "Ort und Lage klären, dann Stichwort wählen und Einsatz anlegen.", "Öffnen", "call", cid])
	if role.get("incidents", false):
		for vid in State.vehicles:
			var v: Dictionary = State.vehicles[vid]
			if v["talk"] != "" and role.get("orgs", []).has(v["org"]):
				out.append([2, Color("#C97BD1"), "Sprechwunsch: %s" % UI.short_callsign(v), "Fahrzeug möchte etwas melden (Status 5). Sprechaufforderung geben.", "Sprechen", "talk", vid])
		for iid in State.incidents:
			var inc: Dictionary = State.incidents[iid]
			var nr: String = String(inc["nr"]).substr(7)
			var where: String = String(inc["address"]).get_slice(",", 0)
			if inc["done"]:
				out.append([5, UI.GREEN, "Einsatz beendet: %s %s" % [inc["keyword"], where], "Fahrzeuge fahren zurück. Einsatz abschließen und archivieren.", "Abschließen", "close", iid])
			elif State.incident_vehicles(iid).is_empty():
				out.append([3, UI.RED, "Keine Fahrzeuge: %s %s" % [inc["keyword"], where], "Einsatz %s wurde noch nicht alarmiert." % nr, "Disponieren", "dispatch", iid])
			elif inc["revealed"] and not inc.get("need", {}).is_empty():
				var miss := IL.shortage(inc["need"], IL.caps_assigned(iid))
				if not miss.is_empty():
					out.append([4, Color("#D98A2B"), "Kräfte fehlen: %s %s" % [inc["keyword"], where], "Benötigt noch: %s" % IL.need_text(miss), "Nachalarmieren", "dispatch", iid])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5 or not State.active:
		return
	_t = 0.0
	var ts := tasks()
	var sig := ""
	for t in ts:
		sig += "%s|%s|%s;" % [t[2], t[3], t[6]]
	if sig == _sig:
		return
	_sig = sig
	for c in list.get_children():
		list.remove_child(c)
		if c != empty:
			c.queue_free()
	head.get_meta("label").text = "Was ist zu tun?   (%d)" % ts.size() if ts.size() > 0 else "Was ist zu tun?"
	if ts.is_empty():
		list.add_child(empty)
		return
	var explain := _explain()
	for t in ts:
		list.add_child(_row(t, explain))

func _row(t: Array, explain: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(UI.MAIN, Color(0, 0, 0, 0), 0, 4))
	var bar := ColorRect.new()
	bar.color = t[1]
	bar.custom_minimum_size = Vector2(4, 0)
	var title := UI.label(t[2], UI.TEXT)
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var texts := UI.vbox([title], 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if explain or t[5] == "dispatch":
		var sub := UI.label(t[3], UI.TEXT2, 11)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size.x = 150
		texts.add_child(sub)
	var b := UI.button(t[4], func(): _do(t[5], t[6]))
	b.custom_minimum_size.x = 104
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if t[0] <= 2:
		UI.accent(b, t[1].darkened(0.1))
	p.add_child(UI.hbox([bar, texts, b], 6))
	return p

func _do(action: String, id: String) -> void:
	var ui: Control = Game.ui
	match action:
		"call": ui.take_call(id)
		"talk": Game.act({"a": "veh_talk", "id": id})
		"dispatch": ui.open_dispatch(id)
		"close":
			Game.act({"a": "inc_close", "id": id})
