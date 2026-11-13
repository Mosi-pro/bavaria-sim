extends VBoxContainer
## Notrufabfrage: Anruferdaten, Gesprächsprotokoll, Rückfragen und Einsatzanlage.

const UI = preload("res://src/ui/kit.gd")

var call_id := ""
var info: RichTextLabel
var transcript: RichTextLabel
var known: RichTextLabel
var kw: OptionButton
var addr: LineEdit
var obj: LineEdit
var persons: LineEdit
var danger: LineEdit
var note: LineEdit
var attach: OptionButton
var dup_label: Label
var _keys: Array = []
var _lines := -1
var _t := 1.0
var _pos := Vector2.ZERO
var _radius := 0.0
var _manual := false
var _attach_ids: Array = []
var _closing := false

func setup(id: String) -> void:
	call_id = id
	_keys = Data.keyword_list()
	var c: Dictionary = State.calls[id]
	info = UI.rich(false)
	info.scroll_following = false
	info.custom_minimum_size = Vector2(300, 150)
	info.size_flags_vertical = Control.SIZE_FILL
	var qgrid := GridContainer.new()
	qgrid.columns = 2
	var qs: Dictionary = Data.call_scripts.get("questions", {})
	for q in qs:
		var b := UI.button(qs[q]["short"], func():
			Audio.play("key")
			Game.act({"a": "call_ask", "id": call_id, "q": q}), qs[q]["text"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qgrid.add_child(b)
	var aml := UI.button("Standort orten (AML)", func(): Game.act({"a": "call_locate", "id": call_id}), "Mobilfunk-Standortdaten des Anrufers abfragen")
	var show := UI.button("Auf Karte zeigen", func():
		if _pos != Vector2.ZERO:
			Game.ui.map.focus_on(_pos, 0.5))
	known = UI.rich(false)
	known.scroll_following = false
	known.custom_minimum_size.y = 90
	var left := UI.vbox([UI.caption("Anrufer / Leitung"), info, UI.hbox([aml, show]), UI.caption("Rückfragen"), qgrid, UI.caption("Erfasste Angaben"), known])
	left.custom_minimum_size.x = 310
	transcript = UI.rich(false)
	transcript.custom_minimum_size = Vector2(380, 170)
	var items: Array = []
	for k in _keys:
		items.append("%s – %s" % [k, Data.keywords[k]["name"]])
	kw = UI.option(["— Einsatzstichwort wählen —"] + items, 0)
	kw.fit_to_longest_item = false
	kw.clip_text = true
	addr = UI.line_edit("Einsatzort")
	addr.text_changed.connect(func(_t): _manual = true)
	var pick := UI.button("Aus Karte …", func(): Game.ui.map.set_tool("pick", "Einsatzort auf der Karte anklicken", _picked))
	obj = UI.line_edit("z. B. Mehrfamilienhaus, 3. OG")
	persons = UI.line_edit("Anzahl / Art")
	danger = UI.line_edit("z. B. Person eingeschlossen, Gefahrstoff")
	note = UI.line_edit("Besondere Hinweise")
	var form := UI.form([["Stichwort", kw], ["Einsatzort", UI.hbox([addr, pick])], ["Objekt / Meldebild", obj], ["Betroffene", persons], ["Gefahrenlage", danger], ["Bemerkung", note]])
	dup_label = UI.label("", UI.YELLOW)
	dup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attach = UI.option(["Zu laufendem Einsatz hinzufügen …"], 0)
	attach.item_selected.connect(_attach)
	var create := UI.accent(UI.button("Einsatz anlegen und disponieren", _create), UI.RED)
	var end := UI.button("Kein Einsatz – Gespräch beenden", func(): UI.confirm(self, "Gespräch beenden", "Gespräch ohne Einsatz beenden?", func():
		Game.act({"a": "call_end", "id": call_id})
		_close()))
	var right := UI.vbox([UI.caption("Gesprächsprotokoll"), transcript, UI.caption("Einsatz anlegen"), form, dup_label, UI.hbox([create, attach, UI.spacer(), end])])
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var split := UI.hbox([left, VSeparator.new(), right], 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_refresh(c)

func _picked(p: Vector2) -> void:
	_pos = p
	_radius = 0.0
	_manual = true
	addr.text = World.address_at(p)["text"]

func _close() -> void:
	if _closing:
		return
	_closing = true
	var w := get_window()
	if w != null and w != get_tree().root:
		w.queue_free()

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.2:
		return
	_t = 0.0
	if not State.calls.has(call_id):
		_close()
		return
	_refresh(State.calls[call_id])

func _refresh(c: Dictionary) -> void:
	var caller: Dictionary = c["caller"]
	var name: String = caller["name"] if c["known"].has("callback") else "(noch nicht erfragt)"
	var loc: Dictionary = c["loc"]
	var lvl := int(c["loc_level"])
	var lt := "[color=#6b737b]unbekannt[/color]"
	if not loc.is_empty():
		var q: String = ["[color=#c83d3d]ungenau (Stadtteil)[/color]", "[color=#d6a83b]Straße ohne Hausnummer[/color]", "[color=#4c9868]genau[/color]"][clampi(lvl, 0, 2)]
		lt = "%s\n%s" % [loc["text"], q]
		if not _manual:
			_pos = Vector2(loc["x"], loc["y"])
			_radius = float(loc["r"])
			if addr.text != loc["text"]:
				addr.text = loc["text"]
	info.text = "[color=#a4adb5]Leitung[/color]  Notruf %s\n[color=#a4adb5]Rufnummer[/color]  %s  (%s, fiktiv)\n[color=#a4adb5]Anrufer[/color]  %s\n[color=#a4adb5]Gesprächsdauer[/color]  %s\n[color=#a4adb5]Standort[/color]  %s" % [c["line"], caller["phone"], "Mobilfunk" if caller["mobile"] else "Festnetz", name, State.dur_str(float(c["talk"])), lt]
	var tr: Array = c["transcript"]
	if tr.size() != _lines:
		_lines = tr.size()
		transcript.clear()
		for l in tr:
			var who: String = l["who"]
			var col: String = {"D": "#8fb7d6", "A": "#e5e7e9", "S": "#d6a83b"}.get(who, "#e5e7e9")
			var tag: String = {"D": "Leitstelle", "A": "Anrufer", "S": "System"}.get(who, who)
			transcript.append_text("[color=#6b737b]%s[/color]  [color=%s][b]%s:[/b]  %s[/color]\n" % [State.time_str(float(l["t"])), col, tag, String(l["text"]).replace("[", "[lb]")])
	var k: Dictionary = c["known"]
	var lines: Array = []
	for pair in [["what", "Ereignis"], ["persons", "Betroffene"], ["danger", "Gefahr"], ["zustand", "Zustand"], ["callback", "Rückruf"]]:
		if k.has(pair[0]):
			lines.append("[color=#a4adb5]%s:[/color] %s" % [pair[1], String(k[pair[0]]).replace("[", "[lb]")])
	known.text = "\n".join(lines) if lines.size() > 0 else "[color=#6b737b]Noch keine Angaben erfasst. Rückfragen stellen.[/color]"
	# mögliche Dubletten (laufende Einsätze in der Nähe)
	var near: Array = []
	if _pos != Vector2.ZERO:
		for iid in State.incidents:
			var inc: Dictionary = State.incidents[iid]
			if not inc["done"] and Vector2(inc["x"], inc["y"]).distance_to(_pos) < 450.0 + _radius:
				near.append(iid)
	if near != _attach_ids:
		_attach_ids = near
		attach.clear()
		attach.add_item("Zu laufendem Einsatz hinzufügen …")
		for iid in near:
			attach.add_item("%s  %s  %s" % [String(State.incidents[iid]["nr"]).substr(7), State.incidents[iid]["keyword"], State.incidents[iid]["address"]])
		attach.disabled = near.is_empty()
	dup_label.text = ("Hinweis: %d laufende(r) Einsatz/Einsätze im Umkreis – mögliche Mehrfachmeldung." % near.size()) if near.size() > 0 else ""
	dup_label.visible = near.size() > 0

func _attach(i: int) -> void:
	if i <= 0 or i - 1 >= _attach_ids.size():
		return
	var iid: String = _attach_ids[i - 1]
	Game.act({"a": "call_attach", "id": call_id, "incident": iid}, func(res):
		if res.get("ok", false):
			_close())

func _create() -> void:
	if kw.selected <= 0:
		UI.message(self, "Einsatz anlegen", "Bitte ein Einsatzstichwort wählen.")
		return
	if _pos == Vector2.ZERO:
		UI.message(self, "Einsatz anlegen", "Der Einsatzort ist noch unbekannt. Bitte den Anrufer befragen, den Standort orten oder den Ort aus der Karte wählen.")
		return
	var form := {"keyword": _keys[kw.selected - 1], "x": _pos.x, "y": _pos.y, "radius": _radius, "address": addr.text, "object": obj.text, "persons": persons.text, "danger": danger.text, "info": note.text}
	var cid := call_id
	Game.act({"a": "call_create", "id": cid, "form": form}, func(res):
		if res.get("ok", false):
			Game.act({"a": "call_end", "id": cid})
			Game.ui.open_dispatch(res["id"])
			_close())
