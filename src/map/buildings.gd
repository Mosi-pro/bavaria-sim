extends RefCounted
## Prozedurale Gebäudeumrisse je Karten-Chunk (wird nur bei hoher Zoomstufe erzeugt).

const STYLE := {
	# [w_min, w_max, d_min, d_max, lücke, abstand, belegung, farbe]
	"altstadt":   [13.0, 26.0, 13.0, 19.0, 1.0, 2.5, 0.96, Color("#47443d")],
	"zentrum":    [26.0, 58.0, 20.0, 32.0, 4.0, 4.0, 0.92, Color("#444951")],
	"wohn_dicht": [20.0, 44.0, 13.0, 17.0, 5.0, 4.0, 0.9, Color("#3e4349")],
	"wohn":       [12.0, 24.0, 10.0, 14.0, 8.0, 6.0, 0.82, Color("#3c4147")],
	"vorstadt":   [9.0, 14.0, 9.0, 12.0, 11.0, 8.0, 0.72, Color("#3b4046")],
	"dorf":       [10.0, 18.0, 9.0, 13.0, 10.0, 7.0, 0.7, Color("#403f3b")],
	"wald":       [9.0, 14.0, 9.0, 12.0, 14.0, 9.0, 0.5, Color("#3b4046")],
	"industrie":  [45.0, 105.0, 32.0, 65.0, 16.0, 12.0, 0.62, Color("#3c3c47")],
	"gewerbe":    [32.0, 70.0, 24.0, 44.0, 13.0, 10.0, 0.66, Color("#3d4048")],
	"sonder":     [40.0, 80.0, 28.0, 46.0, 20.0, 12.0, 0.3, Color("#404550")],
	"land":       [14.0, 24.0, 10.0, 14.0, 40.0, 14.0, 0.04, Color("#403f3b")],
}
const ROAD_HALF := [13.0, 5.0, 9.0, 6.5, 4.5, 3.5, 4.5, 3.0, 3.0]

static func hashf(a: int, b: int, c: int) -> float:
	var h := (a * 374761393 + b * 668265263 + c * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0

static func build_chunk(chunk_idx: int) -> Dictionary:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var outline := PackedVector2Array()
	var edges: PackedInt32Array = World.chunk_edges[chunk_idx]
	for e in edges:
		var cls: int = World.edge_cls[e]
		if cls <= World.CLS_RAMPE or World.edge_flags[e] != 0:
			continue
		var d: int = World.edge_dist[e]
		var style: String = World.districts[d]["style"]
		var s: Array = STYLE.get(style, STYLE["wohn"])
		var a: Vector2 = World.node_pos[World.edge_a[e]]
		var b: Vector2 = World.node_pos[World.edge_b[e]]
		var length: float = World.edge_len[e]
		var dir := (b - a) / length
		var nrm := Vector2(-dir.y, dir.x)
		var half: float = ROAD_HALF[cls]
		for side in 2:
			var sgn := 1.0 if side == 0 else -1.0
			var pos := 16.0 + hashf(e, side, 1) * 6.0
			var k := 0
			while pos < length - 16.0 and k < 40:
				k += 1
				var w: float = lerpf(s[0], s[1], hashf(e, k, side + 10))
				var dep: float = lerpf(s[2], s[3], hashf(e, k, side + 20))
				if pos + w > length - 14.0:
					break
				var occupied: bool = hashf(e, k, side + 30) < float(s[6])
				var c0: Vector2 = a + dir * (pos + w * 0.5) + nrm * sgn * (half + float(s[5]) + dep * 0.5)
				pos += w + float(s[4]) * (0.6 + hashf(e, k, side + 40))
				if not occupied:
					continue
				var lu := World.landuse(c0)
				if lu == "water" or lu == "park" or lu == "forest" or lu == "rail" or lu == "stadium" or lu == "airport":
					continue
				if _too_close(c0, e, dep * 0.5 + 5.0):
					continue
				var hx := dir * (w * 0.5)
				var hy := nrm * (dep * 0.5)
				var base := pts.size()
				pts.append(c0 - hx - hy); pts.append(c0 + hx - hy); pts.append(c0 + hx + hy); pts.append(c0 - hx + hy)
				var col: Color = s[7]
				col = col.lightened(hashf(e, k, side + 50) * 0.07)
				for q in 4:
					cols.append(col)
				idx.append(base); idx.append(base + 1); idx.append(base + 2)
				idx.append(base); idx.append(base + 2); idx.append(base + 3)
				for q in 4:
					outline.append(pts[base + q])
					outline.append(pts[base + (q + 1) % 4])
	return {"pts": pts, "cols": cols, "idx": idx, "outline": outline}

static func _too_close(p: Vector2, own: int, limit: float) -> bool:
	var gx := clampi(int((p.x - World.bounds.position.x) / World.GRID), 0, World.gw - 1)
	var gy := clampi(int((p.y - World.bounds.position.y) / World.GRID), 0, World.gh - 1)
	for e in World.grid_edges[gy * World.gw + gx]:
		if e == own:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, World.node_pos[World.edge_a[e]], World.node_pos[World.edge_b[e]])
		if p.distance_to(q) < limit + ROAD_HALF[World.edge_cls[e]]:
			return true
	return false
