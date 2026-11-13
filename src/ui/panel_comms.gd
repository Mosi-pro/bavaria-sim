extends VBoxContainer
## Unterer Bereich: Funk- und Nachrichtenprotokoll, Sprechwünsche, Systemmeldungen, Chat.

const UI = preload("res://src/ui/kit.gd")

signal vehicle_requested(id)

var tabs: TabContainer
var funk: RichTextLabel
var system: RichTextLabel
var notes: RichTextLabel
var chat: RichTextLabel
var talk_tree: Tree
var input: LineEdit
var target: OptionButton
var _talk_dirty := true
var _t := 0.0

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	funk = UI.rich(true)
	funk.name = "Funkprotokoll"
	tabs.add_child(funk)
	talk_tree = UI.tree([{"title": "Seit", "width": 52}, {"title": "Funkrufname", "width": 170}, {"title": "Einsatz"}])
	talk_tree.name = "Sprechwünsche"
	talk_tree.item_activated.connect(_ack_selected)
	var tv := UI.vbox([talk_tree, UI.hbox([UI.button("Sprechaufforderung (J) geben  [F6]", _ack_selected), UI.button("Alle annehmen", _ack_all), UI.spacer()])])
	tv.name = "Sprechwünsche"
	tabs.add_child(tv)
	system = UI.rich(true)
	system.name = "Systemmeldungen"
	tabs.add_child(system)
	notes = UI.rich(true)
	notes.name = "Einsatznotizen"
	tabs.add_child(notes)
	chat = UI.rich(false)
	chat.name = "Chat"
	tabs.add_child(chat)
	target = UI.option(["Textnachricht an alle", "Chat (Mitspieler)"], 0)
	input = UI.line_edit("Nachricht eingeben …  (Enter sendet)")
	input.text_submitted.connect(func(_t): _send())
	input.focus_entered.connect(func(): Audio.play("key"))
	add_child(UI.margin(UI.hbox([target, input, UI.button("Senden", _send)]), 3))
	State.radio_added.connect(_on_radio)
	State.chat_added.connect(_on_chat)
	State.vehicle_changed.connect(func(_id): _talk_dirty = true)
	State.reset_done.connect(_reload)
	_reload()

func focus_input() -> void:
	input.grab_focus()

func _reload() -> void:
	for r in [funk, system, notes, chat]:
		r.clear()
	for e in State.radio:
		_on_radio(e, false)
	for e in State.chat:
		_on_chat(e)
	_talk_dirty = true

func _status_tag(st: int) -> String:
	if st < 0:
		return "   "
	return "[bgcolor=%s][color=#ffffff] %d [/color][/bgcolor]" % [UI.hex(Data.fms_color(st).darkened(0.15)), st]

func _on_radio(e: Dictionary, sound := true) -> void:
	var time := State.time_str(float(e["t"]))
	var kind: String = e["kind"]
	var src: String = e["src"]
	var text: String = e["text"]
	var st := int(e["status"])
	var esc_text := text.replace("[", "[lb]")
	if kind == "system":
		system.append_text("[color=#a4adb5]%s[/color]  %s\n" % [time, esc_text])
		return
	if kind == "note":
		notes.append_text("[color=#a4adb5]%s[/color]  [color=#d6a83b]%s[/color]  %s\n" % [time, src, esc_text])
	var col := "#e5e7e9"
	var src_col := "#8fb7d6"
	match kind:
		"alarm":
			col = "#f0c060"
			src_col = "#f0c060"
		"status":
			col = "#a4adb5"
			if text == "":
				esc_text = Data.fms_text(st)
		"text":
			col = "#b9d6a4"
		"note":
			col = "#d6a83b"
	if src == "Leitstelle":
		src_col = "#e5e7e9"
	funk.append_text("[color=#6b737b]%s[/color] %s [color=%s]%-26s[/color] [color=%s]%s[/color]\n" % [time, _status_tag(st), src_col, src.replace("[", "[lb]"), col, esc_text])
	if sound and kind == "funk":
		Audio.play("radio")

func _on_chat(e: Dictionary) -> void:
	chat.append_text("[color=#6b737b]%s[/color]  [color=#8fb7d6]%s:[/color]  %s\n" % [State.time_str(float(e["t"])), String(e["who"]).replace("[", "[lb]"), String(e["text"]).replace("[", "[lb]")])
	if tabs.current_tab != 4:
		tabs.set_tab_title(4, "Chat ●")

func _send() -> void:
	var text := input.text.strip_edges()
	if text == "":
		return
	input.text = ""
	if target.selected == 1 or tabs.current_tab == 4:
		Game.act({"a": "chat", "text": text})
	else:
		Game.act({"a": "msg", "text": text})

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.4:
		return
	_t = 0.0
	if tabs.current_tab == 4:
		tabs.set_tab_title(4, "Chat")
	if _talk_dirty:
		_talk_dirty = false
		talk_tree.clear()
		var root := talk_tree.create_item()
		var n := 0
		for id in State.vehicles:
			var v: Dictionary = State.vehicles[id]
			if v["talk"] == "" and int(v["status"]) != 5:
				continue
			n += 1
			var it := talk_tree.create_item(root)
			it.set_metadata(0, id)
			it.set_text(0, State.dur_str(State.clock - float(v["talk_t"])))
			it.set_text(1, v["callsign"])
			it.set_text(2, State.incidents[v["incident"]]["keyword"] + "  " + State.incidents[v["incident"]]["address"] if State.incidents.has(v["incident"]) else "")
		tabs.set_tab_title(1, "Sprechwünsche (%d)" % n if n > 0 else "Sprechwünsche")

func pending_talks() -> Array:
	var out: Array = []
	for id in State.vehicles:
		if int(State.vehicles[id]["status"]) == 5:
			out.append(id)
	return out

func _ack_selected() -> void:
	var it := talk_tree.get_selected()
	var id := ""
	if it != null:
		id = it.get_metadata(0)
	else:
		var p := pending_talks()
		if p.size() > 0:
			id = p[0]
	if id != "":
		Game.act({"a": "veh_talk", "id": id})

func ack_next() -> void:
	var p := pending_talks()
	if p.size() > 0:
		Game.act({"a": "veh_talk", "id": p[0]})

func _ack_all() -> void:
	for id in pending_talks():
		Game.act({"a": "veh_talk", "id": id})
