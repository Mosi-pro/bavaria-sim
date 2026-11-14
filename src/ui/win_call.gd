extends VBoxContainer
## Notrufabfrage in drei Schritten: ① Ort klären  ② Lage klären  ③ Stichwort wählen und Einsatz anlegen.

const UI = preload("res://src/ui/kit.gd")
const IL = preload("res://src/incidents/incident_logic.gd")
const CATS := ["brand", "thl", "rd", "abc", "pol", "sonst"]

var call_id := ""
var caller_lbl: Label
var loc_lbl: Label
var loc_state: Label
var transcript: RichTextLabel
var known: RichTextLabel
var hint_lbl: Label
var cat_opt: OptionButton
var kw_opt: OptionButton
var kw_desc: Label
var details: GridContainer
var obj: LineEdit
var persons: LineEdit
var danger: LineEdit
var note: LineEdit
var attach: OptionButton
var dup_label: Label
var _kws: Array = []
var _lines := -1
var _t := 1.0
var _pos := Vector2.ZERO
var _radius := 0.0
var _manual := false
var _attach_ids: Array = []
var _closing := false
var _known_sig := ""

func _step_head(n: String, text: String) -> Label:
	var l := UI.label("%s  %s" % [n, text], UI.TEXT, 13)
	l.add_theme_font_override("font", UI.bold())
	return l

func setup(id: String) -> void:
	call_id = id
	add_theme_constant_override("separation", 6)
	caller_lbl = UI.label("", UI.TEXT2)
	caller_lbl.clip_text = true
	add_child(caller_lbl)
	# ---- links: Schritt 1 und 2
	loc_state = UI.label("", UI.TEXT)
	loc_lbl = UI.label("", UI.TEXT)
	loc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loc_lbl.custom_minimum_size.x = 300
	var b_wo := UI.accent(UI.button("Wo genau?", func(): _ask("q_wo"), "Nach Straße und Hausnummer fragen. Bei ungenauen Angaben mehrfach fragen."), UI.BLUE)
	var b_aml := UI.button("Standort orten", func(): Game.act({"a": "call_locate", "id": call_id}), "Handy-Standort abfragen (AML). Klappt nicht immer, bei Festnetz nie.")
	var b_pick := UI.button("Auf Karte wählen", func(): Game.ui.map.set_tool("pick", "Einsatzort auf der Karte anklicken", _picked), "Den Ort selbst auf der Karte festlegen")
	var b_show := UI.button("Zeigen", func():
		if _pos != Vector2.ZERO:
			Game.ui.map.focus_on(_pos, 0.5), "Ort auf der Karte anzeigen")
	var s1 := UI.vbox([_step_head("①", "Wo ist der Notfall?"), loc_state, loc_lbl, UI.hbox([b_wo, b_aml]), UI.hbox([b_pick, b_show])], 4)
	var qgrid := GridContainer.new()
	qgrid.columns = 2
	var labels := {"q_was": "Was ist passiert?", "q_personen": "Wie viele Betroffene?", "q_gefahr": "Gefahr / eingeklemmt?", "q_zustand": "Zustand Patient?", "q_beruhigen": "Anrufer beruhigen", "q_rueckruf": "Name / Rückruf"}
	var qs: Dictionary = Data.call_scripts.get("questions", {})
	for q in labels:
		var b := UI.button(labels[q], _ask.bind(q), qs.get(q, {}).get("text", ""))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if q == "q_was":
			UI.accent(b, UI.BLUE)
		qgrid.add_child(b)
	known = UI.rich(false)
	known.scroll_following = false
	known.custom_minimum_size.y = 96
	var s2 := UI.vbox([_step_head("②", "Was ist passiert?"), qgrid, UI.caption("Bisher bekannt"), known], 4)
	var left := UI.vbox([s1, HSeparator.new(), s2], 8)
	left.custom_minimum_size.x = 330
	# ---- rechts: Gespräch und Schritt 3
	transcript = UI.rich(false)
	transcript.custom_minimum_size = Vector2(400, 120)
	hint_lbl = UI.label("", UI.GREEN)
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.custom_minimum_size.x = 400
	var cat_names: Array = ["— Einsatzart wählen —"]
	for c in CATS:
		cat_names.append(Data.category_name(c))
	cat_opt = UI.option(cat_names, 0)
	cat_opt.item_selected.connect(func(_i): _fill_keywords(""))
	kw_opt = UI.option(["—"], 0)
	kw_opt.clip_text = true
	kw_opt.fit_to_longest_item = false
	kw_opt.item_selected.connect(func(_i): _update_kw_desc())
	kw_desc = UI.label("", UI.TEXT2, 11)
	kw_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kw_desc.custom_minimum_size.x = 400
	obj = UI.line_edit("z. B. Mehrfamilienhaus, 3. OG")
	persons = UI.line_edit("Anzahl / Art")
	danger = UI.line_edit("z. B. Person eingeschlossen")
	note = UI.line_edit("Besondere Hinweise")
	details = UI.form([["Objekt", obj], ["Betroffene", persons], ["Gefahr", danger], ["Bemerkung", note]])
	details.visible = false
	var more := UI.button("Weitere Angaben (optional) ▸", Callable())
	more.flat = true
	more.pressed.connect(func():
		details.visible = not details.visible
		more.text = "Weitere Angaben (optional) ▾" if details.visible else "Weitere Angaben (optional) ▸")
	dup_label = UI.label("", UI.YELLOW)
	dup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dup_label.custom_minimum_size.x = 400
	attach = UI.option(["Gehört zu laufendem Einsatz …"], 0)
	attach.item_selected.connect(_attach)
	var create := UI.accent(UI.button("Einsatz anlegen  →  Fahrzeuge wählen", _create), UI.RED)
	create.custom_minimum_size.y = 30
	var end := UI.button("Kein Einsatz nötig – auflegen", func(): UI.confirm(self, "Gespräch beenden", "Gespräch ohne Einsatz beenden?\n(Richtig bei Fehlanrufen, Scherzanrufen oder Anfragen ohne Notfall.)", func():
		Game.act({"a": "call_end", "id": call_id})
		_close()))
	var s3 := UI.vbox([_step_head("③", "Stichwort wählen und Einsatz anlegen"), hint_lbl,
		UI.form([["Einsatzart", cat_opt], ["Stichwort", kw_opt]]), kw_desc, more, details, dup_label,
		UI.hbox([create, attach, UI.spacer(), end])], 4)
	var right := UI.vbox([UI.caption("Gespräch"), transcript, HSeparator.new(), s3], 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var split := UI.hbox([left, VSeparator.new(), right], 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_fill_keywords("")
	_refresh(State.calls[id])

func _ask(q: String) -> void:
	Audio.play("key")
	Game.act({"a": "call_ask", "id": call_id, "q": q})

func _fill_keywords(select: String) -> void:
	kw_opt.clear()
	_kws = []
	if cat_opt.selected <= 0:
		kw_opt.add_item("— zuerst Einsatzart wählen —")
		kw_opt.disabled = true
		kw_desc.text = ""
		return
	kw_opt.disabled = false
	_kws = Data.keywords_in(CATS[cat_opt.selected - 1])
	kw_opt.add_item("— Stichwort wählen —")
	for k in _kws:
		kw_opt.add_item("%s – %s" % [k, Data.keywords[k]["name"]])
	if select != "" and _kws.has(select):
		kw_opt.select(_kws.find(select) + 1)
	_update_kw_desc()

func _update_kw_desc() -> void:
	var k := _keyword()
	if k == "":
		kw_desc.text = Data.categories.get(CATS[cat_opt.selected - 1], {}).get("desc", "") if cat_opt.selected > 0 else ""
		return
	var kd: Dictionary = Data.keywords[k]
	var lines: Array = []
	if String(kd.get("schlagworte", "")) != "":
		lines.append("Typisch: %s" % kd["schlagworte"])
	if String(kd.get("min", "")) != "":
		lines.append("Mindestanforderung: %s" % kd["min"])
	lines.append("Vorschlag des Systems: %s" % IL.need_text(kd.get("aao", {})))
	kw_desc.text = "\n".join(lines)

func _keyword() -> String:
	if kw_opt.disabled or kw_opt.selected <= 0 or kw_opt.selected - 1 >= _kws.size():
		return ""
	return _kws[kw_opt.selected - 1]

func _picked(p: Vector2) -> void:
	_pos = p
	_radius = 0.0
	_manual = true
	loc_lbl.text = World.address_at(p)["text"]
	loc_state.text = "● Ort selbst auf der Karte festgelegt"
	loc_state.add_theme_color_override("font_color", UI.GREEN)

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
	caller_lbl.text = "Notruf 112   ·   Tel. %s (%s)   ·   %s   ·   Gesprächsdauer %s" % [caller["phone"], "Handy" if caller["mobile"] else "Festnetz", caller["name"] if c["known"].has("callback") else "Name unbekannt", State.dur_str(float(c["talk"]))]
	var loc: Dictionary = c["loc"]
	if not loc.is_empty() and not _manual:
		var lvl := clampi(int(c["loc_level"]), 0, 2)
		loc_state.text = ["● Ort ungenau – nur der Stadtteil ist bekannt. Nachfragen!", "● Straße bekannt, Hausnummer fehlt. Nochmals nachfragen.", "● Adresse vollständig"][lvl]
		loc_state.add_theme_color_override("font_color", [UI.RED, UI.YELLOW, UI.GREEN][lvl])
		loc_lbl.text = loc["text"]
		_pos = Vector2(loc["x"], loc["y"])
		_radius = float(loc["r"])
	elif loc.is_empty() and not _manual:
		loc_state.text = "● Noch kein Ort bekannt"
		loc_state.add_theme_color_override("font_color", UI.TEXT2)
	var tr: Array = c["transcript"]
	if tr.size() != _lines:
		_lines = tr.size()
		transcript.clear()
		for l in tr:
			var who: String = l["who"]
			var col: String = {"D": "#8fb7d6", "A": "#e5e7e9", "S": "#d6a83b"}.get(who, "#e5e7e9")
			var tag: String = {"D": "Du", "A": "Anrufer", "S": "System"}.get(who, who)
			transcript.append_text("[color=%s][b]%s:[/b]  %s[/color]\n" % [col, tag, String(l["text"]).replace("[", "[lb]")])
	var k: Dictionary = c["known"]
	var sig := str(k) + str(c.get("hint", {}))
	if sig != _known_sig:
		_known_sig = sig
		var lines: Array = []
		for pair in [["what", "Ereignis"], ["persons", "Betroffene"], ["danger", "Gefahr"], ["zustand", "Zustand"], ["callback", "Rückruf"]]:
			if k.has(pair[0]):
				lines.append("[color=#a4adb5]%s:[/color] %s" % [pair[1], String(k[pair[0]]).replace("[", "[lb]")])
		known.text = "\n".join(lines) if lines.size() > 0 else "[color=#6b737b]Noch nichts. Stelle die Fragen oben.[/color]"
		if k.has("what") and obj.text == "":
			obj.text = String(k["what"]).substr(0, 80)
		var hint: Dictionary = c.get("hint", {})
		hint_lbl.text = hint.get("text", "")
		hint_lbl.visible = hint_lbl.text != ""
		if not hint.is_empty() and cat_opt.selected <= 0:
			var ci := CATS.find(hint.get("cat", ""))
			if ci >= 0:
				cat_opt.select(ci + 1)
				_fill_keywords(hint.get("keyword", ""))
	# Mehrfachmeldung?
	var near: Array = []
	if _pos != Vector2.ZERO:
		for iid in State.incidents:
			var inc: Dictionary = State.incidents[iid]
			if not inc["done"] and Vector2(inc["x"], inc["y"]).distance_to(_pos) < 450.0 + _radius:
				near.append(iid)
	if near != _attach_ids:
		_attach_ids = near
		attach.clear()
		attach.add_item("Gehört zu laufendem Einsatz …")
		for iid in near:
			attach.add_item("%s  %s" % [State.incidents[iid]["keyword"], String(State.incidents[iid]["address"]).get_slice(",", 0)])
		attach.visible = not near.is_empty()
	dup_label.text = "Achtung: In der Nähe läuft schon ein Einsatz. Wenn es derselbe Notfall ist, ordne den Anruf rechts unten dem Einsatz zu, statt einen neuen anzulegen." if near.size() > 0 else ""
	dup_label.visible = near.size() > 0

func _attach(i: int) -> void:
	if i <= 0 or i - 1 >= _attach_ids.size():
		return
	Game.act({"a": "call_attach", "id": call_id, "incident": _attach_ids[i - 1]}, func(res):
		if res.get("ok", false):
			_close())

func _create() -> void:
	var kw := _keyword()
	if kw == "":
		UI.message(self, "Einsatz anlegen", "Bitte bei Schritt ③ zuerst Einsatzart und Stichwort wählen.")
		return
	if _pos == Vector2.ZERO:
		UI.message(self, "Einsatz anlegen", "Der Einsatzort ist noch unbekannt. Frage nach dem Ort (»Wo genau?«), orte das Handy oder wähle den Ort auf der Karte.")
		return
	var form := {"keyword": kw, "x": _pos.x, "y": _pos.y, "radius": _radius, "address": loc_lbl.text, "object": obj.text, "persons": persons.text, "danger": danger.text, "info": note.text}
	var cid := call_id
	Game.act({"a": "call_create", "id": cid, "form": form}, func(res):
		if res.get("ok", false):
			Game.act({"a": "call_end", "id": cid})
			Game.ui.open_dispatch(res["id"])
			_close())
