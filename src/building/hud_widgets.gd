extends Control
## Kleine HUD-Bausteine der begehbaren Leitstelle: Lageplan (Minikarte) und Logo.

var kind := "minimap"
var building: Node = null

const ROOMS := [
	[Rect2(0, 0, 36, 18), "Leitstellenraum"], [Rect2(-8, -2.6, 44, 2.6), ""], [Rect2(-8, 0, 8, 10), "Foyer"],
	[Rect2(-8, -9, 8, 6.4), "Umkleide"], [Rect2(0, -9, 10, 6.4), "Pause"], [Rect2(10, -9, 6, 6.4), "Bespr."],
	[Rect2(16, -9, 3, 6.4), "WC"], [Rect2(19, -9, 3, 6.4), "WC"], [Rect2(22, -9, 7, 6.4), "Technik"], [Rect2(29, -9, 7, 6.4), "SF-Büro"],
]
const AREA := Rect2(-9, -10, 46, 29)

func _process(_d: float) -> void:
	if kind == "minimap" and is_visible_in_tree():
		queue_redraw()

func _map(p: Vector2, r: Rect2) -> Vector2:
	var s := minf(r.size.x / AREA.size.x, r.size.y / AREA.size.y)
	var off := r.position + (r.size - AREA.size * s) * 0.5
	return off + (p - AREA.position) * s

func _draw() -> void:
	if kind == "logo":
		for i in 3:
			var x := 4.0 + i * 9.0
			var pts := PackedVector2Array([Vector2(x + 10, 2), Vector2(x + 16, 2), Vector2(x + 6, size.y - 2), Vector2(x, size.y - 2)])
			draw_colored_polygon(pts, [Color(0.12, 0.32, 0.72), Color(0.2, 0.45, 0.85), Color(0.45, 0.65, 0.95)][i])
		return
	var r := Rect2(Vector2(6, 6), size - Vector2(12, 26))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.1, 0.86))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.37, 0.4, 0.8), false, 1.0)
	var font := ThemeDB.fallback_font
	for room in ROOMS:
		var rr: Rect2 = room[0]
		var a := _map(rr.position, r)
		var b := _map(rr.end, r)
		draw_rect(Rect2(a, b - a), Color(0.2, 0.22, 0.24))
		draw_rect(Rect2(a, b - a), Color(0.42, 0.45, 0.48), false, 1.0)
		if room[1] != "" and b.x - a.x > 26:
			draw_string(font, a + Vector2(3, 11), room[1], HORIZONTAL_ALIGNMENT_LEFT, b.x - a.x - 4, 9, Color(0.6, 0.63, 0.66))
	if building == null or building.layout == null:
		return
	# Arbeitsplätze (grün frei, rot belegt)
	for id in building.layout.seats:
		var sd: Dictionary = building.layout.seats[id]
		if sd["kind"] != "desk":
			continue
		var p3: Vector3 = sd["pos"]
		var used: bool = Presence.owner_of(id) != 0 or building._npc_at(id) != ""
		draw_circle(_map(Vector2(p3.x, p3.z), r), 2.2, Color(0.85, 0.3, 0.25) if used else Color(0.3, 0.8, 0.4))
	# Mitspieler
	for pid in Presence.poses:
		if pid == Presence.me():
			continue
		var pp: Vector3 = Presence.poses[pid]["p"]
		draw_circle(_map(Vector2(pp.x, pp.z), r), 3.0, Color(0.95, 0.8, 0.3))
	# eigener Standort als Pfeil
	var me: Vector3 = building.body.position
	var c := _map(Vector2(me.x, me.z), r)
	var yaw: float = building.yaw
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([c + fwd * 9.0, c - fwd * 5.0 + side * 5.0, c - fwd * 2.0, c - fwd * 5.0 - side * 5.0]), Color(0.25, 0.55, 1.0))
	draw_string(font, Vector2(0, size.y - 6), "Leitstelle Bavaria", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.85, 0.87, 0.9))
	draw_string(font, Vector2(size.x * 0.5 - 4, 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.87, 0.9))
