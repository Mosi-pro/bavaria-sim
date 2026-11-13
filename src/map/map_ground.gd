extends Node2D
## Statischer Kartengrund: Umland, Stadtfläche, Nutzungsflächen, Gewässer, Bahn, Flughafen.

const COL := {
	"water": Color("#1f3d57"), "forest": Color("#1f3327"), "park": Color("#263b2c"), "airport": Color("#2b2f36"),
	"rail": Color("#2c2a2e"), "messe": Color("#343842"), "stadium": Color("#3a4a3d"), "campus": Color("#2f3238"),
}
const STYLE_TINT := {
	"altstadt": Color("#322f2b"), "zentrum": Color("#2e3136"), "wohn_dicht": Color("#2b2e32"), "wohn": Color("#292c30"),
	"vorstadt": Color("#272b2c"), "industrie": Color("#2c2a31"), "gewerbe": Color("#2b2b30"), "sonder": Color("#282b30"),
	"wald": Color("#252b28"), "dorf": Color("#2a2b29"),
}
var border_lines := PackedVector2Array()
var show_borders := true

func _ready() -> void:
	_compute_borders()

func _compute_borders() -> void:
	var step := 250.0
	var b: Rect2 = World.bounds
	var nx := int(b.size.x / step)
	var ny := int(b.size.y / step)
	var grid := PackedInt32Array()
	grid.resize(nx * ny)
	for j in ny:
		for i in nx:
			grid[j * nx + i] = World.district_at(b.position + Vector2((i + 0.5) * step, (j + 0.5) * step))
	for j in ny:
		for i in nx:
			var d := grid[j * nx + i]
			var p := b.position + Vector2(i * step, j * step)
			if i + 1 < nx and grid[j * nx + i + 1] != d:
				border_lines.append(p + Vector2(step, 0)); border_lines.append(p + Vector2(step, step))
			if j + 1 < ny and grid[(j + 1) * nx + i] != d:
				border_lines.append(p + Vector2(0, step)); border_lines.append(p + Vector2(step, step))
	_cells = grid
	_nx = nx
	_ny = ny

var _cells := PackedInt32Array()
var _nx := 0
var _ny := 0

func _draw() -> void:
	var b: Rect2 = World.bounds
	draw_rect(b.grow(6000.0), Color("#191d1b"))
	draw_rect(b, Color("#1e2421"))
	# Stadtteilflächen (zusammengefasste Zeilenabschnitte)
	var step := 250.0
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for j in _ny:
		var i := 0
		while i < _nx:
			var d := _cells[j * _nx + i]
			var i0 := i
			while i < _nx and _cells[j * _nx + i] == d:
				i += 1
			var style: String = World.districts[d]["style"]
			if not STYLE_TINT.has(style):
				continue
			var p0 := b.position + Vector2(i0 * step, j * step)
			var p1 := b.position + Vector2(i * step, (j + 1) * step)
			var base := pts.size()
			pts.append(p0); pts.append(Vector2(p1.x, p0.y)); pts.append(p1); pts.append(Vector2(p0.x, p1.y))
			for q in 4:
				cols.append(STYLE_TINT[style])
			idx.append(base); idx.append(base + 1); idx.append(base + 2); idx.append(base); idx.append(base + 2); idx.append(base + 3)
	if pts.size() > 0:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
	for a in World.areas:
		if a["kind"] == "water":
			continue
		draw_colored_polygon(World.area_polygon(a), COL.get(a["kind"], Color("#2a2e32")))
	for r in World.cfg.get("runways", []):
		var a := {"c": Vector2(r["c"][0], r["c"][1]), "rect": true, "rx": r["w"] * 0.5, "ry": r["h"] * 0.5, "cs": cos(deg_to_rad(r["rot"])), "sn": sin(deg_to_rad(r["rot"]))}
		draw_colored_polygon(World.area_polygon(a), Color("#4a4f57"))
	for r in World.rivers:
		draw_polyline(r["pts"], COL["water"], r["width"], true)
	for a in World.areas:
		if a["kind"] == "water":
			draw_colored_polygon(World.area_polygon(a), COL["water"])
	for rail in World.cfg.get("rails", []):
		var line := PackedVector2Array()
		for p in rail:
			line.append(Vector2(p[0], p[1]))
		draw_polyline(line, Color("#4b4a50"), 14.0, true)
		draw_polyline(line, Color("#8a8a92"), -1.0)
	if show_borders:
		draw_multiline(border_lines, Color(0.64, 0.68, 0.71, 0.2), -1.0)
	var outline := World.city_outline()
	outline.append(outline[0])
	draw_polyline(outline, Color(0.64, 0.68, 0.71, 0.5), -1.0)
