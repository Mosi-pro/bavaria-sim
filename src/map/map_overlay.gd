extends Control
## Kartenüberlagerung in Bildschirmkoordinaten: Beschriftungen, Wachen, Kliniken,
## Einsatzorte, Notrufortung, Verkehrslage, Routen und Fahrzeuge.

const UI = preload("res://src/ui/kit.gd")

var view: Control
var _labels: Array = []
var _shields: Array = []
var _refs := {}
var _font: Font
var _mono: Font

const ORG_LETTER := {"fw": "F", "rd": "R", "pol": "P", "thw": "T", "wr": "W", "kats": "K"}
const POI_COLOR := {"industrie": Color("#8d7fa8"), "einkauf": Color("#b58f5a"), "schule": Color("#7f9bb0"), "pflege": Color("#b07f93"), "leitstelle": Color("#e5e7e9")}

func _ready() -> void:
	_font = UI.font()
	_mono = UI.mono()
	for art in World.cfg.get("arterials", []):
		if art.has("ref"):
			_refs[art["name"]] = art["ref"]

func camera_changed() -> void:
	_labels = []
	_shields = []
	if view.zoom >= 0.45 and view.layers.get("labels", true):
		_build_street_labels()
	elif view.zoom >= 0.025 and view.layers.get("labels", true):
		_build_shields()

func _build_street_labels() -> void:
	var vr: Rect2 = view.view_rect()
	var edges := World.edges_in_rect(vr)
	var best := {}
	var minor: bool = view.zoom >= 0.85
	for e in edges:
		var c: int = World.edge_cls[e]
		if c == World.CLS_RAMPE:
			continue
		if not minor and c >= World.CLS_NEBEN and c != World.CLS_LAND:
			continue
		var a: Vector2 = World.node_pos[World.edge_a[e]]
		var b: Vector2 = World.node_pos[World.edge_b[e]]
		var mid := (a + b) * 0.5
		if not vr.has_point(mid):
			continue
		var sm: Vector2 = view.w2s(mid)
		var key := "%d_%d_%d" % [World.edge_name[e], int(sm.x / 420.0), int(sm.y / 300.0)]
		var l: float = World.edge_len[e]
		if not best.has(key) or best[key][1] < l:
			best[key] = [e, l]
	var n := 0
	for key in best:
		var e: int = best[key][0]
		var a: Vector2 = World.node_pos[World.edge_a[e]]
		var b: Vector2 = World.node_pos[World.edge_b[e]]
		if a.x > b.x:
			var t := a
			a = b
			b = t
		var text: String = World.names[World.edge_name[e]]
		if _refs.has(text):
			text = "%s  %s" % [_refs[text], text]
		_labels.append([(a + b) * 0.5, (b - a).angle(), text, World.edge_cls[e]])
		n += 1
		if n > 110:
			break

func _build_shields() -> void:
	var vr: Rect2 = view.view_rect()
	for cls in [World.CLS_AUTOBAHN, World.CLS_BUNDES]:
		var pool: PackedInt32Array = World.class_edges[cls]
		var step := 26 if cls == World.CLS_AUTOBAHN else 34
		var i := 7
		while i < pool.size():
			var e := pool[i]
			i += step
			var mid: Vector2 = (World.node_pos[World.edge_a[e]] + World.node_pos[World.edge_b[e]]) * 0.5
			if not vr.has_point(mid):
				continue
			var name: String = World.names[World.edge_name[e]]
			if cls == World.CLS_BUNDES:
				if not _refs.has(name) or view.zoom < 0.045:
					continue
				name = _refs[name]
			_shields.append([mid, name, cls])

func _txt(pos: Vector2, text: String, size: int, col: Color, outline := true, font: Font = null) -> void:
	var f := font if font != null else _font
	if outline:
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0.07, 0.08, 0.09, 0.9))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _txt_c(pos: Vector2, text: String, size: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_txt(pos - Vector2(w * 0.5, 0), text, size, col)

func _draw() -> void:
	if view == null or not World.built:
		return
	var z: float = view.zoom
	var L: Dictionary = view.layers
	var vr: Rect2 = view.view_rect().grow(200.0)
	# Stadtteilgrenzen und -namen
	if L.get("districts", true) and z < 0.6:
		pass
	if L.get("labels", true):
		if z < 0.22:
			for d in World.districts:
				if d["id"] == "umland":
					continue
				var p: Vector2 = view.w2s(d["c"])
				var big: bool = not d.get("village", false)
				if z < 0.03 and not big:
					continue
				_txt_c(p, String(d["name"]).to_upper() if big else d["name"], 12 if big else 11, Color(0.9, 0.91, 0.92, 0.75 if big else 0.6))
		if z >= 0.06 and z < 1.2:
			for a in World.areas:
				if a["kind"] in ["rail", "campus", "messe", "stadium"] and z < 0.15:
					continue
				if not vr.has_point(a["c"]):
					continue
				var col := Color("#6fa3c8") if a["kind"] == "water" else (Color("#7fae8b") if a["kind"] in ["forest", "park"] else Color("#a4adb5"))
				_txt_c(view.w2s(a["c"]), a["name"], 11, col)
			for r in World.rivers:
				var pts: PackedVector2Array = r["pts"]
				for k in [pts.size() / 4, pts.size() * 3 / 4]:
					if vr.has_point(pts[k]):
						_txt_c(view.w2s(pts[k]) + Vector2(0, 4), r["name"], 11, Color("#6fa3c8"))
	# Straßenschilder (niedrige Zoomstufe)
	for s in _shields:
		var p: Vector2 = view.w2s(s[0])
		var w := _font.get_string_size(s[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8.0
		var rect := Rect2(p - Vector2(w * 0.5, 7), Vector2(w, 14))
		draw_rect(rect, Color("#2f5f8f") if s[2] == World.CLS_AUTOBAHN else Color("#c9a53a"))
		draw_rect(rect, Color("#101214"), false, 1.0)
		draw_string(_font, rect.position + Vector2(4, 11), s[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE if s[2] == World.CLS_AUTOBAHN else Color("#101214"))
	# Straßennamen
	for l in _labels:
		var p: Vector2 = view.w2s(l[0])
		var size := 11 if l[3] <= World.CLS_HAUPT else 10
		var w := _font.get_string_size(l[2], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_set_transform(p, l[1], Vector2.ONE)
		draw_string_outline(_font, Vector2(-w * 0.5, 4), l[2], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0.08, 0.09, 0.1, 0.85))
		draw_string(_font, Vector2(-w * 0.5, 4), l[2], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("#d5d8db") if l[3] <= World.CLS_HAUPT else Color("#aab1b8"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not State.active:
		_draw_hud()
		return
	if L.get("traffic", true):
		_draw_traffic(vr)
	if L.get("pois", true) and z >= 0.1:
		for p in World.pois:
			if not vr.has_point(p["p"]):
				continue
			var sp: Vector2 = view.w2s(p["p"])
			var col: Color = POI_COLOR.get(p["kind"], Color("#9aa3ab"))
			draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color("#202326"))
			draw_rect(Rect2(sp - Vector2(3, 3), Vector2(6, 6)), col)
			if z >= 0.3:
				_txt(sp + Vector2(8, 4), p["name"], 10, Color("#c3c8cd"))
	for ev in State.env.get("events", []):
		var sp: Vector2 = view.w2s(Vector2(ev["x"], ev["y"]))
		draw_arc(sp, 16.0, 0, TAU, 24, Color("#d6a83b"), 1.5)
		_txt(sp + Vector2(20, 4), ev["name"], 10, Color("#d6a83b"))
	if L.get("stations", true) and z >= 0.02:
		_draw_stations(vr, z)
	_draw_routes()
	_draw_calls()
	_draw_incidents(z)
	_draw_vehicles(vr, z)
	_draw_hud()

func _draw_traffic(vr: Rect2) -> void:
	var env: Dictionary = State.env
	for k in env.get("jams", {}):
		var e := int(k)
		var a: Vector2 = World.node_pos[World.edge_a[e]]
		if not vr.has_point(a):
			continue
		var f := float(env["jams"][k])
		draw_line(view.w2s(a), view.w2s(World.node_pos[World.edge_b[e]]), Color("#c83d3d") if f > 2.7 else Color("#d98a2b"), 3.0)
	for k in env.get("sites", {}):
		var e := int(k)
		var a: Vector2 = World.node_pos[World.edge_a[e]]
		if not vr.has_point(a):
			continue
		var b: Vector2 = World.node_pos[World.edge_b[e]]
		draw_dashed_line(view.w2s(a), view.w2s(b), Color("#d6a83b"), 3.0, 6.0)
		var m: Vector2 = view.w2s((a + b) * 0.5)
		draw_colored_polygon(PackedVector2Array([m + Vector2(0, -7), m + Vector2(6, 4), m + Vector2(-6, 4)]), Color("#d6a83b"))
		draw_line(m + Vector2(0, -3), m + Vector2(0, 1), Color("#202326"), 1.5)
	for k in env.get("closures", {}):
		var e := int(k)
		var a: Vector2 = World.node_pos[World.edge_a[e]]
		if not vr.has_point(a):
			continue
		var b: Vector2 = World.node_pos[World.edge_b[e]]
		draw_line(view.w2s(a), view.w2s(b), Color("#c83d3d"), 4.0)
		var m: Vector2 = view.w2s((a + b) * 0.5)
		draw_circle(m, 6.5, Color("#c83d3d"))
		draw_rect(Rect2(m - Vector2(4, 1.5), Vector2(8, 3)), Color.WHITE)

func _draw_stations(vr: Rect2, z: float) -> void:
	var small := z < 0.045
	for h in Sim.hospitals:
		if not vr.has_point(h["p"]):
			continue
		var sp: Vector2 = view.w2s(h["p"])
		var r := 4.0 if small else 6.5
		draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), Color("#e5e7e9"))
		draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), Color("#202326"), false, 1.0)
		if not small:
			draw_string(_font, sp + Vector2(-4, 4), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c83d3d"))
		if z >= 0.25:
			_txt(sp + Vector2(10, 4), h["name"], 10, Color("#e5e7e9"))
	for id in State.stations:
		var st: Dictionary = State.stations[id]
		var wp := Vector2(st["x"], st["y"])
		if not vr.has_point(wp):
			continue
		var sp: Vector2 = view.w2s(wp)
		var col := Data.org_color(st["org"])
		var r := 3.0 if small else 6.0
		var rect := Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_rect(rect, Color("#202326"))
		draw_rect(rect.grow(-1.0), col)
		if view.sel["kind"] == "station" and view.sel["id"] == id:
			draw_rect(rect.grow(3.0), Color.WHITE, false, 1.5)
		if not small:
			draw_string(_font, sp + Vector2(-3.5, 4), ORG_LETTER.get(st["org"], "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#16181a"))
		if z >= 0.3:
			_txt(sp + Vector2(10, 4), st["name"], 10, Color("#d8dbde"))

func _route_points(v: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var route: Array = v["route"]
	if route.is_empty():
		return pts
	pts.append(view.w2s(State.veh_pos(v)))
	var start := int(v["ri"]) + (0 if v["pre"] else 1)
	for i in range(start, route.size()):
		pts.append(view.w2s(World.node_pos[int(route[i])]))
	pts.append(view.w2s(Vector2(v["dx"], v["dy"])))
	return pts

func _draw_routes() -> void:
	if not view.layers.get("routes", true):
		return
	var ids: Array = []
	if view.sel["kind"] == "vehicle" and State.vehicles.has(view.sel["id"]):
		ids.append(view.sel["id"])
	elif view.sel["kind"] == "incident":
		ids = State.incident_vehicles(view.sel["id"])
	for id in ids:
		var v: Dictionary = State.vehicles[id]
		var pts := _route_points(v)
		if pts.size() >= 2:
			draw_polyline(pts, Color(0.07, 0.08, 0.09, 0.8), 5.0, true)
			draw_polyline(pts, Data.org_color(v["org"]).lightened(0.25), 2.5, true)
			draw_circle(pts[pts.size() - 1], 4.0, Color.WHITE)

func _draw_calls() -> void:
	for id in State.calls:
		var c: Dictionary = State.calls[id]
		if c["state"] != "active" or c["loc"].is_empty():
			continue
		var sp: Vector2 = view.w2s(Vector2(c["loc"]["x"], c["loc"]["y"]))
		var r: float = float(c["loc"]["r"]) * view.zoom
		if r > 6.0:
			draw_circle(sp, r, Color(0.84, 0.66, 0.23, 0.10))
			draw_arc(sp, r, 0, TAU, 48, Color("#d6a83b"), 1.5)
		var blink := fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0
		draw_rect(Rect2(sp - Vector2(7, 7), Vector2(14, 14)), Color("#202326"))
		draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), Color("#d6a83b") if blink else Color("#8a6d28"))
		draw_string(_font, sp + Vector2(-4, 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#16181a"))

func _draw_incidents(z: float) -> void:
	for id in State.incidents:
		var inc: Dictionary = State.incidents[id]
		var sp: Vector2 = view.w2s(Vector2(inc["x"], inc["y"]))
		var col: Color = [Color("#c83d3d"), Color("#c83d3d"), Color("#d6a83b"), Color("#497fa8")][clampi(int(inc["prio"]), 1, 3)]
		if inc["done"]:
			col = Color("#6b737b")
		var r: float = float(inc["radius"]) * z
		if r > 8.0:
			draw_arc(sp, r, 0, TAU, 48, Color(col, 0.7), 1.2)
		var s := 8.0
		var selected: bool = view.sel["kind"] == "incident" and view.sel["id"] == id
		var poly := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0)])
		var outer := PackedVector2Array([sp + Vector2(0, -s - 2), sp + Vector2(s + 2, 0), sp + Vector2(0, s + 2), sp + Vector2(-s - 2, 0)])
		draw_colored_polygon(outer, Color.WHITE if selected else Color("#16181a"))
		draw_colored_polygon(poly, col)
		if inc["status"] == "neu" and fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0:
			draw_arc(sp, s + 6.0, 0, TAU, 24, col, 2.0)
		if z >= 0.05 or selected:
			_txt(sp + Vector2(s + 5, 4), inc["keyword"], 11, Color("#f0f1f2"))

func _draw_vehicles(vr: Rect2, z: float) -> void:
	var blink := fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
	for id in State.vehicles:
		var v: Dictionary = State.vehicles[id]
		if not view.vehicle_drawn(v):
			continue
		var wp := State.veh_pos(v)
		if not vr.has_point(wp):
			continue
		var sp: Vector2 = view.w2s(wp)
		var col := Data.org_color(v["org"])
		var selected: bool = view.sel["kind"] == "vehicle" and view.sel["id"] == id
		if bool(Data.vehicle_types[v["type"]].get("air", false)):
			var r := 9.0 if z >= 0.1 else 6.0
			draw_circle(sp, r + 1.5, Color.WHITE if selected else Color("#111315"))
			draw_circle(sp, r, Color("#e8c45a"))
			var rot := float(Time.get_ticks_msec()) / 90.0 if v["state"] in ["enroute", "returning"] else 0.0
			for k in 2:
				var a := rot + k * PI * 0.5
				draw_line(sp - Vector2.from_angle(a) * (r + 6), sp + Vector2.from_angle(a) * (r + 6), Color(0.1, 0.1, 0.1, 0.7), 1.5)
			draw_string(_font, sp + Vector2(-4, 4), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#16181a"))
			if z >= 0.04 or selected:
				_txt(sp + Vector2(r + 6, 4), v["callsign"], 10, Color("#f0d68a"))
			continue
		if z < 0.1:
			draw_rect(Rect2(sp - Vector2(3.5, 3.5), Vector2(7, 7)), Color.WHITE if selected else Color("#111315"))
			draw_rect(Rect2(sp - Vector2(2.5, 2.5), Vector2(5, 5)), col)
			if v["emergency"] and blink:
				draw_rect(Rect2(sp - Vector2(1, 1), Vector2(2, 2)), Color("#7fc4ff"))
			continue
		var ang: float = v["heading"]
		draw_set_transform(sp, ang, Vector2.ONE)
		draw_rect(Rect2(-8, -5, 16, 10), Color.WHITE if selected else Color("#111315"))
		draw_rect(Rect2(-7, -4, 14, 8), col)
		draw_rect(Rect2(3, -4, 4, 8), col.darkened(0.35))
		if v["emergency"]:
			draw_rect(Rect2(-2, -4, 3, 8), Color("#7fc4ff") if blink else Color("#2c5f8f"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var st := int(v["status"])
		draw_rect(Rect2(sp + Vector2(8, -16), Vector2(11, 12)), Color("#16181a"))
		draw_string(_mono, sp + Vector2(10, -6), str(st), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Data.fms_color(st))
		if z >= 0.3 or selected:
			_txt(sp + Vector2(22, -6), UI.short_callsign(v), 10, Color("#e5e7e9"))

func _draw_hud() -> void:
	var z: float = view.zoom
	# Maßstab
	var target := 130.0 / z
	var nice := 100.0
	for n in [50.0, 100.0, 250.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0]:
		if n <= target:
			nice = n
	var w := nice * z
	var base := Vector2(14, size.y - 16)
	draw_rect(Rect2(base + Vector2(-6, -18), Vector2(w + 12, 26)), Color(0.125, 0.137, 0.149, 0.85))
	draw_line(base, base + Vector2(w, 0), Color("#e5e7e9"), 1.5)
	draw_line(base, base + Vector2(0, -5), Color("#e5e7e9"), 1.5)
	draw_line(base + Vector2(w, 0), base + Vector2(w, -5), Color("#e5e7e9"), 1.5)
	draw_string(_font, base + Vector2(4, -6), ("%d m" % int(nice)) if nice < 1000.0 else ("%d km" % int(nice / 1000.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#e5e7e9"))
	# Nordpfeil
	var np := Vector2(size.x - 24, 28)
	draw_colored_polygon(PackedVector2Array([np + Vector2(0, -12), np + Vector2(6, 8), np + Vector2(0, 4), np + Vector2(-6, 8)]), Color("#e5e7e9"))
	draw_string(_font, np + Vector2(-4, 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#a4adb5"))
	# Werkzeughinweis
	if view.tool != "":
		var text: String = view.tool_hint + "   (Rechtsklick / Esc: abbrechen)"
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(Vector2(size.x * 0.5 - tw * 0.5 - 10, 8), Vector2(tw + 20, 24)), Color("#d6a83b"))
		draw_string(_font, Vector2(size.x * 0.5 - tw * 0.5, 25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#16181a"))
	# Hover-Information
	var info := ""
	if not view.hover.is_empty():
		info = view.hover["text"]
	elif z >= 0.25 and State.active:
		var ne := World.nearest_edge(view.mouse_world, 14.0 / z)
		if not ne.is_empty():
			var e: int = ne["edge"]
			info = "%s  ·  %s  ·  %s" % [World.street_name(e), World.CLASS_NAMES[World.edge_cls[e]], World.districts[World.edge_dist[e]]["name"]]
	if info != "":
		var tw := _font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var pos := Vector2(w + 34, size.y - 30)
		draw_rect(Rect2(pos, Vector2(tw + 14, 22)), Color(0.125, 0.137, 0.149, 0.92))
		draw_rect(Rect2(pos, Vector2(tw + 14, 22)), Color("#454b52"), false, 1.0)
		draw_string(_font, pos + Vector2(7, 15), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e5e7e9"))
