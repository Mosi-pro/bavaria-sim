extends RefCounted
## Prozeduraler, deterministischer Generator für die Stadt Bavaria.
## Erzeugt aus data/world/bavaria.json ein zusammenhängendes Straßennetz:
## verzerrtes Raster (Wohn-/Neben-/Hauptstraßen), darübergelegte Ringe und
## Radialen (Bundesstraßen), eigenständige Autobahnen mit Anschlussstellen.

const CLS_AUTOBAHN := 0
const CLS_RAMPE := 1
const CLS_BUNDES := 2
const CLS_HAUPT := 3
const CLS_NEBEN := 4
const CLS_WOHN := 5
const CLS_LAND := 6
const CLS_FUSS := 7
const CLS_ZUFAHRT := 8

const NODE_DROP := {"altstadt": 0.0, "zentrum": 0.02, "wohn_dicht": 0.04, "wohn": 0.08, "vorstadt": 0.14, "industrie": 0.30, "gewerbe": 0.24, "sonder": 0.45, "wald": 0.45, "dorf": 0.05, "land": 1.0}
const EDGE_DROP := {"altstadt": 0.05, "zentrum": 0.04, "wohn_dicht": 0.06, "wohn": 0.10, "vorstadt": 0.15, "industrie": 0.20, "gewerbe": 0.18, "sonder": 0.2, "wald": 0.2, "dorf": 0.08, "land": 0.0}
const JITTER := {"altstadt": 38.0, "zentrum": 10.0, "wohn_dicht": 16.0, "wohn": 26.0, "vorstadt": 34.0, "industrie": 12.0, "gewerbe": 14.0, "sonder": 10.0, "wald": 40.0, "dorf": 36.0, "land": 30.0}
const SPACED_STEMS := ["Wittelsbacher", "Seeburger", "Waldheimer", "Aicheringer", "Moosbrunner", "Hohenrieder", "Kirchstettener", "Oberfeldkirchner"]

var w: Node
var cfg: Dictionary
var S: float
var nx: int
var ny: int
var ox: float
var oy: float
var seed_i: int

var lat_pos := PackedVector2Array()
var lat_alive := PackedByteArray()   # 0 tot, 1 normal, 2 geschützt (Magistrale)
var lat_node := PackedInt32Array()
var lat_dist := PackedByteArray()
var claims := {}                     # key -> [a, b, cls, name, flags]
var claim_order: Array = []

var gpos := PackedVector2Array()
var gmajor := PackedByteArray()
var ea := PackedInt32Array()
var eb := PackedInt32Array()
var ecls := PackedByteArray()
var eflags := PackedByteArray()
var ename := PackedInt32Array()
var enum_ := PackedInt32Array()
var names := PackedStringArray()
var name_cache := {}
var used_names := {}
var major_grid := {}
var junctions: Array = []

static func hashf(a: int, b: int, c: int = 0) -> float:
	var h := (a * 374761393 + b * 668265263 + c * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0

func generate(world: Node) -> void:
	w = world
	cfg = w.cfg
	S = float(cfg.get("lattice", 210))
	seed_i = int(cfg.get("seed", 1))
	var b: Array = cfg["bounds"]
	ox = b[0]
	oy = b[1]
	nx = int((b[2] - b[0]) / S) + 1
	ny = int((b[3] - b[1]) / S) + 1
	_build_lattice()
	_claim_arterials()
	_decide_nodes()
	_build_edges()
	_build_autobahnen()
	_finalize()

# ---------------------------------------------------------------- Raster
func _warp(q: Vector2) -> Vector2:
	var r := q.length()
	if r >= 6000.0:
		return q
	return q * (0.74 + 0.26 * r / 6000.0)

func _unwarp(p: Vector2) -> Vector2:
	var r := p.length()
	if r >= 6000.0 or r < 0.001:
		return p
	var k := 0.26 / 6000.0
	var rq := (-0.74 + sqrt(0.5476 + 4.0 * k * r)) / (2.0 * k)
	return p * (rq / r)

func _lat_index_of(p: Vector2) -> int:
	var q := _unwarp(p)
	var i := int(round((q.x - ox) / S))
	var j := int(round((q.y - oy) / S))
	if i < 0 or j < 0 or i >= nx or j >= ny:
		return -1
	return j * nx + i

func _build_lattice() -> void:
	var n := nx * ny
	lat_pos.resize(n)
	lat_alive.resize(n)
	lat_node.resize(n)
	lat_dist.resize(n)
	for j in ny:
		for i in nx:
			var li := j * nx + i
			var p := _warp(Vector2(ox + i * S, oy + j * S))
			var d: int = w.district_at(p)
			var style: String = w.districts[d]["style"]
			var amp: float = JITTER.get(style, 20.0)
			p += Vector2(hashf(i, j, seed_i) - 0.5, hashf(i, j, seed_i + 7) - 0.5) * 2.0 * amp
			lat_pos[li] = p
			lat_dist[li] = d
			lat_node[li] = -1
			lat_alive[li] = 1

func _smooth(points: Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pts: Array = []
	for p in points:
		pts.append(Vector2(p[0], p[1]))
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[max(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[min(i + 2, pts.size() - 1)]
		var n: int = max(1, int(ceil(p1.distance_to(p2) / step)))
		for k in n:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(k) / n))
	out.append(pts[pts.size() - 1])
	return out

func _ellipse(a: float, b: float, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var per := PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b)))
	var n := int(per / step)
	for k in n:
		var t := TAU * float(k) / n
		out.append(Vector2(cos(t) * a, sin(t) * b))
	return out

func _ckey(a: int, b: int) -> int:
	return (mini(a, b) << 24) | maxi(a, b)

func _claim_arterials() -> void:
	for art in cfg.get("arterials", []):
		var samples: PackedVector2Array
		var closed := false
		if art.has("ring"):
			samples = _ellipse(art["ring"]["a"], art["ring"]["b"], 40.0)
			closed = true
		else:
			samples = _smooth(art["points"], 40.0)
		var label: String = art["name"]
		_claim_path(samples, closed, int(art["class"]), label, art.get("tunnels", []))

func _claim_path(samples: PackedVector2Array, closed: bool, cls: int, label: String, tunnels: Array) -> void:
	var cells: Array = []
	var sums: Array = []
	var cnts: Array = []
	var ts: Array = []
	var n := samples.size()
	for k in n:
		var li := _lat_index_of(samples[k])
		if li < 0:
			continue
		var m := cells.size()
		if m > 0 and cells[m - 1] == li:
			sums[m - 1] += samples[k]
			cnts[m - 1] += 1
			continue
		if m > 1 and cells[m - 2] == li:
			cells.pop_back(); sums.pop_back(); cnts.pop_back(); ts.pop_back()
			sums[m - 2] += samples[k]
			cnts[m - 2] += 1
			continue
		if m > 0:
			var pi: int = cells[m - 1] % nx
			var pj: int = cells[m - 1] / nx
			var ci: int = li % nx
			var cj: int = li / nx
			if pi != ci and pj != cj and abs(pi - ci) == 1 and abs(pj - cj) == 1:
				var mid := cj * nx + pi
				if not cells.has(mid):
					cells.append(mid); sums.append(Vector2.ZERO); cnts.append(0); ts.append(float(k) / n)
		cells.append(li); sums.append(samples[k]); cnts.append(1); ts.append(float(k) / n)
	if closed and cells.size() > 2 and cells[cells.size() - 1] == cells[0]:
		cells.pop_back(); sums.pop_back(); cnts.pop_back(); ts.pop_back()
	var m2 := cells.size()
	if m2 < 2:
		return
	# Positionen auf die Ideallinie ziehen
	var newpos: Array = []
	newpos.resize(m2)
	for k in m2:
		newpos[k] = (sums[k] / cnts[k]) if cnts[k] > 0 else null
	for k in m2:
		if newpos[k] == null:
			var a = newpos[(k - 1 + m2) % m2]
			var b = newpos[(k + 1) % m2]
			if a == null or b == null:
				newpos[k] = lat_pos[cells[k]]
			else:
				newpos[k] = (a + b) * 0.5
	for k in m2:
		var li: int = cells[k]
		if lat_alive[li] != 2:
			lat_pos[li] = newpos[k]
			lat_alive[li] = 2
	var last := m2 if closed else m2 - 1
	for k in last:
		var a: int = cells[k]
		var b: int = cells[(k + 1) % m2]
		if a == b:
			continue
		var key := _ckey(a, b)
		var fl := 0
		for tr in tunnels:
			if ts[k] >= tr[0] and ts[k] <= tr[1]:
				fl = 2
		if claims.has(key):
			if claims[key][2] <= cls:
				continue
		else:
			claim_order.append(key)
		claims[key] = [a, b, cls, label, fl]

# ---------------------------------------------------------------- Knoten
func _decide_nodes() -> void:
	for j in ny:
		for i in nx:
			var li := j * nx + i
			var p := lat_pos[li]
			var keep := false
			if lat_alive[li] == 2:
				keep = true
			else:
				keep = _keep_node(i, j, p, lat_dist[li])
			if keep:
				lat_node[li] = gpos.size()
				gpos.append(p)
				gmajor.append(0)
			else:
				lat_alive[li] = 0

func _keep_node(i: int, j: int, p: Vector2, d: int) -> bool:
	var dd: Dictionary = w.districts[d]
	var style: String = dd["style"]
	var main := (i % 4 == 0) or (j % 4 == 0)
	var lu: String = w.landuse(p)
	if lu == "water" or lu == "airport" or lu == "messe" or lu == "stadium":
		return false
	if w.river_distance(p) < 25.0:
		return false
	if lu == "rail":
		return main and (i % 4 == 0)
	if lu == "forest":
		return main and hashf(i, j, 31) < 0.85
	if lu == "park":
		return main
	if style == "land":
		return (i % 8 == 0) or (j % 8 == 0)
	if main:
		return true
	return hashf(i, j, 17) >= NODE_DROP.get(style, 0.1)

# ---------------------------------------------------------------- Kanten
func _add_edge(a: int, b: int, cls: int, fl: int, name_idx: int, num: int) -> void:
	ea.append(a); eb.append(b); ecls.append(cls); eflags.append(fl); ename.append(name_idx); enum_.append(num)
	if cls <= CLS_HAUPT or cls == CLS_LAND:
		gmajor[a] = max(gmajor[a], 2 if cls == CLS_BUNDES else 1)
		gmajor[b] = max(gmajor[b], 2 if cls == CLS_BUNDES else 1)

func _name_idx(label: String) -> int:
	if name_cache.has(label):
		return name_cache[label]
	names.append(label)
	name_cache[label] = names.size() - 1
	return names.size() - 1

func _street_name(orient: int, line: int, d: int, cls: int) -> int:
	var key := "%d_%d_%d" % [orient, line, d]
	if name_cache.has(key):
		return name_cache[key]
	var sn: Dictionary = cfg["street_names"]
	var stems: Array = sn["stems"]
	var style: String = w.districts[d]["style"]
	var suffixes: Array = sn["suffix_side"]
	if cls <= CLS_HAUPT or cls == CLS_LAND:
		suffixes = sn["suffix_main"]
	elif style == "altstadt":
		suffixes = sn["suffix_old"]
	elif style == "industrie" or style == "gewerbe":
		suffixes = sn["suffix_ind"]
	var label := ""
	for attempt in 40:
		var stem: String = stems[int(hashf(line + orient * 977, d, 100 + attempt) * stems.size()) % stems.size()]
		var suf: String = suffixes[int(hashf(line, d + orient * 131, 200 + attempt) * suffixes.size()) % suffixes.size()]
		if SPACED_STEMS.has(stem):
			label = stem + " " + suf.capitalize()
		else:
			label = stem + suf
		if style == "land" and cls == CLS_LAND:
			label = "Kreisstraße BA %d" % (1 + (line * 7 + orient * 3 + attempt) % 60)
		if not used_names.has(label):
			break
	used_names[label] = true
	names.append(label)
	name_cache[key] = names.size() - 1
	return names.size() - 1

func _build_edges() -> void:
	# 1) Magistralen (beanspruchte Kanten)
	for key in claim_order:
		var c: Array = claims[key]
		var a: int = lat_node[c[0]]
		var b: int = lat_node[c[1]]
		if a < 0 or b < 0:
			continue
		var fl: int = c[4]
		if fl == 0 and w.segment_crosses_river(gpos[a], gpos[b]):
			fl = 1
		_add_edge(a, b, c[2], fl, _name_idx(c[3]), 1 + (int(c[0]) % 23) * 6)
	# 2) Rasterkanten
	var center := Vector2.ZERO
	for j in ny:
		for i in nx:
			var li := j * nx + i
			if lat_node[li] < 0:
				continue
			for dir in 2:
				var i2 := i + (1 if dir == 0 else 0)
				var j2 := j + (0 if dir == 0 else 1)
				if i2 >= nx or j2 >= ny:
					continue
				var lj := j2 * nx + i2
				if lat_node[lj] < 0:
					continue
				if claims.has(_ckey(li, lj)):
					continue
				var pa := lat_pos[li]
				var pb := lat_pos[lj]
				var mid := (pa + pb) * 0.5
				var d: int = w.district_at(mid)
				var style: String = w.districts[d]["style"]
				var line := j if dir == 0 else i
				var main := line % 4 == 0
				var lu: String = w.landuse(mid)
				if lu == "water" or lu == "airport" or lu == "messe" or lu == "stadium":
					continue
				var fl := 0
				if w.segment_crosses_river(pa, pb):
					if not main:
						continue
					fl = 1
				if lu == "rail":
					if not main:
						continue
					fl = 1
				var cls := CLS_WOHN
				if main and style == "land" and not w.in_city(mid) and hashf(line + dir * 500, (i if dir == 0 else j) / 5, 77) < 0.38:
					continue
				if main:
					cls = CLS_LAND if (style == "land" or lu == "forest") else CLS_HAUPT
				else:
					if lu == "forest" or lu == "park":
						continue
					if hashf(li, lj, 53) < EDGE_DROP.get(style, 0.1):
						continue
					if style == "altstadt" and mid.distance_to(center) < 420.0:
						cls = CLS_FUSS
					elif style == "industrie" or style == "gewerbe" or style == "sonder":
						cls = CLS_NEBEN if line % 2 == 0 else CLS_ZUFAHRT
					else:
						cls = CLS_NEBEN if line % 2 == 0 else CLS_WOHN
				var along := i if dir == 0 else j
				_add_edge(lat_node[li], lat_node[lj], cls, fl, _street_name(dir, line, d, cls), 1 + (along % 13) * 12)

# ---------------------------------------------------------------- Autobahn
func _mkey(p: Vector2) -> int:
	return int(floor((p.x + 20000.0) / 300.0)) * 4096 + int(floor((p.y + 20000.0) / 300.0))

func _nearest_major(p: Vector2, radius: float) -> int:
	var best := -1
	var bd := radius
	var cx := int(floor((p.x + 20000.0) / 300.0))
	var cy := int(floor((p.y + 20000.0) / 300.0))
	var rr := int(ceil(radius / 300.0))
	for dx in range(-rr, rr + 1):
		for dy in range(-rr, rr + 1):
			var key := (cx + dx) * 4096 + (cy + dy)
			if not major_grid.has(key):
				continue
			for n in major_grid[key]:
				var d := p.distance_to(gpos[n])
				var eff := d - (60.0 if gmajor[n] == 2 else 0.0)
				if eff < bd:
					bd = eff
					best = n
	return best

func _build_autobahnen() -> void:
	var lattice_nodes := gpos.size()
	for n in lattice_nodes:
		if gmajor[n] > 0:
			var key := _mkey(gpos[n])
			if not major_grid.has(key):
				major_grid[key] = []
			major_grid[key].append(n)
	var spacing: float = cfg.get("junction_spacing", 2200)
	var b: Array = cfg["bounds"]
	var ring_nodes: Array = []
	for ab in cfg.get("autobahnen", []):
		var samples: PackedVector2Array
		var closed: bool = ab.get("ring", false)
		if closed:
			samples = _ellipse(ab["a"], ab["b"], 240.0)
		else:
			samples = _smooth(ab["points"], 240.0)
		var name_idx := _name_idx(ab["name"])
		var chain: Array = []
		for p in samples:
			var reuse := -1
			if not closed:
				for rn in ring_nodes:
					if gpos[rn].distance_to(p) < 190.0:
						reuse = rn
						break
			if reuse >= 0:
				if chain.size() == 0 or chain[chain.size() - 1] != reuse:
					chain.append(reuse)
			else:
				gpos.append(p)
				gmajor.append(0)
				chain.append(gpos.size() - 1)
		if closed:
			ring_nodes = chain.duplicate()
		var m := chain.size()
		var last := m if closed else m - 1
		for k in last:
			var a: int = chain[k]
			var c: int = chain[(k + 1) % m]
			if a != c:
				_add_edge(a, c, CLS_AUTOBAHN, 0, name_idx, 0)
		# Anschlussstellen
		var since := spacing * 0.6
		var ramp_idx := _name_idx("Anschlussstelle " + String(ab["name"]))
		for k in m:
			var an: int = chain[k]
			var p: Vector2 = gpos[an]
			var at_end := (not closed) and (k == 0 or k == m - 1)
			var inside: bool = p.x > b[0] + 400 and p.x < b[2] - 400 and p.y > b[1] + 400 and p.y < b[3] - 400
			since += 240.0
			var cand := _nearest_major(p, 520.0 if at_end else 260.0)
			if cand < 0 or cand >= lattice_nodes:
				continue
			var want := false
			if at_end and inside and not ring_nodes.has(an):
				want = true
			elif gmajor[cand] == 2 and since >= 700.0:
				want = true
			elif since >= spacing:
				want = true
			if want:
				_add_edge(an, cand, CLS_RAMPE, 0, ramp_idx, 0)
				since = 0.0
				var d: int = w.district_at(gpos[cand])
				junctions.append({"pos": gpos[cand], "name": "AS %s" % w.districts[d]["name"], "ref": ab["name"]})

# ---------------------------------------------------------------- Abschluss
func _finalize() -> void:
	var n := gpos.size()
	var adj: Array = []
	adj.resize(n)
	for i in n:
		adj[i] = PackedInt32Array()
	for e in ea.size():
		adj[ea[e]].append(e)
		adj[eb[e]].append(e)
	# größte Zusammenhangskomponente
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var best_c := -1
	var best_n := 0
	var cc := 0
	for s in n:
		if comp[s] >= 0:
			continue
		var stack := [s]
		comp[s] = cc
		var cnt := 0
		while stack.size() > 0:
			var u: int = stack.pop_back()
			cnt += 1
			for e in adj[u]:
				var v: int = eb[e] if ea[e] == u else ea[e]
				if comp[v] < 0:
					comp[v] = cc
					stack.append(v)
		if cnt > best_n:
			best_n = cnt
			best_c = cc
		cc += 1
	var remap := PackedInt32Array()
	remap.resize(n)
	remap.fill(-1)
	w.node_pos = PackedVector2Array()
	for i in n:
		if comp[i] == best_c and adj[i].size() > 0:
			remap[i] = w.node_pos.size()
			w.node_pos.append(gpos[i])
	var nn: int = w.node_pos.size()
	w.node_edges = []
	w.node_edges.resize(nn)
	for i in nn:
		w.node_edges[i] = PackedInt32Array()
	w.edge_a = PackedInt32Array(); w.edge_b = PackedInt32Array(); w.edge_len = PackedFloat32Array()
	w.edge_cls = PackedByteArray(); w.edge_flags = PackedByteArray(); w.edge_name = PackedInt32Array()
	w.edge_num = PackedInt32Array(); w.edge_dist = PackedByteArray()
	var seen := {}
	for e in ea.size():
		var a := remap[ea[e]]
		var b2 := remap[eb[e]]
		if a < 0 or b2 < 0 or a == b2:
			continue
		var key: int = (mini(a, b2) << 24) | maxi(a, b2)
		if seen.has(key):
			continue
		seen[key] = true
		var idx: int = w.edge_a.size()
		w.edge_a.append(a); w.edge_b.append(b2)
		var pa: Vector2 = w.node_pos[a]
		var pb: Vector2 = w.node_pos[b2]
		w.edge_len.append(max(5.0, pa.distance_to(pb)))
		w.edge_cls.append(ecls[e]); w.edge_flags.append(eflags[e]); w.edge_name.append(ename[e]); w.edge_num.append(enum_[e])
		w.edge_dist.append(w.district_at((pa + pb) * 0.5))
		w.node_edges[a].append(idx)
		w.node_edges[b2].append(idx)
	w.names = names
	w.junctions = junctions
	# Knotenmerkmale: Ampeln und Kreisverkehre
	w.node_flags = PackedByteArray()
	w.node_flags.resize(nn)
	for i in nn:
		var majors := 0
		var total: int = w.node_edges[i].size()
		var has_ab := false
		for e in w.node_edges[i]:
			var c: int = w.edge_cls[e]
			if c == CLS_BUNDES or c == CLS_HAUPT:
				majors += 1
			if c == CLS_AUTOBAHN:
				has_ab = true
		if has_ab:
			continue
		var p: Vector2 = w.node_pos[i]
		var style: String = w.districts[w.district_at(p)]["style"]
		var dense := style in ["altstadt", "zentrum", "wohn_dicht", "wohn", "industrie", "gewerbe"]
		if majors >= 3 and dense:
			w.node_flags[i] = 1
		elif majors >= 2 and total >= 4 and dense and hashf(i, 3, 5) < 0.35:
			w.node_flags[i] = 1
		elif majors >= 3 and total >= 4 and hashf(i, 9, 2) < 0.45:
			w.node_flags[i] = 2
