extends Node
## Statische Spielwelt (Stadt Bavaria): Straßengraph, Stadtteile, Flächennutzung,
## räumlicher Index und Routing. Die Welt ist deterministisch – Host und Clients
## erzeugen exakt dieselbe Karte aus denselben Daten.

const Gen = preload("res://src/map/world_gen.gd")

const CLS_AUTOBAHN := 0
const CLS_RAMPE := 1
const CLS_BUNDES := 2
const CLS_HAUPT := 3
const CLS_NEBEN := 4
const CLS_WOHN := 5
const CLS_LAND := 6
const CLS_FUSS := 7
const CLS_ZUFAHRT := 8
const CLASS_NAMES := ["Autobahn", "Anschlussstelle", "Bundesstraße", "Hauptstraße", "Nebenstraße", "Wohnstraße", "Landstraße", "Fußgängerzone", "Zufahrtsstraße"]
## km/h im Normalverkehr bzw. mit Sonder- und Wegerechten
const SPEED_NORMAL := [105.0, 50.0, 55.0, 45.0, 36.0, 26.0, 80.0, 6.0, 24.0]
const SPEED_EMERG := [140.0, 70.0, 85.0, 72.0, 58.0, 44.0, 110.0, 14.0, 38.0]
const GRID := 250.0

var built := false
var cfg: Dictionary = {}
var bounds := Rect2()
var districts: Array = []
var umland_idx := 0
var areas: Array = []
var rivers: Array = []
var river_cells := {}
var city_a := 10500.0
var city_b := 9400.0
var chunk_size := 1000.0
var chunks_x := 0
var chunks_y := 0

var node_pos := PackedVector2Array()
var node_flags := PackedByteArray()
var node_edges: Array = []
var edge_a := PackedInt32Array()
var edge_b := PackedInt32Array()
var edge_len := PackedFloat32Array()
var edge_cls := PackedByteArray()
var edge_flags := PackedByteArray()
var edge_name := PackedInt32Array()
var edge_num := PackedInt32Array()
var edge_dist := PackedByteArray()
var names := PackedStringArray()
var junctions: Array = []

# dynamische Kantenattribute (werden von State gesetzt)
var edge_block := PackedByteArray()
var edge_traffic := PackedFloat32Array()
var edge_tn := PackedFloat32Array()
var edge_te := PackedFloat32Array()
var speed_scale := 1.0
var traffic_level := 1.0

var gw := 0
var gh := 0
var grid_nodes: Array = []
var grid_edges: Array = []
var chunk_edges: Array = []
var district_edges: Array = []
var class_edges: Array = []
var pois: Array = []

# Routing-Arbeitsfelder
var _hk := PackedFloat32Array()
var _hv := PackedInt32Array()
var _hn := 0
var _g := PackedFloat32Array()
var _came := PackedInt32Array()

func ensure_built() -> void:
	if built:
		return
	var t0 := Time.get_ticks_msec()
	cfg = Data.world
	var b: Array = cfg["bounds"]
	bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	city_a = cfg["city"]["a"]
	city_b = cfg["city"]["b"]
	chunk_size = cfg.get("chunk", 1000)
	chunks_x = int(ceil(bounds.size.x / chunk_size))
	chunks_y = int(ceil(bounds.size.y / chunk_size))
	_prepare_districts()
	_prepare_areas()
	_prepare_rivers()
	var gen := Gen.new()
	gen.generate(self)
	_build_index()
	recompute_times()
	pois = []
	for p in cfg.get("pois", []):
		var q: Dictionary = p.duplicate()
		q["p"] = Vector2(p["pos"][0], p["pos"][1])
		q["node"] = nearest_node(q["p"])
		pois.append(q)
	built = true
	print("[World] Bavaria erzeugt: %d Knoten, %d Kanten, %d ms" % [node_pos.size(), edge_a.size(), Time.get_ticks_msec() - t0])

func _prepare_districts() -> void:
	districts = []
	for d in cfg["districts"]:
		var e: Dictionary = d.duplicate()
		e["c"] = Vector2(d["center"][0], d["center"][1])
		e["maxr"] = float(d.get("maxr", 0))
		e["village"] = d.get("village", false)
		e["force_city"] = d.get("force_city", false)
		districts.append(e)
	var u: Dictionary = cfg["umland"].duplicate()
	u["c"] = Vector2.ZERO
	u["maxr"] = 0.0
	u["village"] = false
	u["force_city"] = false
	u["weight"] = 1.0
	districts.append(u)
	umland_idx = districts.size() - 1

func _prepare_areas() -> void:
	areas = []
	for a in cfg.get("areas", []):
		var e := {"kind": a["kind"], "name": a["name"], "c": Vector2(a["c"][0], a["c"][1])}
		var rot := deg_to_rad(a.get("rot", 0.0))
		e["cs"] = cos(rot)
		e["sn"] = sin(rot)
		if a.has("rx"):
			e["rect"] = false
			e["rx"] = float(a["rx"])
			e["ry"] = float(a["ry"])
			e["rb"] = max(e["rx"], e["ry"])
		else:
			e["rect"] = true
			e["rx"] = a["w"] * 0.5
			e["ry"] = a["h"] * 0.5
			e["rb"] = Vector2(e["rx"], e["ry"]).length()
		areas.append(e)

func area_polygon(a: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var c: Vector2 = a["c"]
	var cs: float = a["cs"]
	var sn: float = a["sn"]
	if a["rect"]:
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var l := Vector2(q.x * a["rx"], q.y * a["ry"])
			out.append(c + Vector2(l.x * cs - l.y * sn, l.x * sn + l.y * cs))
	else:
		for k in 40:
			var t := TAU * k / 40.0
			var l := Vector2(cos(t) * a["rx"], sin(t) * a["ry"])
			out.append(c + Vector2(l.x * cs - l.y * sn, l.x * sn + l.y * cs))
	return out

func _area_contains(a: Dictionary, p: Vector2) -> bool:
	var d: Vector2 = p - a["c"]
	var rb: float = a["rb"]
	if absf(d.x) > rb or absf(d.y) > rb:
		return false
	var lx: float = d.x * a["cs"] + d.y * a["sn"]
	var ly: float = -d.x * a["sn"] + d.y * a["cs"]
	if a["rect"]:
		return absf(lx) <= a["rx"] and absf(ly) <= a["ry"]
	var ex: float = lx / a["rx"]
	var ey: float = ly / a["ry"]
	return ex * ex + ey * ey <= 1.0

func _prepare_rivers() -> void:
	rivers = []
	river_cells = {}
	var gen := Gen.new()
	for r in cfg.get("rivers", []):
		var pts: PackedVector2Array = gen._smooth(r["points"], 70.0)
		rivers.append({"name": r["name"], "width": float(r["width"]), "pts": pts})
		for p in pts:
			var cx := int(floor(p.x / GRID))
			var cy := int(floor(p.y / GRID))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					river_cells[(cx + dx + 512) * 4096 + (cy + dy + 512)] = true

func _river_flag(p: Vector2) -> bool:
	return river_cells.has((int(floor(p.x / GRID)) + 512) * 4096 + int(floor(p.y / GRID)) + 512)

## Abstand zum nächsten Gewässerrand eines Flusses (negativ = im Wasser), groß wenn fern.
func river_distance(p: Vector2) -> float:
	if not _river_flag(p):
		return 9999.0
	var best := 9999.0
	for r in rivers:
		var pts: PackedVector2Array = r["pts"]
		var hw: float = r["width"] * 0.5
		for i in range(pts.size() - 1):
			var c := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			var d := p.distance_to(c) - hw
			if d < best:
				best = d
	return best

func segment_crosses_river(a: Vector2, b: Vector2) -> bool:
	if not (_river_flag(a) or _river_flag(b) or _river_flag((a + b) * 0.5)):
		return false
	for r in rivers:
		var pts: PackedVector2Array = r["pts"]
		for i in range(pts.size() - 1):
			if Geometry2D.segment_intersects_segment(a, b, pts[i], pts[i + 1]) != null:
				return true
	return false

func in_city(p: Vector2) -> bool:
	var th := atan2(p.y, p.x)
	var rr := sqrt(pow(p.x / city_a, 2.0) + pow(p.y / city_b, 2.0))
	return rr < 1.0 + 0.06 * sin(3.0 * th + 0.7) + 0.04 * sin(5.0 * th + 2.1)

func city_outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 180:
		var th := TAU * k / 180.0
		var f := 1.0 + 0.06 * sin(3.0 * th + 0.7) + 0.04 * sin(5.0 * th + 2.1)
		out.append(Vector2(cos(th) * city_a * f, sin(th) * city_b * f))
	return out

func district_at(p: Vector2) -> int:
	var best := -1
	var bd := INF
	var city := in_city(p)
	for i in range(districts.size() - 1):
		var d: Dictionary = districts[i]
		var dist: float = p.distance_to(d["c"])
		var maxr: float = d["maxr"]
		if maxr > 0.0 and dist > maxr:
			continue
		if not city and not (d["village"] or d["force_city"]):
			continue
		var s: float = dist / d["weight"]
		if s < bd:
			bd = s
			best = i
	return best if best >= 0 else umland_idx

func district_index(id: String) -> int:
	for i in districts.size():
		if districts[i]["id"] == id:
			return i
	return -1

func landuse(p: Vector2) -> String:
	if river_distance(p) < 0.0:
		return "water"
	for a in areas:
		if _area_contains(a, p):
			return a["kind"]
	return ""

func area_name_at(p: Vector2) -> String:
	for a in areas:
		if _area_contains(a, p):
			return a["name"]
	return ""

# ---------------------------------------------------------------- Index
func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x - bounds.position.x) / GRID), 0, gw - 1), clampi(int((p.y - bounds.position.y) / GRID), 0, gh - 1))

func _build_index() -> void:
	gw = int(ceil(bounds.size.x / GRID))
	gh = int(ceil(bounds.size.y / GRID))
	grid_nodes = []
	grid_edges = []
	grid_nodes.resize(gw * gh)
	grid_edges.resize(gw * gh)
	for i in gw * gh:
		grid_nodes[i] = PackedInt32Array()
		grid_edges[i] = PackedInt32Array()
	for n in node_pos.size():
		var c := _cell(node_pos[n])
		grid_nodes[c.y * gw + c.x].append(n)
	chunk_edges = []
	chunk_edges.resize(chunks_x * chunks_y)
	for i in chunks_x * chunks_y:
		chunk_edges[i] = PackedInt32Array()
	district_edges = []
	for i in districts.size():
		district_edges.append(PackedInt32Array())
	class_edges = []
	for i in 9:
		class_edges.append(PackedInt32Array())
	var ne := edge_a.size()
	edge_block.resize(ne)
	edge_block.fill(0)
	edge_traffic.resize(ne)
	edge_traffic.fill(1.0)
	for e in ne:
		var pa := node_pos[edge_a[e]]
		var pb := node_pos[edge_b[e]]
		var ca := _cell(pa)
		var cb := _cell(pb)
		for gy in range(min(ca.y, cb.y), max(ca.y, cb.y) + 1):
			for gx in range(min(ca.x, cb.x), max(ca.x, cb.x) + 1):
				grid_edges[gy * gw + gx].append(e)
		var mid := (pa + pb) * 0.5
		var cx := clampi(int((mid.x - bounds.position.x) / chunk_size), 0, chunks_x - 1)
		var cy := clampi(int((mid.y - bounds.position.y) / chunk_size), 0, chunks_y - 1)
		chunk_edges[cy * chunks_x + cx].append(e)
		class_edges[edge_cls[e]].append(e)
		var c: int = edge_cls[e]
		if c != CLS_AUTOBAHN and c != CLS_RAMPE and (edge_flags[e] == 0):
			district_edges[edge_dist[e]].append(e)

func nearest_node(p: Vector2, max_radius := 3000.0) -> int:
	var c := _cell(p)
	var best := -1
	var bd := INF
	var ring := 0
	var max_ring := int(ceil(max_radius / GRID)) + 1
	while ring <= max_ring:
		for gy in range(c.y - ring, c.y + ring + 1):
			if gy < 0 or gy >= gh:
				continue
			for gx in range(c.x - ring, c.x + ring + 1):
				if gx < 0 or gx >= gw:
					continue
				if ring > 0 and gx != c.x - ring and gx != c.x + ring and gy != c.y - ring and gy != c.y + ring:
					continue
				for n in grid_nodes[gy * gw + gx]:
					var hw := false
					for e in node_edges[n]:
						if edge_cls[e] == CLS_AUTOBAHN:
							hw = true
							break
					if hw:
						continue
					var d := p.distance_squared_to(node_pos[n])
					if d < bd:
						bd = d
						best = n
		if best >= 0 and sqrt(bd) < ring * GRID:
			break
		ring += 1
	return best

## Nächste Kante: {edge, t, dist, point} oder leeres Dictionary.
func nearest_edge(p: Vector2, radius := 400.0, allow_highway := true) -> Dictionary:
	var c := _cell(p)
	var rr := int(ceil(radius / GRID))
	var best := -1
	var bd := radius
	var bp := Vector2.ZERO
	for gy in range(max(0, c.y - rr), min(gh, c.y + rr + 1)):
		for gx in range(max(0, c.x - rr), min(gw, c.x + rr + 1)):
			for e in grid_edges[gy * gw + gx]:
				if not allow_highway and edge_cls[e] <= CLS_RAMPE:
					continue
				var q := Geometry2D.get_closest_point_to_segment(p, node_pos[edge_a[e]], node_pos[edge_b[e]])
				var d := p.distance_to(q)
				if d < bd:
					bd = d
					best = e
					bp = q
	if best < 0:
		return {}
	var t := node_pos[edge_a[best]].distance_to(bp) / edge_len[best]
	return {"edge": best, "t": t, "dist": bd, "point": bp}

func edges_in_rect(r: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	var c0 := _cell(r.position)
	var c1 := _cell(r.end)
	for gy in range(c0.y, c1.y + 1):
		for gx in range(c0.x, c1.x + 1):
			for e in grid_edges[gy * gw + gx]:
				if not seen.has(e):
					seen[e] = true
					out.append(e)
	return out

func edge_point(e: int, t: float) -> Vector2:
	return node_pos[edge_a[e]].lerp(node_pos[edge_b[e]], t)

func edge_between(a: int, b: int) -> int:
	for e in node_edges[a]:
		if edge_a[e] == b or edge_b[e] == b:
			return e
	return -1

func street_name(e: int) -> String:
	return names[edge_name[e]]

## Adresse zu einer Position: {street, number, district, plz, text, edge}
func address_at(p: Vector2) -> Dictionary:
	var ne := nearest_edge(p, 900.0)
	var d := district_at(p)
	var dd: Dictionary = districts[d]
	if ne.is_empty():
		return {"street": "Freifläche", "number": "", "district": dd["name"], "plz": dd["plz"], "text": "Freifläche, %s" % dd["name"], "edge": -1}
	var e: int = ne["edge"]
	var street := street_name(e)
	var cls: int = edge_cls[e]
	var number := ""
	var text := ""
	if cls == CLS_AUTOBAHN:
		var km := 10.0 + fmod(absf(ne["point"].x * 0.37 + ne["point"].y * 0.61), 62000.0) / 1000.0
		number = "km %.1f" % km
		text = "%s, %s, Höhe %s" % [street, number, dd["name"]]
	elif cls == CLS_RAMPE:
		text = "%s, %s" % [street, dd["name"]]
	else:
		var side := 0 if (p - ne["point"]).cross(node_pos[edge_b[e]] - node_pos[edge_a[e]]) > 0.0 else 1
		var num: int = edge_num[e] + int(ne["t"] * 6.0) * 2 + side
		number = str(num)
		text = "%s %s, %s Bavaria-%s" % [street, number, dd["plz"], dd["name"]]
		if dd.get("village", false) or d == umland_idx:
			text = "%s %s, %s %s" % [street, number, dd["plz"], dd["name"]]
	return {"street": street, "number": number, "district": dd["name"], "plz": dd["plz"], "text": text, "edge": e}

# ---------------------------------------------------------------- Verkehr / Kantenzeiten
func recompute_times() -> void:
	var ne := edge_a.size()
	edge_tn.resize(ne)
	edge_te.resize(ne)
	for e in ne:
		_update_edge_time(e)

func _update_edge_time(e: int) -> void:
	var c: int = edge_cls[e]
	var tf: float = max(1.0, edge_traffic[e] * (traffic_level if c <= CLS_NEBEN else 1.0 + (traffic_level - 1.0) * 0.4))
	var vn: float = SPEED_NORMAL[c] / 3.6 * speed_scale / tf
	var ve: float = SPEED_EMERG[c] / 3.6 * (0.6 + 0.4 * speed_scale) / pow(tf, 0.4)
	edge_tn[e] = edge_len[e] / vn
	edge_te[e] = edge_len[e] / ve

func set_edge_traffic(e: int, factor: float) -> void:
	edge_traffic[e] = factor
	_update_edge_time(e)

func set_edge_blocked(e: int, blocked: bool) -> void:
	edge_block[e] = 1 if blocked else 0

func reset_dynamic() -> void:
	edge_block.fill(0)
	edge_traffic.fill(1.0)
	speed_scale = 1.0
	traffic_level = 1.0
	recompute_times()

func edge_speed(e: int, emergency: bool) -> float:
	return edge_len[e] / (edge_te[e] if emergency else edge_tn[e])

# ---------------------------------------------------------------- Routing (A*)
func _hpush(k: float, v: int) -> void:
	if _hn >= _hk.size():
		_hk.resize(_hn * 2 + 256)
		_hv.resize(_hn * 2 + 256)
	var i := _hn
	_hn += 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hk[p] <= k:
			break
		_hk[i] = _hk[p]
		_hv[i] = _hv[p]
		i = p
	_hk[i] = k
	_hv[i] = v

var _hpk := 0.0
func _hpop() -> int:
	var top := _hv[0]
	_hpk = _hk[0]
	_hn -= 1
	if _hn > 0:
		var k := _hk[_hn]
		var v := _hv[_hn]
		var i := 0
		while true:
			var c := i * 2 + 1
			if c >= _hn:
				break
			if c + 1 < _hn and _hk[c + 1] < _hk[c]:
				c += 1
			if _hk[c] >= k:
				break
			_hk[i] = _hk[c]
			_hv[i] = _hv[c]
			i = c
		_hk[i] = k
		_hv[i] = v
	return top

func _turn_cost(e_in: int, e_out: int, via: int, emergency: bool) -> float:
	var cost := 0.0
	var fl: int = node_flags[via]
	if fl == 1:
		cost += 1.5 if emergency else 9.0
	elif fl == 2:
		cost += 1.0 if emergency else 3.0
	if e_in < 0:
		return cost
	var p := node_pos[via]
	var a := node_pos[edge_a[e_in]] if edge_b[e_in] == via else node_pos[edge_b[e_in]]
	var b := node_pos[edge_b[e_out]] if edge_a[e_out] == via else node_pos[edge_a[e_out]]
	var d1 := (p - a).normalized()
	var d2 := (b - p).normalized()
	var dot := d1.dot(d2)
	if dot < -0.8:
		cost += 8.0 if emergency else 20.0
	elif dot < 0.5:
		cost += 2.0 if emergency else 5.0
	return cost

## Schnellste Route. Rückgabe: {ok, nodes:PackedInt32Array, time, dist}
func find_path(from: int, to: int, emergency := true, ignore_block := false) -> Dictionary:
	if from < 0 or to < 0:
		return {"ok": false}
	if from == to:
		return {"ok": true, "nodes": PackedInt32Array([from]), "time": 0.0, "dist": 0.0}
	var n := node_pos.size()
	_g.resize(n)
	_g.fill(INF)
	_came.resize(n)
	_came.fill(-1)
	_hn = 0
	var goal := node_pos[to]
	var inv_vmax := 1.0 / (145.0 / 3.6)
	var times := edge_te if emergency else edge_tn
	_g[from] = 0.0
	_hpush(node_pos[from].distance_to(goal) * inv_vmax, from)
	var found := false
	while _hn > 0:
		var u := _hpop()
		if u == to:
			found = true
			break
		var gu := _g[u]
		if _hpk > gu + node_pos[u].distance_to(goal) * inv_vmax + 0.001:
			continue
		var ein := _came[u]
		for e in node_edges[u]:
			if edge_block[e] != 0 and not ignore_block:
				continue
			var v := edge_b[e] if edge_a[e] == u else edge_a[e]
			var ng := gu + times[e] + _turn_cost(ein, e, u, emergency)
			if ng < _g[v]:
				_g[v] = ng
				_came[v] = e
				_hpush(ng + node_pos[v].distance_to(goal) * inv_vmax, v)
	if not found:
		return {"ok": false}
	var path := PackedInt32Array()
	var cur := to
	var dist := 0.0
	while cur != from:
		path.append(cur)
		var e := _came[cur]
		dist += edge_len[e]
		cur = edge_a[e] if edge_b[e] == cur else edge_b[e]
	path.append(from)
	path.reverse()
	return {"ok": true, "nodes": path, "time": _g[to], "dist": dist}

## Fahrzeiten von einem Knoten zu allen Knoten (Dijkstra) – für Dispositionsvorschläge.
func times_from(from: int, emergency := true) -> PackedFloat32Array:
	var n := node_pos.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	if from < 0:
		return g
	_hn = 0
	var times := edge_te if emergency else edge_tn
	g[from] = 0.0
	_hpush(0.0, from)
	while _hn > 0:
		var u := _hpop()
		var gu := g[u]
		if _hpk > gu + 0.001:
			continue
		for e in node_edges[u]:
			if edge_block[e] != 0:
				continue
			var v := edge_b[e] if edge_a[e] == u else edge_a[e]
			var ng := gu + times[e] + (1.5 if node_flags[u] == 1 else 0.0)
			if ng < g[v]:
				g[v] = ng
				_hpush(ng, v)
	return g

func path_points(nodes: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for n in nodes:
		out.append(node_pos[n])
	return out

# ---------------------------------------------------------------- Zufallsorte
## Zufälliger Ort an einer Straße. filter: {district:int, classes:Array, style:Array}
func random_road_point(rng: RandomNumberGenerator, district: int, classes: Array = []) -> Dictionary:
	var pool: PackedInt32Array = district_edges[district]
	if pool.is_empty():
		return {}
	for attempt in 30:
		var e := pool[rng.randi() % pool.size()]
		if not classes.is_empty() and not classes.has(int(edge_cls[e])):
			continue
		return _edge_location(rng, e)
	return _edge_location(rng, pool[rng.randi() % pool.size()])

func random_class_point(rng: RandomNumberGenerator, cls: int) -> Dictionary:
	var pool: PackedInt32Array = class_edges[cls]
	if pool.is_empty():
		return {}
	return _edge_location(rng, pool[rng.randi() % pool.size()], cls != CLS_AUTOBAHN)

func _edge_location(rng: RandomNumberGenerator, e: int, offset := true) -> Dictionary:
	var t := rng.randf_range(0.15, 0.85)
	var p := edge_point(e, t)
	if offset:
		var dir := (node_pos[edge_b[e]] - node_pos[edge_a[e]]).normalized()
		p += Vector2(-dir.y, dir.x) * (18.0 if rng.randf() < 0.5 else -18.0)
	var node := edge_a[e] if t < 0.5 else edge_b[e]
	if edge_cls[e] == CLS_AUTOBAHN:
		node = edge_a[e]
	return {"pos": p, "edge": e, "node": node}

## Routing-Knoten zu einer beliebigen Position (auch auf Autobahnen).
func access_node(p: Vector2) -> int:
	var ne := nearest_edge(p, 500.0)
	if ne.is_empty():
		return nearest_node(p)
	var e: int = ne["edge"]
	return edge_a[e] if ne["t"] < 0.5 else edge_b[e]
