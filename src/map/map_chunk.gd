extends Node2D
## Ein Karten-Chunk (1 km²): zeichnet Straßen in der passenden Detailstufe und
## – bei hoher Zoomstufe – Gebäude. Nicht sichtbare Chunks werden ausgeblendet.

const Buildings = preload("res://src/map/buildings.gd")

const WIDTH_M := [24.0, 9.0, 17.0, 12.0, 8.5, 6.5, 8.5, 6.0, 6.0]
const MIN_PX := [3.4, 1.4, 2.6, 1.7, 1.1, 0.9, 1.3, 0.9, 0.9]
const FILL := [Color("#c08a3e"), Color("#a98a52"), Color("#c9b672"), Color("#9aa1a8"), Color("#6c737b"), Color("#545a61"), Color("#8f9483"), Color("#7d7468"), Color("#5a5d68")]
const CASING := Color("#15181b")
const ORDER := [7, 8, 5, 4, 6, 3, 1, 2, 0]

var chunk_idx := 0
var lod := -1
var zoom_bucket := -999
var zoom := 0.1
var seg: Array = []         # je Straßenklasse PackedVector2Array
var seg_special: Array = [] # Brücken / Tunnel
var marks: Array = []       # [pos, typ] Ampel/Kreisverkehr
var bld: Dictionary = {}
var want_buildings := false
var aa := true

func setup(idx: int) -> void:
	chunk_idx = idx
	seg.resize(9)
	for i in 9:
		seg[i] = PackedVector2Array()
	var tun := PackedVector2Array()
	var bri := PackedVector2Array()
	var seen := {}
	for e in World.chunk_edges[idx]:
		var a: Vector2 = World.node_pos[World.edge_a[e]]
		var b: Vector2 = World.node_pos[World.edge_b[e]]
		var c: int = World.edge_cls[e]
		if World.edge_flags[e] == 2:
			tun.append(a); tun.append(b)
		else:
			seg[c].append(a); seg[c].append(b)
			if World.edge_flags[e] == 1:
				bri.append(a); bri.append(b)
		for n in [World.edge_a[e], World.edge_b[e]]:
			if World.node_flags[n] != 0 and not seen.has(n):
				seen[n] = true
				marks.append([World.node_pos[n], World.node_flags[n]])
	seg_special = [bri, tun]

func has_content() -> bool:
	return not World.chunk_edges[chunk_idx].is_empty()

func update_view(new_lod: int, z: float, buildings: bool, antialias: bool) -> void:
	var bucket := int(round(log(z) / log(1.18)))
	if new_lod != lod or bucket != zoom_bucket or buildings != want_buildings or antialias != aa:
		lod = new_lod
		zoom_bucket = bucket
		zoom = z
		want_buildings = buildings
		aa = antialias
		queue_redraw()

func needs_buildings() -> bool:
	return want_buildings and bld.is_empty()

func generate_buildings() -> void:
	bld = Buildings.build_chunk(chunk_idx)
	queue_redraw()

func drop_buildings() -> void:
	bld = {}

func _visible_class(c: int) -> bool:
	match lod:
		0: return c == 0 or c == 2
		1: return c == 0 or c == 2 or c == 3 or c == 6
		2: return c != 5 and c != 7 and c != 8
		_: return true

func _w(c: int) -> float:
	return max(WIDTH_M[c], MIN_PX[c] / zoom)

func _draw() -> void:
	if lod < 0:
		return
	if want_buildings and not bld.is_empty() and bld["pts"].size() > 0:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), bld["idx"], bld["pts"], bld["cols"])
		if zoom > 1.1:
			draw_multiline(bld["outline"], Color("#23262a"), -1.0)
	var casing := zoom >= 0.22
	if casing:
		for c in ORDER:
			if _visible_class(c) and seg[c].size() > 0:
				draw_multiline(seg[c], CASING, _w(c) + 2.2 / zoom, aa)
		if seg_special[0].size() > 0:
			draw_multiline(seg_special[0], Color("#0d0f11"), 14.0 + 5.0 / zoom, aa)
	for c in ORDER:
		if _visible_class(c) and seg[c].size() > 0:
			var col: Color = FILL[c]
			if lod <= 1 and c == 3:
				col = col.darkened(0.35)
			draw_multiline(seg[c], col, _w(c), aa)
	if seg_special[1].size() > 0 and lod >= 1:
		draw_multiline(seg_special[1], Color(0.79, 0.71, 0.45, 0.35), _w(2), aa)
		draw_multiline(seg_special[1], Color("#15181b"), -1.0)
	if zoom >= 1.0:
		for m in marks:
			if m[1] == 2:
				draw_circle(m[0], 11.0, Color("#757c84"))
				draw_circle(m[0], 5.0, Color("#2d3b30"))
			else:
				draw_circle(m[0] + Vector2(7, -7), 2.2, Color("#c83d3d"))
				draw_circle(m[0] + Vector2(7, -2.5), 2.2, Color("#4c9868"))
