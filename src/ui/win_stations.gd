extends HBoxContainer
## Wachen- und Standortverwaltung: Standorte bearbeiten/neu einrichten, Fahrzeuge
## beschaffen, verlegen und außer Dienst nehmen, Regionen übernehmen (Karriere).

const UI = preload("res://src/ui/kit.gd")
const StationLogic = preload("res://src/stations/station_logic.gd")
const Personnel = preload("res://src/personnel/personnel.gd")
const KINDS := {"fw": [["bf", "Berufsfeuerwehr-Wache"], ["ff", "Freiwillige Feuerwehr"]], "rd": [["rw", "Rettungswache"]], "pol": [["pol", "Polizeidienststelle"]], "thw": [["thw", "THW-Ortsverband"]], "wr": [["wr", "Wasserrettungsstation"]], "kats": [["kats", "Katastrophenschutz-Standort"]]}

var tree: Tree
var org_opt: OptionButton
var detail: VBoxContainer
var budget: Label
var sel := ""
var _orgs: Array = [""]
var _dirty := true
var _t := 0.0

func setup(station_id := "") -> void:
	sel = station_id
	add_theme_constant_override("separation", 8)
	var names: Array = ["Alle Organisationen"]
	for o in Data.organisations:
		_orgs.append(o)
		names.append(Data.organisations[o]["name"])
	org_opt = UI.option(names, 0)
	org_opt.item_selected.connect(func(_i): _dirty = true)
	tree = UI.tree([{"title": "Standort"}, {"title": "Fzg.", "width": 50}])
	tree.item_selected.connect(func():
		var it := tree.get_selected()
		if it != null and it.get_metadata(0) != sel:
			sel = it.get_metadata(0)
			_fill_detail())
	budget = UI.label("", UI.TEXT2)
	var left := UI.vbox([org_opt, tree, budget, UI.hbox([UI.button("Neuer Standort …", _new_station), UI.button("Region übernehmen …", _zones)])])
	left.custom_minimum_size.x = 330
	add_child(left)
	add_child(VSeparator.new())
	detail = UI.vbox([])
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(detail)
	for s in [State.station_changed, State.station_removed, State.vehicle_changed, State.vehicle_removed]:
		s.connect(_mark)
	State.meta_changed.connect(_mark.bind(""))
	_fill_list()
	_fill_detail()

func _mark(_id) -> void:
	_dirty = true

func _process(delta: float) -> void:
	_t += delta
	if _dirty and _t > 0.4:
		_t = 0.0
		_dirty = false
		_fill_list()
		_fill_detail()

func _fill_list() -> void:
	tree.clear()
	var root := tree.create_item()
	var org: String = _orgs[org_opt.selected]
	var ids: Array = State.stations.keys()
	ids.sort_custom(func(a, b): return [State.stations[a]["org"], int(State.stations[a]["nr"])] < [State.stations[b]["org"], int(State.stations[b]["nr"])])
	for id in ids:
		var st: Dictionary = State.stations[id]
		if org != "" and st["org"] != org:
			continue
		var it := tree.create_item(root)
		it.set_metadata(0, id)
		it.set_text(0, st["name"])
		it.set_custom_color(0, Data.org_color(st["org"]).lightened(0.35))
		it.set_text(1, "%d/%d" % [State.station_vehicles(id).size(), int(st["slots"])])
		if id == sel:
			it.select(0)
	if State.meta["mode"] == "karriere":
		budget.text = "Budget: %s   ·   Stufe %d" % [UI.money(int(State.meta["budget"])), int(State.meta["level"])]
	else:
		budget.text = "Freier Modus: Beschaffungen ohne Budgetbegrenzung."

func _fill_detail() -> void:
	for c in detail.get_children():
		c.queue_free()
	if sel == "" or not State.stations.has(sel):
		detail.add_child(UI.label("Standort in der Liste auswählen.", UI.TEXT2))
		return
	var st: Dictionary = State.stations[sel]
	var career: Dictionary = Data.modes.get("career", {})
	var name := UI.line_edit("", st["name"])
	var addr := UI.line_edit("", st["address"])
	var slots := SpinBox.new()
	slots.min_value = State.station_vehicles(sel).size()
	slots.max_value = 14
	slots.value = int(st["slots"])
	var save := UI.button("Standortdaten speichern", func(): Game.act({"a": "st_edit", "id": sel, "name": name.text, "address": addr.text, "slots": int(slots.value)}))
	detail.add_child(UI.form([
		["Name", name], ["Adresse", addr],
		["Organisation", UI.label("%s  ·  %s  ·  Wachnummer %d" % [Data.org_name(st["org"]), st["kind"].to_upper(), int(st["nr"])])],
		["Stellplätze", UI.hbox([slots, UI.label("(zusätzlicher Stellplatz: %s)" % UI.money(int(career.get("slot_cost", 0))) if State.meta["mode"] == "karriere" else "", UI.TEXT2)])],
	]))
	detail.add_child(UI.hbox([save, UI.button("Auf Karte zeigen", func(): Game.ui.map.focus_on(Vector2(st["x"], st["y"]), 0.6)), UI.spacer(),
		UI.button("Standort auflösen", func(): UI.confirm(self, "Standort auflösen", "Standort »%s« wirklich auflösen? (Nur ohne Fahrzeuge möglich.)" % st["name"], func(): Game.act({"a": "st_delete", "id": sel})))]))
	detail.add_child(UI.caption("Personal (Wachstärke)"))
	var ov := Personnel.overview(sel)
	var parts: Array = []
	for q in ov:
		parts.append("%s: %d Soll / %d im Dienst / %d verfügbar" % [Data.qualifications.get(q, q), ov[q][0], ov[q][1], ov[q][2]])
	var pl := UI.label("\n".join(parts) if parts.size() > 0 else "Kein Personal zugeordnet.", UI.TEXT)
	detail.add_child(pl)
	detail.add_child(UI.caption("Fahrzeugbestand"))
	var vt := UI.tree([{"title": "St", "width": 24}, {"title": "Funkrufname"}, {"title": "Typ", "width": 80}, {"title": "Besatzung", "width": 70}])
	var vroot := vt.create_item()
	for vid in State.station_vehicles(sel):
		var v: Dictionary = State.vehicles[vid]
		var it := vt.create_item(vroot)
		it.set_metadata(0, vid)
		it.set_text(0, str(int(v["status"])))
		it.set_custom_bg_color(0, Color(Data.fms_color(int(v["status"])), 0.75))
		it.set_text(1, v["callsign"])
		it.set_text(2, Data.vehicle_types[v["type"]]["short"])
		it.set_text(3, "%d/%d" % [int(Data.vehicle_types[v["type"]]["min"]), int(Data.vehicle_types[v["type"]]["crew"])])
	vt.custom_minimum_size.y = 150
	detail.add_child(vt)
	var targets: Array = []
	var tnames: Array = []
	for id in State.stations:
		if id != sel and State.stations[id]["org"] == st["org"] and StationLogic.free_slots(id) > 0:
			targets.append(id)
			tnames.append(State.stations[id]["name"])
	var topt := UI.option(tnames if tnames.size() > 0 else ["(kein Standort mit freiem Stellplatz)"], 0)
	topt.clip_text = true
	topt.custom_minimum_size.x = 220
	var get_vid := func():
		var it := vt.get_selected()
		return "" if it == null else it.get_metadata(0)
	detail.add_child(UI.hbox([
		UI.label("Markiertes Fahrzeug:", UI.TEXT2),
		UI.button("verlegen nach", func():
			var vid: String = get_vid.call()
			if vid != "" and targets.size() > 0:
				Game.act({"a": "veh_move", "id": vid, "station": targets[topt.selected]})), topt,
		UI.button("Status 6 / 2", func():
			var vid: String = get_vid.call()
			if vid != "":
				Game.act({"a": "veh_status", "id": vid, "status": 2 if State.vehicles[vid]["state"] == "oos" else 6})),
		UI.button("aussondern", func():
			var vid: String = get_vid.call()
			if vid != "":
				UI.confirm(self, "Fahrzeug aussondern", "%s dauerhaft aussondern%s?" % [State.vehicles[vid]["callsign"], " (Erlös 50 % des Neupreises)" if State.meta["mode"] == "karriere" else ""], func(): Game.act({"a": "veh_sell", "id": vid}))),
		UI.button("Info", func():
			var vid: String = get_vid.call()
			if vid != "":
				Game.ui.open_vehicle(vid)),
	]))
	var types: Array = []
	var type_names: Array = []
	for tid in Data.vehicle_types:
		var t: Dictionary = Data.vehicle_types[tid]
		if t["org"] == st["org"]:
			types.append(tid)
			type_names.append("%s – %s  (%s)" % [t["short"], t["name"], UI.money(int(t.get("price", 0)))])
	var bopt := UI.option(type_names, 0)
	bopt.clip_text = true
	bopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(UI.hbox([UI.label("Neues Fahrzeug:", UI.TEXT2), bopt, UI.button("Beschaffen", func(): Game.act({"a": "veh_buy", "station": sel, "type": types[bopt.selected]}))]))

func _new_station() -> void:
	var orgs: Array = []
	var onames: Array = []
	for o in State.meta["orgs"]:
		orgs.append(o)
		onames.append(Data.org_name(o))
	var name := UI.line_edit("z. B. Feuerwache 11 – Südwest")
	var oopt := UI.option(onames, 0)
	var kopt := UI.option([], 0)
	var fill_k := func(i):
		kopt.clear()
		for k in KINDS.get(orgs[i], []):
			kopt.add_item(k[1])
	oopt.item_selected.connect(fill_k)
	fill_k.call(0)
	var slots := SpinBox.new()
	slots.min_value = 1
	slots.max_value = 12
	slots.value = 4
	var pos_label := UI.label("(noch nicht gewählt)", UI.TEXT2)
	var pos := [Vector2.ZERO]
	var cost := int(Data.modes.get("career", {}).get("station_cost", 0)) if State.meta["mode"] == "karriere" else 0
	var box := UI.vbox([])
	var pick := UI.button("Position aus Karte wählen …", func(): Game.ui.map.set_tool("pick", "Position des neuen Standorts auf der Karte anklicken", func(p):
		pos[0] = p
		pos_label.text = World.address_at(p)["text"]))
	box.add_child(UI.form([["Name", name], ["Organisation", oopt], ["Art", kopt], ["Stellplätze", slots], ["Position", UI.hbox([pick, pos_label])]]))
	box.add_child(UI.label("Kosten: %s" % (UI.money(cost) if cost > 0 else "keine (freier Modus)"), UI.TEXT2))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sp)
	box.add_child(UI.hbox([UI.spacer(), UI.accent(UI.button("Standort einrichten", func():
		if pos[0] == Vector2.ZERO:
			UI.message(self, "Neuer Standort", "Bitte zuerst die Position auf der Karte wählen.")
			return
		var org: String = orgs[oopt.selected]
		Game.act({"a": "st_new", "name": name.text, "org": org, "kind": KINDS[org][kopt.selected][0], "x": pos[0].x, "y": pos[0].y, "slots": int(slots.value)}, func(res):
			if res.get("ok", false):
				sel = res["id"]
				_dirty = true
				box.get_window().queue_free())), UI.BLUE), UI.button("Abbrechen", func(): box.get_window().queue_free())]))
	UI.window(Game.ui, "Neuen Standort einrichten", Vector2i(560, 280), box, "new_station")

func _zones() -> void:
	if State.meta["mode"] != "karriere":
		UI.message(self, "Regionen", "Im aktuellen Spielmodus ist bereits das gesamte Stadtgebiet Bavaria zugeordnet. Die Übernahme weiterer Regionen ist Teil des Karrieremodus.")
		return
	var career: Dictionary = Data.modes.get("career", {})
	var box := UI.vbox([UI.label("Zuständigkeitsbereich der Leitstelle erweitern. Mit jeder Region werden die dortigen Wachen übernommen – und das Einsatzaufkommen steigt.", UI.TEXT2)])
	box.get_child(0).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for z in range(1, 6):
		var have: bool = State.meta["zones"].has(z) or State.meta["zones"].has(float(z))
		var dn: Array = []
		for d in World.districts:
			if int(d.get("zone", 5)) == z:
				dn.append(d["name"])
		var cost := int(career.get("zone_cost", {}).get(str(z), 0))
		var b := UI.button("übernommen" if have else "Übernehmen (%s)" % UI.money(cost), func():
			Game.act({"a": "zone_unlock", "zone": z}, func(res):
				if res.get("ok", false):
					box.get_window().queue_free()))
		b.disabled = have
		var l := UI.label("%s: %s" % [career.get("zone_names", {}).get(str(z), "Region %d" % z), ", ".join(dn)])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(UI.hbox([l, b]))
	UI.window(Game.ui, "Regionen übernehmen", Vector2i(620, 330), box, "zones")
