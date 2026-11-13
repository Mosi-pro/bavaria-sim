extends VBoxContainer
## Fahrzeuginformation (öffnet sich beim Anklicken eines Fahrzeugs).

const UI = preload("res://src/ui/kit.gd")
const IL = preload("res://src/incidents/incident_logic.gd")

var vid := ""
var info: RichTextLabel
var talk_btn: Button
var oos_btn: Button
var recall_btn: Button
var msg: LineEdit
var _t := 1.0

func setup(id: String) -> void:
	vid = id
	info = UI.rich(false)
	info.scroll_following = false
	add_child(info)
	talk_btn = UI.accent(UI.button("Sprechaufforderung (J)", func(): Game.act({"a": "veh_talk", "id": vid})), Color("#9a5fa3"))
	oos_btn = UI.button("Status 6 setzen", _toggle_oos)
	recall_btn = UI.button("Aus Einsatz abziehen", func(): Game.act({"a": "veh_recall", "id": vid}))
	msg = UI.line_edit("Textnachricht an Fahrzeug …")
	msg.text_submitted.connect(func(_t): _send())
	add_child(UI.hbox([msg, UI.button("Senden", _send)]))
	add_child(UI.hbox([UI.button("Auf Karte zeigen", func(): Game.ui.show_vehicle(vid)), talk_btn, recall_btn, oos_btn, UI.spacer(),
		UI.button("Einsatz öffnen", func():
			var v: Dictionary = State.vehicles.get(vid, {})
			if not v.is_empty() and v["incident"] != "":
				Game.ui.open_dispatch(v["incident"]))]))
	_refresh()

func _send() -> void:
	if msg.text.strip_edges() != "":
		Game.act({"a": "veh_msg", "id": vid, "text": msg.text})
		msg.text = ""

func _toggle_oos() -> void:
	var v: Dictionary = State.vehicles[vid]
	Game.act({"a": "veh_status", "id": vid, "status": 2 if v["state"] == "oos" else 6})

func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		if not State.vehicles.has(vid):
			get_window().queue_free()
			return
		_refresh()

func _refresh() -> void:
	var v: Dictionary = State.vehicles[vid]
	var t: Dictionary = Data.vehicle_types[v["type"]]
	var st: Dictionary = State.stations[v["station"]]
	var s := int(v["status"])
	var pos := State.veh_pos(v)
	var where: String = st["name"] if (v["state"] == "station" or v["state"] == "oos") else World.address_at(pos)["text"]
	var job := "–"
	if v["incident"] != "" and State.incidents.has(v["incident"]):
		var inc: Dictionary = State.incidents[v["incident"]]
		job = "Einsatz %s  ·  %s" % [inc["nr"], inc["keyword"]]
	elif v["state"] == "transport":
		job = "Patiententransport"
	elif v["state"] == "hospital":
		job = "Patientenübergabe im Krankenhaus"
	elif v["state"] == "returning":
		job = "Rückfahrt zur Wache"
	var eta := "–"
	if float(v["eta"]) > State.clock:
		eta = "%s  (in %s)" % [State.time_str(float(v["eta"])), State.dur_str(float(v["eta"]) - State.clock)]
	elif v["state"] == "alarmed":
		eta = "rückt aus in %s" % State.dur_str(float(v["timer"]))
	var caps: Array = []
	for k in t.get("caps", {}):
		caps.append(Data.capabilities.get(k, k))
	var quals: Array = []
	for q in t.get("quals", {}):
		quals.append("%d× %s" % [int(t["quals"][q]), Data.qualifications.get(q, q)])
	var txt := "[b]%s[/b]\n" % v["callsign"]
	txt += "[color=#a4adb5]Fahrzeugtyp[/color]  %s (%s)\n" % [t["name"], t["short"]]
	txt += "[color=#a4adb5]Organisation[/color]  [color=%s]%s[/color]\n" % [UI.hex(Data.org_color(v["org"]).lightened(0.3)), Data.org_name(v["org"])]
	txt += "[color=#a4adb5]Heimatwache[/color]  %s\n" % st["name"]
	txt += "[color=#a4adb5]Standort[/color]  %s\n" % where
	txt += "[color=#a4adb5]Status[/color]  [bgcolor=%s][color=#ffffff] %d [/color][/bgcolor]  %s\n" % [UI.hex(Data.fms_color(s).darkened(0.15)), s, Data.fms_text(s)]
	txt += "[color=#a4adb5]Besatzung[/color]  %s   [color=#6b737b](Regel %d / Mindest %d; erforderlich: %s)[/color]\n" % [Sim.Personnel.crew_text(v), int(t["crew"]), int(t["min"]), ", ".join(quals) if quals.size() > 0 else "–"]
	txt += "[color=#a4adb5]Aktueller Auftrag[/color]  %s\n" % job
	txt += "[color=#a4adb5]Zielort[/color]  %s\n" % (v["dest_name"] if v["dest_name"] != "" else "–")
	txt += "[color=#a4adb5]Voraussichtliche Ankunft[/color]  %s\n" % eta
	txt += "[color=#a4adb5]Höchstgeschwindigkeit[/color]  %d km/h    [color=#a4adb5]Laufleistung Schicht[/color]  %.1f km    [color=#a4adb5]Einsätze[/color]  %d\n" % [int(t["speed"]), float(v["km"]), int(v["runs"])]
	txt += "[color=#a4adb5]Einsatzmöglichkeiten[/color]  %s\n" % ", ".join(caps)
	txt += "[color=#a4adb5]Ausrüstung[/color]  %s\n" % ", ".join(t.get("equip", []))
	if v["talk"] != "":
		txt += "\n[color=#c97bd1][b]SPRECHWUNSCH – Sprechaufforderung geben.[/b][/color]\n"
	info.text = txt
	talk_btn.visible = v["talk"] != ""
	recall_btn.disabled = v["incident"] == ""
	oos_btn.text = "Wieder in Dienst (Status 2)" if v["state"] == "oos" else "Außer Dienst (Status 6)"
	oos_btn.disabled = not (v["state"] == "station" or v["state"] == "oos")
