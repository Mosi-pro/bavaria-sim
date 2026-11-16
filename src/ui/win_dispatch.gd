extends VBoxContainer
## Einsatzakte mit Dispositionsfenster: Vorschlag, Fahrzeugauswahl, Alarmierung,
## zugeordnete Kräfte, Notizen, Abschluss.

const UI = preload("res://src/ui/kit.gd")
const IL = preload("res://src/incidents/incident_logic.gd")
const VL = preload("res://src/vehicles/vehicle_logic.gd")
const Advisor = preload("res://src/dispatch/advisor.gd")
const FormScript = preload("res://src/ui/win_incident_form.gd")

var inc_id := ""
var info: RichTextLabel
var progress: ProgressBar
var disp_tree: Tree
var force_tree: Tree
var notes: RichTextLabel
var note_edit: LineEdit
var sugg_label: Label
var org_filter: OptionButton
var only_free: CheckBox
var type_filter: OptionButton
var _types: Array = []
var alarm_btn: Button
var close_btn: Button
var tabs: TabContainer
var _t := 1.0
var _checked := {}
var _suggested: Array = []
var _modules := {}   # Fahrzeug-ID -> gewählter Rollcontainer (GW-L)
var _sugg_sig := ""
var _orgs: Array = []
var _details := ""

func setup(id: String) -> void:
	inc_id = id
	Game.act({"a": "inc_open", "id": id})
	info = UI.rich(false)
	info.scroll_following = false
	info.custom_minimum_size.y = 130
	info.size_flags_vertical = Control.SIZE_FILL
	add_child(info)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 8
	progress.show_percentage = false
	progress.max_value = 1.0
	add_child(progress)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	# --- Disposition
	_orgs = [""]
	var names: Array = ["Alle Organisationen"]
	for o in Data.organisations:
		_orgs.append(o)
		names.append(Data.organisations[o]["name"])
	org_filter = UI.option(names, 0)
	org_filter.item_selected.connect(func(_i): _fill_disposition(false))
	only_free = CheckBox.new()
	only_free.text = "Nur Vorschlag zeigen"
	only_free.tooltip_text = "Ein: nur die vom System vorgeschlagenen Fahrzeuge.  Aus: alle einsatzbereiten Fahrzeuge (Vorschlag oben, blau markiert)."
	only_free.button_pressed = false
	only_free.focus_mode = Control.FOCUS_NONE
	only_free.toggled.connect(func(_on): _fill_disposition(false))
	_types = [""]
	var tnames: Array = ["Alle Fahrzeugtypen"]
	var tlist: Array = Data.vehicle_types.keys()
	tlist.sort_custom(func(a, b): return [Data.vehicle_types[a]["org"], Data.vehicle_types[a]["short"]] < [Data.vehicle_types[b]["org"], Data.vehicle_types[b]["short"]])
	for tid in tlist:
		_types.append(tid)
		tnames.append("%s – %s" % [Data.vehicle_types[tid]["short"], Data.vehicle_types[tid]["name"]])
	type_filter = UI.option(tnames, 0)
	type_filter.custom_minimum_size.x = 200
	type_filter.tooltip_text = "Nur einen bestimmten Fahrzeugtyp anzeigen, z. B. um gezielt eine Drehleiter nachzualarmieren"
	type_filter.item_selected.connect(func(_i): _fill_disposition(false))
	sugg_label = UI.label("", UI.TEXT2)
	sugg_label.clip_text = true
	sugg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disp_tree = UI.tree([{"title": "", "width": 26}, {"title": "ETA", "width": 50}, {"title": "Funkrufname", "width": 150}, {"title": "Typ", "width": 70}, {"title": "Wache"}, {"title": "km", "width": 44}, {"title": "Status", "width": 120}, {"title": "Rollcontainer", "width": 170}])
	disp_tree.item_edited.connect(_on_check)
	disp_tree.item_activated.connect(func():
		var it := disp_tree.get_selected()
		if it != null and it.is_editable(0):
			it.set_checked(0, not it.is_checked(0))
			_checked[it.get_metadata(0)] = it.is_checked(0)
			_update_alarm_btn())
	alarm_btn = UI.accent(UI.button("ALARMIEREN", _alarm), UI.RED)
	alarm_btn.custom_minimum_size.x = 170
	var dv := UI.vbox([
		sugg_label,
		UI.hbox([org_filter, type_filter, only_free, UI.spacer(), UI.button("Vorschlag neu berechnen", func(): _fill_disposition(true), "Vorschlag nach Stichwort bzw. aktuellem Bedarf neu berechnen und anhaken"), UI.button("Alle Haken entfernen", func():
			_checked = {}
			_fill_disposition(false))]),
		disp_tree,
		UI.hbox([UI.label("Haken = wird alarmiert. ETA = voraussichtliche Ankunft.", UI.TEXT2), UI.spacer(), alarm_btn]),
	])
	dv.name = "Fahrzeuge alarmieren"
	tabs.add_child(dv)
	# --- Kräfte
	force_tree = UI.tree([{"title": "St", "width": 24}, {"title": "Funkrufname", "width": 180}, {"title": "Typ", "width": 70}, {"title": "Zustand"}, {"title": "Besatzung", "width": 150}])
	var fv := UI.vbox([force_tree, UI.hbox([
		UI.button("Fahrzeug abziehen", _recall, "Einsatzabbruch für das markierte Fahrzeug"),
		UI.button("Auf Karte zeigen", func():
			var it := force_tree.get_selected()
			if it != null and State.vehicles.has(it.get_metadata(0)):
				Game.ui.show_vehicle(it.get_metadata(0))),
		UI.button("Fahrzeuginformation", func():
			var it := force_tree.get_selected()
			if it != null:
				Game.ui.open_vehicle(it.get_metadata(0))),
		UI.spacer()])])
	fv.name = "Am Einsatz"
	tabs.add_child(fv)
	# --- Notizen
	notes = UI.rich(false)
	note_edit = UI.line_edit("Einsatznotiz eingeben …")
	note_edit.text_submitted.connect(func(_t): _add_note())
	var nv := UI.vbox([notes, UI.hbox([note_edit, UI.button("Notiz speichern", _add_note)])])
	nv.name = "Notizen"
	tabs.add_child(nv)
	tabs.set_tab_title(2, "Verlauf und Notizen")
	close_btn = UI.button("Einsatz abschließen", _close_incident)
	add_child(UI.hbox([
		UI.button("Auf Karte zeigen", func():
			if State.incidents.has(inc_id):
				Game.ui.show_incident(inc_id)),
		UI.button("Einsatzdaten bearbeiten …", func():
			var f := VBoxContainer.new()
			f.set_script(FormScript)
			f.setup(inc_id)
			UI.window(Game.ui, "Einsatzdaten bearbeiten", Vector2i(560, 300), f, "form_" + inc_id)),
		UI.spacer(), close_btn, UI.button("Schließen", func(): get_window().queue_free())]))
	_fill_disposition(not Data.modes.get("modes", {}).get(State.meta["mode"], {}).get("no_preselect", false))
	_refresh()

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	if not State.incidents.has(inc_id):
		get_window().queue_free()
		return
	_refresh()

func _refresh() -> void:
	var inc: Dictionary = State.incidents[inc_id]
	var kd: Dictionary = Data.keywords.get(inc["keyword"], {})
	var t := func(x): return State.time_str(float(x)) if float(x) >= 0.0 else "–"
	var txt := "[font_size=15][b][color=#%s]%s[/color]  %s[/b][/font_size]    [color=#6b737b]Einsatz %s · Priorität %d[/color]\n" % [Data.keyword_color(inc["keyword"]).to_html(false), inc["keyword"], kd.get("name", ""), inc["nr"], int(inc["prio"])]
	txt += "[color=#a4adb5]Ort:[/color]  %s%s\n" % [inc["address"], "   [color=#d6a83b](ungenau – Kräfte müssen suchen)[/color]" if float(inc["radius"]) > 0.0 else ""]
	txt += "[color=#a4adb5]Stand:[/color]  [b]%s[/b]\n" % _plain_status(inc)
	if inc["revealed"]:
		txt += "[color=#a4adb5]Lage:[/color]  %s\n" % String(inc["lage"]).replace("[", "[lb]").replace("\n", "  ")
		var need: Dictionary = inc.get("need", {})
		var have: Dictionary = inc.get("have", {})
		var assigned := IL.caps_assigned(inc_id)
		var parts: Array = []
		for k in need:
			var n := int(need[k])
			var h := int(have.get(k, 0))
			var a := int(assigned.get(k, 0))
			if k == "ktw":
				h += int(have.get("rtw", 0))
				a += int(assigned.get("rtw", 0))
			var mark := "[color=#4c9868]✓[/color]" if h >= n else ("[color=#d6a83b]…[/color]" if a >= n else "[color=#c83d3d]✗[/color]")
			parts.append("%s %d× %s" % [mark, n, Data.capabilities.get(k, k)])
		txt += "[color=#a4adb5]Bedarf:[/color]  %s\n" % ("   ".join(parts) if parts.size() > 0 else "kein weiterer Bedarf")
		if parts.size() > 0:
			txt += "[color=#6b737b]✓ vor Ort   … unterwegs   ✗ fehlt noch – nachalarmieren[/color]\n"
		var pat: Dictionary = inc.get("pat", {})
		if int(pat.get("total", 0)) > 0:
			txt += "[color=#a4adb5]Patienten:[/color]  %d gesamt · %d warten · %d in Behandlung · %d transportiert%s\n" % [int(pat["total"]), int(pat.get("wait", 0)), int(pat.get("care", 0)), int(pat.get("transport", 0)) + int(pat.get("ambulant", 0)), ("  ·  [color=#c83d3d]%d verstorben[/color]" % int(pat["dead"])) if int(pat.get("dead", 0)) > 0 else ""]
	if inc["done"]:
		txt += "[color=#4c9868][b]Bewertung: %d %%[/b][/color]\n" % int(inc["score"])
	if inc["dup_of"] != "":
		txt += "[color=#d6a83b]Hinweis: wahrscheinlich derselbe Notfall wie Einsatz %s.[/color]\n" % inc["dup_of"]
	var meld: Array = []
	for pair in [["object", "Objekt"], ["persons", "Betroffene"], ["danger", "Gefahr"], ["info", "Bemerkung"]]:
		if String(inc[pair[0]]) != "":
			meld.append("%s: %s" % [pair[1], String(inc[pair[0]]).replace("[", "[lb]")])
	_details = "[b]Einsatzdaten[/b]\n[color=#a4adb5]Meldung[/color]  %s\n[color=#a4adb5]Anrufer[/color]  %s    [color=#a4adb5]angelegt von[/color] %s\n[color=#a4adb5]Zeiten[/color]  Notruf %s · Einsatz %s · Alarm %s · Eintreffen %s · Ende %s\n\n[b]Verlauf[/b]\n" % ["  ·  ".join(meld) if meld.size() > 0 else "–", inc["caller"] if inc["caller"] != "" else "–", inc["by"], t.call(inc["t_call"]), t.call(inc["t_created"]), t.call(inc["t_alarm"]), t.call(inc["t_arrival"]), t.call(inc["t_done"])]
	info.text = txt
	progress.value = float(inc.get("progress", 0.0))
	progress.visible = inc["revealed"]
	close_btn.text = "Einsatz abschließen" if inc["done"] else "Einsatz stornieren"
	alarm_btn.disabled = inc["done"]
	_fill_forces()
	var ntext := _details
	for n in inc["notes"]:
		ntext += "[color=#6b737b]%s[/color]  [color=#d6a83b]%s:[/color]  %s\n" % [State.time_str(float(n["t"])), n["who"], String(n["text"]).replace("[", "[lb]")]
	for e in State.radio:
		if e["inc"] == inc_id and e["kind"] != "note":
			ntext += "[color=#6b737b]%s[/color]  [color=#8fb7d6]%s:[/color]  %s\n" % [State.time_str(float(e["t"])), e["src"], (String(e["text"]) if e["text"] != "" else Data.fms_text(int(e["status"]))).replace("[", "[lb]")]
	if notes.get_meta("sig", "") != str(ntext.length()):
		notes.set_meta("sig", str(ntext.length()))
		notes.text = ntext
	# Vorschlag bei geänderter Lage automatisch aktualisieren (ohne Auswahl zu verändern)
	var sig := "%s|%s|%d" % [inc["keyword"], str(inc.get("need", {})), State.incident_vehicles(inc_id).size()]
	if sig != _sugg_sig:
		_fill_disposition(false)

func _plain_status(inc: Dictionary) -> String:
	match inc["status"]:
		"neu", "in_bearbeitung":
			return "Noch keine Fahrzeuge alarmiert – unten auswählen und ALARMIEREN."
		"alarmiert":
			return "Fahrzeuge alarmiert, sie rücken gerade aus."
		"anfahrt":
			var eta := INF
			for vid in State.incident_vehicles(inc_id):
				var v: Dictionary = State.vehicles[vid]
				if v["state"] == "enroute":
					eta = min(eta, float(v["eta"]) - State.clock)
			return "Fahrzeuge auf der Anfahrt – erstes Eintreffen in ca. %s." % State.dur_str(eta) if eta < INF else "Fahrzeuge auf der Anfahrt."
		"vor_ort":
			return "Erste Kräfte vor Ort, sie erkunden die Lage."
		"laeuft":
			return "Einsatz läuft – %d %% erledigt." % int(float(inc.get("progress", 0.0)) * 100.0)
		"rueckfahrt":
			return "Einsatz beendet. Fahrzeuge fahren zurück – Einsatz jetzt abschließen."
	return String(inc["status"])

func _fill_forces() -> void:
	var sel := ""
	if force_tree.get_selected() != null:
		sel = force_tree.get_selected().get_metadata(0)
	force_tree.clear()
	var root := force_tree.create_item()
	var ids := State.incident_vehicles(inc_id)
	for vid in ids:
		var v: Dictionary = State.vehicles[vid]
		var it := force_tree.create_item(root)
		it.set_metadata(0, vid)
		var st := int(v["status"])
		it.set_text(0, str(st))
		it.set_custom_bg_color(0, Color(Data.fms_color(st), 0.75))
		it.set_text(1, v["callsign"])
		it.set_text(2, Data.vehicle_types[v["type"]]["short"])
		if VL.has_modules(v):
			it.set_tooltip_text(2, "Rollcontainer: " + VL.module_name(v))
		var z := ""
		match v["state"]:
			"alarmed": z = "alarmiert, rückt aus in %s" % State.dur_str(float(v["timer"]))
			"enroute": z = "Anfahrt, Ankunft in ca. %s" % State.dur_str(float(v["eta"]) - State.clock)
			"onscene": z = "an der Einsatzstelle" + ("  –  SPRECHWUNSCH" if v["talk"] != "" else "")
			_: z = v["state"]
		if VL.has_modules(v):
			z += "  ·  Rollcontainer: " + VL.module_name(v)
		it.set_text(3, z)
		it.set_text(4, Sim.Personnel.crew_text(v))
		if vid == sel:
			it.select(1)
	tabs.set_tab_title(1, "Am Einsatz (%d)" % ids.size())

func _fill_disposition(apply_suggestion: bool) -> void:
	if not State.incidents.has(inc_id):
		return
	var inc: Dictionary = State.incidents[inc_id]
	_sugg_sig = "%s|%s|%d" % [inc["keyword"], str(inc.get("need", {})), State.incident_vehicles(inc_id).size()]
	var res := Advisor.suggest(inc)
	_suggested = res["suggested"]
	if apply_suggestion:
		_checked = {}
		_modules = {}
		for vid in _suggested:
			_checked[vid] = true
	for vid in res.get("modules", {}):
		if apply_suggestion or not _modules.has(vid):
			_modules[vid] = res["modules"][vid]
	var org: String = _orgs[org_filter.selected]
	var vt: String = _types[type_filter.selected] if type_filter != null else ""
	disp_tree.clear()
	var root := disp_tree.create_item()
	var shown := 0
	var rows: Array = res["rows"].duplicate()
	# vorgeschlagene und bereits angehakte Fahrzeuge zuerst, dann nach Ankunftszeit
	rows.sort_custom(func(a, b):
		var pa: int = 0 if (_suggested.has(a["id"]) or _checked.get(a["id"], false)) else 1
		var pb: int = 0 if (_suggested.has(b["id"]) or _checked.get(b["id"], false)) else 1
		if pa != pb:
			return pa < pb
		return a["eta"] < b["eta"])
	for r in rows:
		var v: Dictionary = State.vehicles[r["id"]]
		if v["incident"] == inc_id:
			continue
		if org != "" and v["org"] != org:
			continue
		if vt != "" and v["type"] != vt:
			continue
		var free: bool = r["reason"] == ""
		if not free:
			continue
		if only_free.button_pressed and not _suggested.has(r["id"]) and not _checked.get(r["id"], false):
			continue
		shown += 1
		if shown > 140:
			break
		var it := disp_tree.create_item(root)
		it.set_metadata(0, r["id"])
		it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		it.set_editable(0, free)
		it.set_checked(0, free and _checked.get(r["id"], false))
		it.set_text(1, State.dur_str(float(r["eta"])) if r["eta"] < INF else "–")
		it.set_text(2, v["callsign"])
		it.set_custom_color(2, Data.org_color(v["org"]).lightened(0.35) if free else UI.TEXT2)
		it.set_text(3, Data.vehicle_types[v["type"]]["short"])
		it.set_tooltip_text(3, "%s\nFähigkeiten: %s" % [Data.vehicle_types[v["type"]]["name"], IL.need_text(r["caps"])])
		it.set_text(4, State.stations[v["station"]]["name"])
		it.set_text(5, "%.1f" % (float(r["dist"]) / 1000.0))
		it.set_text(6, ("%d %s" % [int(v["status"]), "frei" if int(v["status"]) == 1 else "auf Wache"]) if free else r["reason"])
		if not free:
			it.set_custom_color(6, UI.TEXT2)
		if VL.has_modules(v):
			_module_cell(it, v)
		if _suggested.has(r["id"]):
			for col in [1, 2, 3]:
				it.set_custom_bg_color(col, Color(0.29, 0.5, 0.66, 0.28))
			it.set_tooltip_text(1, "Vom System vorgeschlagen")
	var st := "Vorschlag: %d Fahrzeug(e) (blau, bereits angehakt). Du kannst jedes andere freie Fahrzeug zusätzlich anhaken oder Haken entfernen." % _suggested.size()
	if _suggested.is_empty():
		st = "Kein Vorschlag nötig – du kannst trotzdem jedes freie Fahrzeug selbst anhaken und alarmieren."
	if not res["missing"].is_empty():
		st += "   Derzeit nicht verfügbar: " + IL.need_text(res["missing"])
	sugg_label.text = st
	sugg_label.add_theme_color_override("font_color", UI.YELLOW if not res["missing"].is_empty() else UI.TEXT2)
	_update_alarm_btn()

## Rollcontainer-Auswahl (Dropdown in der Tabelle) für Fahrzeuge mit Wechselbeladung
func _module_cell(it: TreeItem, v: Dictionary) -> void:
	var mods: Dictionary = Data.vehicle_types[v["type"]]["modules"]
	var keys: Array = mods.keys()
	var cur: String = String(_modules.get(v["id"], VL.module_of(v)))
	var tip := "Rollcontainer wählen – Umladen auf der Wache dauert %s.\n" % State.dur_str(float(Data.vehicle_types[v["type"]].get("module_change", 120)))
	for m in keys:
		tip += "\n%s: %s" % [mods[m]["name"], mods[m].get("equip", "")]
	if VL.can_change_module(v):
		var names: Array = []
		for m in keys:
			names.append(String(mods[m]["name"]) + ("" if m != VL.module_of(v) else " ✓"))
		it.set_cell_mode(7, TreeItem.CELL_MODE_RANGE)
		it.set_text(7, ",".join(names))
		it.set_range(7, max(0, keys.find(cur)))
		it.set_editable(7, true)
		it.set_tooltip_text(7, tip + "\n\n✓ = derzeit geladen")
		if cur != VL.module_of(v):
			it.set_custom_color(7, UI.YELLOW)
	else:
		it.set_text(7, VL.module_name(v))
		it.set_custom_color(7, UI.TEXT2)
		it.set_tooltip_text(7, "Umladen nur auf der Wache möglich.\n" + tip)

func _on_check() -> void:
	var it := disp_tree.get_edited()
	if it == null:
		return
	var vid: String = it.get_metadata(0)
	if disp_tree.get_edited_column() == 7 and State.vehicles.has(vid):
		var keys: Array = Data.vehicle_types[State.vehicles[vid]["type"]].get("modules", {}).keys()
		var i := int(it.get_range(7))
		if i >= 0 and i < keys.size():
			_modules[vid] = keys[i]
			it.set_custom_color(7, UI.YELLOW if keys[i] != VL.module_of(State.vehicles[vid]) else UI.TEXT)
		return
	_checked[vid] = it.is_checked(0)
	_update_alarm_btn()

func _selected_ids() -> Array:
	var out: Array = []
	for vid in _checked:
		if _checked[vid] and State.vehicles.has(vid) and VL.block_reason(State.vehicles[vid]) == "":
			out.append(vid)
	return out

func _update_alarm_btn() -> void:
	var n := _selected_ids().size()
	alarm_btn.text = "ALARMIEREN (%d)" % n if n > 0 else "ALARMIEREN"

func _alarm() -> void:
	var ids := _selected_ids()
	if ids.is_empty():
		UI.message(self, "Alarmierung", "Es sind keine Einsatzmittel ausgewählt.")
		return
	var mods := {}
	for vid in ids:
		if _modules.has(vid):
			mods[vid] = _modules[vid]
	Game.act({"a": "inc_alarm", "id": inc_id, "vehicles": ids, "modules": mods}, func(res):
		_checked = {}
		_modules = {}
		if not is_inside_tree():
			return
		_fill_disposition(false)
		tabs.current_tab = 1
		if res.get("failed", []).size() > 0:
			UI.message(self, "Alarmierung", "Nicht alarmiert:\n" + "\n".join(res["failed"])))

func _recall() -> void:
	var it := force_tree.get_selected()
	if it == null:
		return
	Game.act({"a": "veh_recall", "id": it.get_metadata(0)})

func _add_note() -> void:
	var text := note_edit.text.strip_edges()
	if text == "":
		return
	note_edit.text = ""
	Game.act({"a": "inc_note", "id": inc_id, "text": text})

func _close_incident() -> void:
	var inc: Dictionary = State.incidents[inc_id]
	var q := "Einsatz %s abschließen und archivieren?" % inc["nr"]
	if not inc["done"]:
		q = "Der Einsatz %s ist noch nicht beendet. Stornieren? (Nur möglich, wenn keine Kräfte mehr zugeteilt sind.)" % inc["nr"]
	UI.confirm(self, "Einsatz abschließen", q, func(): Game.act({"a": "inc_close", "id": inc_id}))
