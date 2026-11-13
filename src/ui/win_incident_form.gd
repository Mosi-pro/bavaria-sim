extends VBoxContainer
## Einsatz manuell anlegen bzw. Einsatzdaten bearbeiten.

const UI = preload("res://src/ui/kit.gd")

var inc_id := ""
var kw: OptionButton
var addr: LineEdit
var obj: LineEdit
var persons: LineEdit
var danger: LineEdit
var note: LineEdit
var prio: OptionButton
var _keys: Array = []
var _pos := Vector2.ZERO
var _moved := false

func setup(id: String, start_pos := Vector2.ZERO) -> void:
	inc_id = id
	_keys = Data.keyword_list()
	var items: Array = []
	for k in _keys:
		items.append("%s – %s" % [k, Data.keywords[k]["name"]])
	kw = UI.option(items, 0)
	kw.clip_text = true
	kw.fit_to_longest_item = false
	addr = UI.line_edit("Einsatzort (aus Karte wählen)")
	addr.editable = false
	var pick := UI.button("Aus Karte …", func(): Game.ui.map.set_tool("pick", "Einsatzort auf der Karte anklicken", _picked))
	obj = UI.line_edit("Objekt / Meldebild")
	persons = UI.line_edit("Betroffene Personen")
	danger = UI.line_edit("Gefahrenlage")
	note = UI.line_edit("Besondere Informationen")
	prio = UI.option(["automatisch (nach Stichwort)", "1 – höchste Dringlichkeit", "2 – dringend", "3 – nicht zeitkritisch"], 0)
	add_child(UI.form([["Einsatzstichwort", kw], ["Einsatzort", UI.hbox([addr, pick])], ["Objekt / Meldebild", obj], ["Betroffene", persons], ["Gefahrenlage", danger], ["Bemerkung", note], ["Priorität", prio]]))
	if id != "" and State.incidents.has(id):
		var inc: Dictionary = State.incidents[id]
		kw.select(max(0, _keys.find(inc["keyword"])))
		addr.text = inc["address"]
		obj.text = inc["object"]
		persons.text = inc["persons"]
		danger.text = inc["danger"]
		note.text = inc["info"]
		prio.select(clampi(int(inc["prio"]), 1, 3))
		_pos = Vector2(inc["x"], inc["y"])
		pick.disabled = inc["revealed"]
	elif start_pos != Vector2.ZERO:
		_picked(start_pos)
		_moved = false
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sp)
	add_child(UI.hbox([UI.spacer(), UI.accent(UI.button("Übernehmen" if id != "" else "Einsatz anlegen", _apply), UI.BLUE), UI.button("Abbrechen", func(): get_window().queue_free())]))

func _picked(p: Vector2) -> void:
	_pos = p
	_moved = true
	addr.text = World.address_at(p)["text"]

func _apply() -> void:
	if _pos == Vector2.ZERO:
		UI.message(self, "Einsatzort", "Bitte den Einsatzort aus der Karte wählen.")
		return
	var form := {"keyword": _keys[kw.selected], "object": obj.text, "persons": persons.text, "danger": danger.text, "info": note.text}
	if prio.selected > 0:
		form["prio"] = prio.selected
	elif inc_id != "":
		form["prio"] = int(Data.keywords[_keys[kw.selected]].get("prio", 2))
	if inc_id == "" or _moved:
		form["x"] = _pos.x
		form["y"] = _pos.y
		form["address"] = addr.text
	if inc_id == "":
		Game.act({"a": "inc_create", "form": form}, func(res):
			if res.get("ok", false):
				Game.ui.open_dispatch(res["id"])
				get_window().queue_free())
	else:
		Game.act({"a": "inc_edit", "id": inc_id, "form": form}, func(res):
			if res.get("ok", false):
				get_window().queue_free())
