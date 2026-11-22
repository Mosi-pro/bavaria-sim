extends RefCounted
## Grundriss und Ausstattung der begehbaren Integrierten Leitstelle Bavaria (fiktiv).
## Architektonisch angelehnt an eine moderne deutsche Großleitstelle: langer, hoher
## Leitstellenraum mit Holzverkleidung, Rasterdecke mit Lichtfeldern, Glasgalerie über der
## Fensterfront, Großbildwand an der Stirnseite und geschwungenen Disponententischen
## mit Monitorreihen, Signalleuchten und Platznummern.
##
## Koordinaten in Metern: X nach Osten (Großbildwand bei X = 36), Z nach Süden (Fensterfront
## bei Z = 18), Y nach oben. Disponenten blicken nach +X.

const Geo = preload("res://src/building/geo.gd")
const MATS = preload("res://src/building/materials.gd")

const HALL := Rect2(0, 0, 36, 18)
const HALL_H := 5.4
const ROOM_H := 2.9
const GALLERY_Z := 14.0
const GALLERY_Y := 3.0
const BOUNDS := AABB(Vector3(-9, -1, -10), Vector3(46, 8, 29))

var g: Geo
var root: Node3D
var seats := {}          # id -> {pos, yaw, kind, name, eye, look, stand, screens, plate}
var seat_order: Array = []
var doors := {}          # id -> {hinge, open_angle, name}
var labels := {}         # Name -> Label3D (z. B. Großbildwand)
var sound_spots := {}    # Name -> Array[Vector3]
var leds: Array = []     # blinkende LEDs im Technikraum
var door_gaps: Array = []  # [Mitte, Richtung, Breite] aller Türöffnungen (für Sockelleisten)
var hotplates: Array = []
var spawn := Vector3(-4.0, 0.0, 6.5)
var spawn_yaw := -PI / 2
var quality := 1

func build(parent: Node3D, q: int) -> void:
	root = parent
	quality = q
	g = Geo.new(root)
	_shell()
	_hall()
	_gallery()
	_videowall()
	_corridor_and_foyer()
	_break_room()
	_meeting_room()
	_toilets()
	_server_room()
	_office()
	_lockers()
	_outside()
	_lights()
	g.commit()

# ------------------------------------------------------------------ Hilfen
func _label(text: String, pos: Vector3, yaw: float, size := 0.006, col := Color(0.15, 0.15, 0.16), font_size := 48, max_w := 0.0, max_h := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size
	l.font_size = font_size
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation.y = yaw
	l.double_sided = false
	l.shaded = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if max_w > 0.0:
		l.set_meta("fit", Vector2(max_w, max_h))
		l.set_meta("max_px", size)
		fit_label(l)
	root.add_child(l)
	return l

## Schriftgröße so wählen, dass der Text in das vorgesehene Feld passt (nichts über die Ränder).
static func fit_label(l: Label3D) -> void:
	if not l.has_meta("fit"):
		return
	var box: Vector2 = l.get_meta("fit")
	var font: Font = ThemeDB.fallback_font
	var w := 1.0
	var lines := l.text.split("\n")
	for line in lines:
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x)
	var h := lines.size() * (font.get_height(l.font_size) + l.line_spacing)
	var px := float(l.get_meta("max_px"))
	px = minf(px, box.x / w)
	if box.y > 0.0:
		px = minf(px, box.y / h)
	l.pixel_size = px

func _sign(text: String, pos: Vector3, yaw: float) -> void:
	# Türschild: kleine Platte mit Beschriftung
	var t := Transform3D(Basis(Vector3.UP, yaw), pos)
	g.box_t("dark", t, Vector3(0.62, 0.14, 0.015))
	_label(text, pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.01), yaw, 0.0028, Color(0.95, 0.95, 0.95), 40, 0.56, 0.11)

func _area(meta: Dictionary, pos: Vector3, size: Vector3, yaw := 0.0) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 2
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	a.add_child(cs)
	a.position = pos
	a.rotation.y = yaw
	a.set_meta("ia", meta)
	root.add_child(a)
	return a

func _spot(name: String, p: Vector3) -> void:
	if not sound_spots.has(name):
		sound_spots[name] = []
	sound_spots[name].append(p)

## Sockelleiste (Quader von a nach b), an Türöffnungen unterbrochen.
func _plinth(a: Vector3, b: Vector3) -> void:
	var along_x := absf(b.x - a.x) >= absf(b.z - a.z)
	var lo := minf(a.x, b.x) if along_x else minf(a.z, b.z)
	var hi := maxf(a.x, b.x) if along_x else maxf(a.z, b.z)
	var other := (a.z + b.z) * 0.5 if along_x else (a.x + b.x) * 0.5
	var cuts: Array = []
	for gp in door_gaps:
		var c: Vector2 = gp[0]
		var d: Vector2 = gp[1]
		var half: float = float(gp[2]) * 0.5 + 0.07
		if along_x and absf(d.x) > 0.9 and absf(c.y - other) < 0.35:
			cuts.append([c.x - half, c.x + half])
		elif not along_x and absf(d.y) > 0.9 and absf(c.x - other) < 0.35:
			cuts.append([c.y - half, c.y + half])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var cur := lo
	for ct in cuts + [[hi, hi]]:
		var e := minf(float(ct[0]), hi)
		if e - cur > 0.02:
			if along_x:
				g.block("plinth", Vector3(cur, a.y, a.z), Vector3(e, b.y, b.z))
			else:
				g.block("plinth", Vector3(a.x, a.y, cur), Vector3(b.x, b.y, e))
		cur = maxf(cur, float(ct[1]))

func _floor(mat: String, r: Rect2, y := 0.0) -> void:
	g.block(mat, Vector3(r.position.x, y - 0.06, r.position.y), Vector3(r.end.x, y, r.end.y))

func _ceiling(r: Rect2, h: float, mat := "ceiling") -> void:
	g.block(mat, Vector3(r.position.x, h, r.position.y), Vector3(r.end.x, h + 0.12, r.end.y))

## Tür (drehbar um das Scharnier) mit Rahmen. a/b: Wandverlauf, at: Abstand ab a.
func _door(id: String, name: String, a: Vector2, b: Vector2, at: float, w := 1.0, glass := false, swing := 1.0, double := false, interactive := true) -> void:
	var dir := (b - a).normalized()
	var rot := -atan2(dir.y, dir.x)
	var c := a + dir * at
	var basis := Basis(Vector3.UP, rot)
	# Zarge
	# (überdeckt die Wandkanten leicht – keine deckungsgleichen Flächen, kein Flackern)
	for s in [-1.0, 1.0]:
		var p: Vector2 = c + dir * (s * (w * 0.5 + 0.025))
		g.box("frame", Vector3(p.x, 1.082, p.y), Vector3(0.07, 2.16, 0.28), rot)
	g.box("frame", Vector3(c.x, 2.175, c.y), Vector3(w + 0.13, 0.07, 0.28), rot)
	door_gaps.append([c, dir, w])
	var leaves := [[-w * 0.5, w if not double else w * 0.5, 1.0]]
	if double:
		leaves = [[-w * 0.5, w * 0.5, 1.0], [w * 0.5, w * 0.5, -1.0]]
	var n := 0
	for lf in leaves:
		var hinge_off: float = lf[0]
		var lw: float = lf[1]
		var side: float = lf[2]
		var hinge := Node3D.new()
		var hp := c + dir * hinge_off
		hinge.position = Vector3(hp.x, 0.0, hp.y)
		hinge.basis = basis
		root.add_child(hinge)
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1 | 2
		hinge.add_child(body)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(lw - 0.01, 2.12, 0.045)
		mi.mesh = bm
		mi.material_override = MATS.get_mat("glass" if glass else "door")
		mi.position = Vector3(side * lw * 0.5, 1.07, 0)
		body.add_child(mi)
		if glass:
			for yy in [0.02, 2.1]:
				var fr := MeshInstance3D.new()
				var fm := BoxMesh.new()
				fm.size = Vector3(lw - 0.01, 0.06, 0.05)
				fr.mesh = fm
				fr.material_override = MATS.get_mat("frame")
				fr.position = Vector3(side * lw * 0.5, yy, 0)
				body.add_child(fr)
		var handle := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.14, 0.025, 0.12)
		handle.mesh = hm
		handle.material_override = MATS.get_mat("metal")
		handle.position = Vector3(side * (lw - 0.1), 1.02, 0)
		body.add_child(handle)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(lw - 0.02, 2.12, 0.06)
		cs.shape = sh
		cs.position = mi.position
		body.add_child(cs)
		body.set_meta("ia", {"kind": "door" if interactive else "info", "id": id, "name": name,
			"text": "Haupteingang – während des Dienstes nur mit Dienstausweis." if not interactive else ""})
		var key := id if n == 0 else id + "_b"
		doors[key] = {"hinge": hinge, "open_angle": swing * side * deg_to_rad(95.0), "group": id, "name": name}
		n += 1

## Disponentenarbeitsplatz (Bediener am Ursprung, Blick nach +X in lokalen Koordinaten):
## weiße, geschwungene Arbeitsplatte auf anthrazitfarbenen Schubladenblöcken,
## Monitorschiene mit 4 + 3 Bildschirmen an Halterungen, Telefon, Funkbedienteil, Stuhl.
func _workstation(id: String, nr: String, origin: Vector3, yaw: float) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), origin)
	var A := 0.98
	g.arc("desk_top", Vector3.ZERO, 0.66, 1.42, -A, A, 0.712, 0.745, 18, T)
	g.arc("desk_edge", Vector3.ZERO, 0.62, 0.66, -A, A, 0.7, 0.745, 18, T)
	g.arc("cabinet", Vector3.ZERO, 1.3, 1.4, -A, A, 0.08, 0.712, 18, T)
	g.arc("cabinet", Vector3.ZERO, 0.82, 1.3, 0.56, A, 0.08, 0.712, 5, T)
	g.arc("cabinet", Vector3.ZERO, 0.82, 1.3, -A, -0.56, 0.08, 0.712, 5, T)
	g.arc("plinth", Vector3.ZERO, 0.86, 1.37, -A, A, 0.0, 0.08, 18, T)
	for s in [-1.0, 1.0]:
		var a0: float = 0.6 if s > 0 else -0.94
		var a1: float = 0.94 if s > 0 else -0.6
		for yy in [0.3, 0.5]:
			g.arc("dark", Vector3.ZERO, 0.815, 0.821, a0, a1, yy, yy + 0.006, 4, T)
		for yy in [0.24, 0.44, 0.64]:
			g.arc("metal", Vector3.ZERO, 0.808, 0.818, a0 + 0.08, a1 - 0.08, yy, yy + 0.014, 3, T)
	# Monitorschiene mit Säulen
	for s in [-1.0, 1.0]:
		var a: float = s * 0.86
		g.cyl_t("metal", T * Transform3D(Basis(), Vector3(cos(a) * 1.37, 1.24, -sin(a) * 1.37)), 0.024, 1.0, 10)
	g.arc("metal", Vector3.ZERO, 1.36, 1.385, -0.88, 0.88, 1.2, 1.235, 14, T)
	g.arc("metal", Vector3.ZERO, 1.38, 1.405, -0.62, 0.62, 1.6, 1.632, 10, T)
	var screens := Node3D.new()
	screens.transform = T
	root.add_child(screens)
	# [Winkel, Radius, Höhe, Breite, Höhe, Inhalt]
	var mons := [[-0.69, 1.27, 1.03, 0.58, 0.35, "screen_c"], [-0.23, 1.27, 1.03, 0.58, 0.35, "screen_a"], [0.23, 1.27, 1.03, 0.58, 0.35, "screen_a"], [0.69, 1.27, 1.03, 0.58, 0.35, "screen_b"],
		[-0.46, 1.33, 1.43, 0.52, 0.31, "screen_b"], [0.0, 1.33, 1.43, 0.52, 0.31, "screen_a"], [0.46, 1.33, 1.43, 0.52, 0.31, "screen_c"]]
	for m in mons:
		var a: float = m[0]
		var r: float = m[1]
		var b := Basis(Vector3.UP, a - PI / 2) * Basis(Vector3.RIGHT, deg_to_rad(-5))
		var lt := Transform3D(b, Vector3(cos(a) * r, m[2], -sin(a) * r))
		g.box_t("bezel", T * lt, Vector3(m[3], m[4], 0.022))
		g.box_t("monitor_back", T * lt * Transform3D(Basis(), Vector3(0, 0, -0.025)), Vector3(m[3] * 0.6, m[4] * 0.6, 0.03))
		g.box_t("dark", T * lt * Transform3D(Basis(), Vector3(0, 0, -0.07)), Vector3(0.05, 0.05, 0.09))
		var sc := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(m[3] - 0.022, m[4] - 0.022)
		sc.mesh = qm
		sc.transform = lt * Transform3D(Basis(), Vector3(0, 0, 0.0115))
		sc.set_meta("on", m[5])
		sc.material_override = MATS.get_mat("screen_login")
		sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		screens.add_child(sc)
	# Tastatur, Maus, Telefon, Funkbedienteil (Touch), Schwanenhalsmikrofon, Tasse
	g.box_t("dark", T * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0.88, 0.755, 0.05)), Vector3(0.44, 0.018, 0.14))
	g.box_t("keys", T * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0.88, 0.765, 0.05)), Vector3(0.42, 0.004, 0.12))
	g.box_t("dark", T * Transform3D(Basis(), Vector3(0.88, 0.758, -0.34)), Vector3(0.1, 0.028, 0.062))
	var ta := 0.52
	var tb := Basis(Vector3.UP, ta - PI / 2) * Basis(Vector3.RIGHT, deg_to_rad(-62))
	var tpos := Vector3(cos(ta) * 1.04, 0.82, -sin(ta) * 1.04)
	g.box_t("dark", T * Transform3D(tb, tpos), Vector3(0.34, 0.24, 0.025))
	var tablet := MeshInstance3D.new()
	var tq := QuadMesh.new()
	tq.size = Vector2(0.31, 0.21)
	tablet.mesh = tq
	tablet.material_override = MATS.get_mat("screen_tablet")
	tablet.transform = T * Transform3D(tb, tpos) * Transform3D(Basis(), Vector3(0, 0, 0.0135))
	root.add_child(tablet)
	var pa := -0.58
	var pb := Basis(Vector3.UP, pa - PI / 2)
	var ppos := Vector3(cos(pa) * 1.0, 0.745, -sin(pa) * 1.0)
	g.box_t("dark", T * Transform3D(pb * Basis(Vector3.RIGHT, deg_to_rad(-12)), ppos + Vector3(0, 0.04, 0)), Vector3(0.22, 0.06, 0.24))
	g.box_t("black", T * Transform3D(pb, ppos + Vector3(0, 0.085, 0)), Vector3(0.05, 0.035, 0.22))
	g.box_t("screen_off", T * Transform3D(pb * Basis(Vector3.RIGHT, deg_to_rad(-30)), ppos + Vector3(0, 0.075, 0.06)), Vector3(0.12, 0.05, 0.005))
	g.cyl_t("black", T * Transform3D(Basis(Vector3.FORWARD, 0.35), Vector3(0.98, 0.9, 0.46)), 0.007, 0.34, 6)
	g.sphere("dark", T * Vector3(1.04, 1.06, 0.46), 0.018)
	if hash(id) % 3 == 0:
		g.cyl("cup", T * Vector3(0.95, 0.795, -0.62), 0.04, 0.1, 12)
	# Bürostuhl
	_chair(T * Transform3D(Basis(), Vector3(0.1, 0, 0)), true)
	# Kollision: Tisch als Segmente, Stuhl als Quader
	for i in 5:
		var a := lerpf(-A + 0.19, A - 0.19, float(i) / 4.0)
		var lp := Vector3(cos(a) * 1.02, 0.38, -sin(a) * 1.02)
		g.collider(T * lp, Vector3(0.8, 0.76, 0.42), yaw + a)
	g.collider(T * Vector3(0.1, 0.5, 0), Vector3(0.5, 1.0, 0.5), yaw)
	_area({"kind": "seat", "id": id}, T * Vector3(-0.15, 0.9, 0), Vector3(1.3, 1.8, 1.3), yaw)
	var plate := _label("", T * Vector3(1.39, 1.82, 0), yaw - PI / 2, 0.0026, Color(0.2, 0.75, 0.35), 36, 1.2, 0.12)
	seats[id] = {"pos": T * Vector3(0.1, 0, 0), "yaw": yaw, "kind": "desk", "name": "Platz " + nr, "nr": nr,
		"eye": T * Vector3(0.0, 1.22, 0), "look": T * Vector3(1.4, 1.1, 0), "stand": T * Vector3(-0.8, 0, 0),
		"screens": screens, "plate": plate}
	seat_order.append(id)
	_spot("keys", T * Vector3(0.8, 0.8, 0))

## Tischreihe aus mehreren Plätzen (entlang Z), verbunden durch Zwischenstücke mit
## weißen Lichtsäulen (Signalleuchte, Platznummern) wie im Vorbild.
func _desk_row(xc: float, z0: float, count: int, first_nr: int, prefix := "ws", title := "") -> void:
	var step := 2.9
	for i in count:
		var nr := first_nr + i
		var id := "%s%d" % [prefix, nr]
		_workstation(id, ("SF%d" % nr) if prefix == "sf" else str(nr), Vector3(xc, 0, z0 + i * step), 0.0)
		if prefix == "sf":
			seats[id]["name"] = "Schichtführung %d" % nr
	for i in count + 1:
		var zm := z0 + (i - 0.5) * step
		var inner := i > 0 and i < count
		if inner:
			# Verbindungsstück der Arbeitsplatte
			g.block("desk_top", Vector3(xc + 0.55, 0.712, zm - 0.36), Vector3(xc + 1.42, 0.745, zm + 0.36))
			g.block("cabinet", Vector3(xc + 0.62, 0.08, zm - 0.34), Vector3(xc + 1.38, 0.712, zm + 0.34), true)
			g.block("plinth", Vector3(xc + 0.66, 0.0, zm - 0.32), Vector3(xc + 1.34, 0.08, zm + 0.32))
		# weiße Lichtsäule mit LED-Band und Signalleuchte
		var zp := zm if inner else (z0 - 1.32 if i == 0 else z0 + (count - 1) * step + 1.32)
		var pp := Vector3(xc + 1.22, 0, zp)
		g.cyl("pillar", pp + Vector3(0, 1.05, 0), 0.13, 2.1, 20)
		g.cyl("pillar", pp + Vector3(0, 2.13, 0), 0.115, 0.06, 20)
		g.box("led_white", pp + Vector3(-0.128, 1.2, 0), Vector3(0.012, 1.1, 0.035))
		g.cyl("red", pp + Vector3(0, 2.24, 0), 0.06, 0.16, 16)
		g.cyl("dark", pp + Vector3(0, 2.16, 0), 0.07, 0.03, 16)
		g.collider_cyl(pp + Vector3(0, 1.05, 0), 0.14, 2.1)
		var left := ""
		var right := ""
		if i > 0:
			left = str(first_nr + i - 1)
		if i < count:
			right = str(first_nr + i)
		var txt := (left + "  " + right).strip_edges() if prefix == "ws" else "SF"
		_label(txt, pp + Vector3(-0.135, 1.92, 0), -PI / 2, 0.003, Color(0.15, 0.15, 0.17), 40, 0.22, 0.14)
	if title != "":
		_label(title, Vector3(xc + 1.45, 1.95, z0 + (count - 1) * step * 0.5), -PI / 2, 0.004, Color(0.2, 0.2, 0.22), 40, 2.0, 0.2)

func _chair(T: Transform3D, swivel: bool) -> void:
	if swivel:
		for i in 5:
			var a := TAU * i / 5.0
			g.box_t("dark", T * Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 0.15, 0.06, -sin(a) * 0.15)), Vector3(0.3, 0.035, 0.05))
			g.sphere("black", T * Vector3(cos(a) * 0.3, 0.03, -sin(a) * 0.3), 0.03)
		g.cyl_t("metal", T * Transform3D(Basis(), Vector3(0, 0.27, 0)), 0.03, 0.38, 8)
		g.box_t("chair", T * Transform3D(Basis(), Vector3(0.02, 0.49, 0)), Vector3(0.5, 0.09, 0.5))
		g.box_t("chair", T * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-8)), Vector3(-0.24, 0.84, 0)), Vector3(0.07, 0.62, 0.46))
		g.box_t("chair", T * Transform3D(Basis(), Vector3(-0.25, 1.2, 0)), Vector3(0.06, 0.14, 0.26))
		for s in [-1.0, 1.0]:
			g.box_t("dark", T * Transform3D(Basis(), Vector3(0.02, 0.66, s * 0.25)), Vector3(0.3, 0.035, 0.05))
			g.box_t("dark", T * Transform3D(Basis(), Vector3(-0.04, 0.58, s * 0.25)), Vector3(0.03, 0.16, 0.03))
	else:
		# Vierbeinstuhl (Pausen-/Besprechungsraum)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				g.box_t("metal", T * Transform3D(Basis(), Vector3(sx * 0.19, 0.22, sz * 0.19)), Vector3(0.025, 0.44, 0.025))
		g.box_t("fabric", T * Transform3D(Basis(), Vector3(0, 0.46, 0)), Vector3(0.44, 0.05, 0.44))
		g.box_t("fabric", T * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-6)), Vector3(-0.21, 0.75, 0)), Vector3(0.035, 0.5, 0.42))

## Sitzplatz ohne Arbeitsplatz (Stuhl, Sofa, Bank).
func _lounge_seat(id: String, name: String, pos: Vector3, yaw: float, chair := true, seat_h := 0.46, swivel := false) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), pos)
	if chair:
		_chair(T, swivel)
		g.collider(T * Vector3(0, 0.4, 0), Vector3(0.46, 0.8, 0.46), yaw)
	_area({"kind": "seat", "id": id}, T * Vector3(0, 0.7, 0), Vector3(0.7, 1.4, 0.7), yaw)
	seats[id] = {"pos": pos, "yaw": yaw, "kind": "lounge", "name": name, "seat_h": seat_h,
		"eye": T * Vector3(0.05, seat_h + 0.72, 0), "look": T * Vector3(2.0, seat_h + 0.6, 0), "stand": T * Vector3(0.75, 0, 0) if not chair else T * Vector3(-0.7, 0, 0)}
	seat_order.append(id)

func _plant(p: Vector3, h := 1.4) -> void:
	g.cyl("pot", p + Vector3(0, 0.25, 0), 0.24, 0.5, 12, 0.2)
	for i in 7:
		var a := TAU * i / 7.0
		g.sphere("plant", p + Vector3(cos(a) * 0.16, 0.5 + h * 0.45 + sin(i * 1.7) * 0.15, sin(a) * 0.16), 0.22, Vector3(1, 1.6, 1))
	g.sphere("plant", p + Vector3(0, 0.5 + h * 0.75, 0), 0.25, Vector3(1, 1.4, 1))
	g.collider_cyl(p + Vector3(0, 0.5, 0), 0.26, 1.0)

func _table(c: Vector3, size: Vector3, mat := "desk_top") -> void:
	g.box(mat, c + Vector3(0, size.y - 0.02, 0), Vector3(size.x, 0.04, size.z))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box("metal", c + Vector3(sx * (size.x * 0.5 - 0.06), size.y * 0.5 - 0.02, sz * (size.z * 0.5 - 0.06)), Vector3(0.04, size.y - 0.04, 0.04))
	g.collider(c + Vector3(0, size.y * 0.5, 0), Vector3(size.x, size.y, size.z))

func _window_row(z: float, x0: float, x1: float, step: float, w: float, sill: float, h: float) -> Array:
	var out: Array = []
	var x := x0 + step * 0.5
	while x < x1:
		out.append({"at": x - x0, "w": w, "h": h, "sill": sill})
		x += step
	return out

func _glass_panes(a: Vector2, b: Vector2, ops: Array, y0: float) -> void:
	var dir := (b - a).normalized()
	var rot := -atan2(dir.y, dir.x)
	for o in ops:
		var c := a + dir * float(o["at"])
		g.box("glass", Vector3(c.x, y0 + float(o["sill"]) + float(o["h"]) * 0.5, c.y), Vector3(o["w"], o["h"], 0.03), rot)
		g.box("frame", Vector3(c.x, y0 + float(o["sill"]) + 0.02, c.y), Vector3(o["w"], 0.05, 0.26), rot)
		for s in [-0.5, 0.5]:
			var p: Vector2 = c + dir * (float(o["w"]) * s)
			g.box("frame", Vector3(p.x, y0 + float(o["sill"]) + float(o["h"]) * 0.5, p.y), Vector3(0.05, o["h"], 0.22), rot)

# ------------------------------------------------------------------ Gebäudehülle
func _shell() -> void:
	# durchgehende Bodenplatte als Kollision
	g.collider(Vector3(14, -0.25, 4.5), Vector3(46, 0.5, 29))
	_floor("carpet", HALL)
	_floor("tiles_floor", Rect2(-8, -2.6, 44, 2.6))
	_floor("tiles_floor", Rect2(-8, 0, 8, 10))

func _hall() -> void:
	# Wände: Nord (zum Flur), Ost (Großbildwand), West (Foyer/Außen), Süd (Fensterfront)
	g.wall("wood", Vector2(0, 0), Vector2(36, 0), HALL_H, 0.2, [{"at": 6, "w": 1.1, "h": 2.2}, {"at": 30, "w": 1.1, "h": 2.2}])
	g.wall("wood", Vector2(36, -2.7), Vector2(36, 18.1), HALL_H, 0.2)
	g.wall("wood", Vector2(0, 0), Vector2(0, 18), HALL_H, 0.2, [{"at": 4, "w": 1.9, "h": 2.2}])
	# Südwand ohne Fenster nach draußen (Leitstellenraum nur mit Sichtverbindung zur Galerie)
	g.wall("wood", Vector2(0, 18), Vector2(36, 18), GALLERY_Y, 0.25)
	_plinth(Vector3(0.1, 0, 17.86), Vector3(35.9, 0.08, 17.88))
	# Wandschränke und Bildschirm-Infotafeln unter der Galerie
	for x0 in [3.0, 27.0]:
		_shelf(Vector3(x0 + 2.4, 0, 17.87), 2.4, PI)
	for xi in [8.0, 12.0, 24.0, 28.0]:
		g.block("bezel", Vector3(xi - 0.9, 1.35, 17.8), Vector3(xi + 0.9, 2.4, 17.86))
		_screen_quad(["screen_a", "screen_b", "screen_c", "screen_a"][[8.0, 12.0, 24.0, 28.0].find(xi)], Vector3(xi, 1.875, 17.795), Vector2(1.72, 0.97), PI)
	_door("hall_n1", "Leitstellenraum", Vector2(0, 0), Vector2(36, 0), 6, 1.1, false, -1.0)
	_door("hall_n2", "Leitstellenraum", Vector2(0, 0), Vector2(36, 0), 30, 1.1, false, -1.0)
	_door("hall_w", "Leitstellenraum", Vector2(0, 0), Vector2(0, 18), 4, 1.9, true, 1.0, true)
	# Sockelleisten
	_plinth(Vector3(0.1, 0, 0.1), Vector3(35.9, 0.08, 0.12))
	_plinth(Vector3(35.88, 0, 0.1), Vector3(35.9, 0.08, 17.9))
	_plinth(Vector3(0.1, 0, 0.1), Vector3(0.12, 0.08, 17.9))
	# Decke: helle Rasterdecke mit durchgehenden LED-Lichtbändern
	_ceiling(Rect2(0, 0, 36, GALLERY_Z), HALL_H)
	for z in [1.6, 3.9, 6.2, 8.5, 10.8, 13.0]:
		var x := 1.2
		while x < 34.0:
			g.block("frame", Vector3(x - 0.02, HALL_H - 0.035, z - 0.09), Vector3(x + 2.62, HALL_H, z + 0.09))
			g.block("emit_light", Vector3(x, HALL_H - 0.045, z - 0.06), Vector3(x + 2.6, HALL_H - 0.03, z + 0.06))
			x += 3.4
	# Lüftungsgitter
	for x in [5.0, 13.0, 21.0, 29.0]:
		g.block("frame", Vector3(x - 0.3, HALL_H - 0.02, 7.2), Vector3(x + 0.3, HALL_H - 0.005, 7.8))
	# Disponentenarbeitsplätze: vier geschwungene Tischreihen mit je drei Plätzen, Blick zur Großbildwand
	var nr := 1
	for xc in [7.6, 14.6, 21.6, 28.6]:
		_desk_row(xc, 3.4, 3, nr)
		nr += 3
	# Schichtführung an der Westseite
	_desk_row(2.6, 7.6, 2, 1, "sf", "SCHICHTFÜHRUNG")
	# Logo der Leitstelle an der Westwand (fiktiv)
	var lz := 10.0
	for i in 3:
		var bt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-24)), Vector3(0.13, 3.95, lz + 1.75 - i * 0.3))
		g.box_t(["logo_a", "logo_b", "logo_c"][i], bt, Vector3(0.04, 1.05, 0.13))
	_label("Leitstelle\nBavaria", Vector3(0.14, 3.95, lz - 0.2), PI / 2, 0.012, Color(0.86, 0.87, 0.88), 64, 2.4, 1.25).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Runder Besprechungstisch unter der Galerie
	g.cyl("desk_top", Vector3(18, 0.74, 15.9), 0.62, 0.04, 28)
	g.cyl("metal", Vector3(18, 0.37, 15.9), 0.05, 0.72, 10)
	g.cyl("dark", Vector3(18, 0.015, 15.9), 0.3, 0.03, 16)
	g.collider_cyl(Vector3(18, 0.38, 15.9), 0.62, 0.76)
	_lounge_seat("rt1", "Stuhl am Rundtisch", Vector3(16.95, 0, 15.9), 0.0)
	_lounge_seat("rt2", "Stuhl am Rundtisch", Vector3(19.05, 0, 15.9), PI)
	_lounge_seat("rt3", "Stuhl am Rundtisch", Vector3(18, 0, 16.95), PI / 2)
	for p in [Vector3(1.0, 0, 16.8), Vector3(12.5, 0, 16.8), Vector3(23.5, 0, 16.8), Vector3(34.9, 0, 16.6), Vector3(34.9, 0, 1.0), Vector3(13.5, 0, 0.9), Vector3(1.0, 0, 13.4), Vector3(1.0, 0, 1.0)]:
		_plant(p)
	# Regale mit Ordnern an der Nordwand
	for x0 in [9.0, 18.5, 24.0]:
		_shelf(Vector3(x0, 0, 0.12), 2.4)
	g.box("desk_white", Vector3(16.6, 0.55, 0.45), Vector3(0.7, 1.1, 0.6), 0.0, true)
	g.box("dark", Vector3(16.6, 1.12, 0.45), Vector3(0.6, 0.06, 0.5))
	_area({"kind": "info", "text": "Netzwerkdrucker – Ausdrucke der Einsatzdepeschen liegen im Fach."}, Vector3(16.6, 0.9, 0.7), Vector3(0.8, 0.8, 0.8))
	# Infotafel mit Hausregeln (fiktiv)
	g.box("desk_white", Vector3(13.0, 1.6, 0.13), Vector3(1.6, 1.0, 0.04))
	_label("HINWEISE FÜR DEN DIENST\n\n• Notrufe haben Vorrang\n• Platz nur nach Übergabe verlassen\n• Getränke nicht am Arbeitsplatz", Vector3(13.0, 1.6, 0.16), 0.0, 0.003, Color(0.15, 0.15, 0.17), 40, 1.45, 0.85)
	_spot("murmur", Vector3(11, 1.5, 7))
	_spot("murmur", Vector3(25, 1.5, 7))

## Bildschirmfläche (zeigt die Live-Inhalte der Leitstelle).
func _screen_quad(mat: String, c: Vector3, size: Vector2, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.position = c
	mi.rotation.y = yaw
	mi.material_override = MATS.get_mat(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

## Wandregal mit farbigen Ordnern (niedrig, wie an der Großbildwand im Vorbild).
func _shelf(p: Vector3, w: float, facing := 0.0) -> void:
	var T := Transform3D(Basis(Vector3.UP, facing), p)
	# offenes Regal: Rückwand, Seiten, Böden
	g.box_t("cabinet", T * Transform3D(Basis(), Vector3(w * 0.5, 0.5, 0.015)), Vector3(w, 1.0, 0.03))
	for sx in [0.015, w - 0.015]:
		g.box_t("cabinet", T * Transform3D(Basis(), Vector3(sx, 0.5, 0.2)), Vector3(0.03, 1.0, 0.4))
	for yy in [0.03, 0.52]:
		g.box_t("cabinet", T * Transform3D(Basis(), Vector3(w * 0.5, yy, 0.2)), Vector3(w, 0.03, 0.4))
	g.box_t("desk_top", T * Transform3D(Basis(), Vector3(w * 0.5, 1.015, 0.2)), Vector3(w + 0.02, 0.03, 0.42))
	var cols := ["binder_a", "binder_b", "binder_c", "binder_d"]
	var k := 0
	for row in [0.08, 0.56]:
		var x := 0.08
		while x < w - 0.1:
			var bw := 0.06 + float((k * 7) % 3) * 0.01
			g.box_t(cols[(k * 5 + int(row * 10)) % 4], T * Transform3D(Basis(), Vector3(x + bw * 0.5, row + 0.17, 0.25)), Vector3(bw - 0.006, 0.33, 0.28))
			x += bw
			k += 1
			if k % 9 == 0:
				x += 0.25
	g.collider(T * Vector3(w * 0.5, 0.5, 0.2), Vector3(w, 1.0, 0.4), facing)

func _gallery() -> void:
	# Galerie über der Fensterzone (Obergeschoss mit Glasfront, wie im Vorbild)
	g.block("ceiling", Vector3(0, GALLERY_Y, GALLERY_Z), Vector3(36, GALLERY_Y + 0.3, 18))
	g.block("plaster", Vector3(0, GALLERY_Y - 0.25, GALLERY_Z - 0.05), Vector3(36, GALLERY_Y + 0.35, GALLERY_Z + 0.1))
	g.block("emit_light", Vector3(0.5, GALLERY_Y - 0.27, GALLERY_Z + 0.02), Vector3(35.5, GALLERY_Y - 0.25, GALLERY_Z + 0.08))
	for x in range(2, 35, 4):
		g.block("emit_light", Vector3(x, GALLERY_Y - 0.02, 15.9), Vector3(x + 2.4, GALLERY_Y, 16.1))
	# senkrechte Glasfront des Obergeschosses mit schwarzen Profilen
	var top := HALL_H
	var y0 := GALLERY_Y + 0.35
	var x := 0.0
	while x < 36.0:
		g.block("glass", Vector3(x, y0, GALLERY_Z - 0.015), Vector3(x + 2.4, top, GALLERY_Z + 0.015))
		g.block("black", Vector3(x - 0.035, y0, GALLERY_Z - 0.05), Vector3(x + 0.035, top, GALLERY_Z + 0.05))
		x += 2.4
	g.block("black", Vector3(0, y0 - 0.02, GALLERY_Z - 0.06), Vector3(36, y0 + 0.05, GALLERY_Z + 0.06))
	g.block("black", Vector3(0, top - 0.06, GALLERY_Z - 0.06), Vector3(36, top, GALLERY_Z + 0.06))
	# Obergeschoss (nur sichtbar, nicht begehbar): Lage- und Stabsraum mit Arbeitsplätzen
	g.block("wood", Vector3(0, GALLERY_Y + 0.3, 17.8), Vector3(36, top, 18.0))
	g.block("carpet", Vector3(0, GALLERY_Y + 0.3, GALLERY_Z), Vector3(36, GALLERY_Y + 0.35, 17.8))
	for xx in range(1, 35, 3):
		var fy := GALLERY_Y + 0.35
		g.block("desk_top", Vector3(xx, fy + 0.72, 15.7), Vector3(xx + 2.2, fy + 0.76, 16.5))
		g.block("cabinet", Vector3(xx + 0.05, fy, 15.75), Vector3(xx + 0.5, fy + 0.72, 16.45))
		g.block("cabinet", Vector3(xx + 1.7, fy, 15.75), Vector3(xx + 2.15, fy + 0.72, 16.45))
		for k in 2:
			var mx := xx + 0.45 + k * 0.75
			g.block("bezel", Vector3(mx, fy + 0.85, 16.3), Vector3(mx + 0.6, fy + 1.22, 16.33))
			_screen_quad("screen_a" if (xx + k) % 2 == 0 else "screen_b", Vector3(mx + 0.3, fy + 1.035, 16.295), Vector2(0.56, 0.33), PI)
		g.block("chair", Vector3(xx + 0.85, fy + 0.4, 15.0), Vector3(xx + 1.35, fy + 0.5, 15.5))
		g.block("chair", Vector3(xx + 0.85, fy + 0.5, 14.95), Vector3(xx + 1.35, fy + 1.15, 15.03))
	for xx in range(2, 35, 4):
		g.block("emit_light", Vector3(xx, top - 0.03, 15.9), Vector3(xx + 2.4, top - 0.01, 16.1))
	# Decke des Obergeschosses
	_ceiling(Rect2(0, GALLERY_Z, 36, 18 - GALLERY_Z), HALL_H)

func _videowall() -> void:
	# Großbildwand an der Stirnseite (Ostwand), Inhalt live aus der Simulation (siehe building.gd)
	var x := 35.88
	g.block("black", Vector3(x - 0.12, 1.45, 1.5), Vector3(x, 4.15, 9.9))
	var wall := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(8.24, 2.62)
	wall.mesh = qm
	wall.position = Vector3(x - 0.125, 2.8, 5.7)
	wall.rotation.y = -PI / 2
	wall.material_override = MATS.get_mat("wall_screen")
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wall)
	for zz in [3.56, 5.62, 7.68]:
		g.block("black", Vector3(x - 0.13, 1.49, zz - 0.006), Vector3(x - 0.124, 4.11, zz + 0.006))
	# Emblemtafel (fiktives Emblem der Leitstelle Bavaria – kein echtes Wappen)
	var ez := 11.5
	g.block("frame", Vector3(x - 0.1, 1.45, ez - 1.25), Vector3(x, 4.15, ez + 1.25))
	g.block("red_matte", Vector3(x - 0.11, 1.53, ez - 1.17), Vector3(x - 0.1, 4.07, ez + 1.17))
	var em := MeshInstance3D.new()
	var eq := QuadMesh.new()
	eq.size = Vector2(1.3, 1.5)
	em.mesh = eq
	em.position = Vector3(x - 0.115, 2.9, ez)
	em.rotation.y = -PI / 2
	em.material_override = MATS.get_mat("emblem")
	root.add_child(em)
	_label("FEUERWEHR", Vector3(x - 0.115, 3.85, ez), -PI / 2, 0.005, Color(1, 0.95, 0.9), 48, 2.0, 0.22)
	_label("LEITSTELLE BAVARIA", Vector3(x - 0.115, 1.85, ez), -PI / 2, 0.005, Color(1, 0.95, 0.9), 48, 2.0, 0.22)
	# Digitaluhr (rote Ziffern)
	g.block("black", Vector3(x - 0.14, 3.25, 13.2), Vector3(x, 3.75, 14.4))
	var clk := _label("00:00", Vector3(x - 0.145, 3.5, 13.8), -PI / 2, 0.006, Color(1.0, 0.12, 0.08), 64, 0.95, 0.36)
	labels["clock"] = clk
	# niedrige Schränke unter der Großbildwand
	_shelf(Vector3(35.85, 0, 1.6), 3.9, -PI / 2)
	_shelf(Vector3(35.85, 0, 6.0), 3.9, -PI / 2)

# ------------------------------------------------------------------ Flur und Foyer
func _corridor_and_foyer() -> void:
	var cz := -2.6
	var door_xs := {"umkl": -4.0, "pause": 5.0, "bespr": 13.0, "wcd": 17.5, "wch": 20.5, "tech": 25.5, "buero": 32.5}
	var ops: Array = []
	for k in door_xs:
		ops.append({"at": float(door_xs[k]) + 8.0, "w": 1.0, "h": 2.15})
	g.wall("plaster", Vector2(-8, cz), Vector2(36, cz), ROOM_H, 0.15, ops)
	_door("umkl", "Umkleide", Vector2(-8, cz), Vector2(36, cz), door_xs["umkl"] + 8.0, 1.0, false, 1.0)
	_door("pause", "Pausenraum", Vector2(-8, cz), Vector2(36, cz), door_xs["pause"] + 8.0, 1.0, false, 1.0)
	_door("bespr", "Besprechungsraum", Vector2(-8, cz), Vector2(36, cz), door_xs["bespr"] + 8.0, 1.0, false, 1.0)
	_door("wcd", "WC Damen", Vector2(-8, cz), Vector2(36, cz), door_xs["wcd"] + 8.0, 1.0, false, 1.0)
	_door("wch", "WC Herren", Vector2(-8, cz), Vector2(36, cz), door_xs["wch"] + 8.0, 1.0, false, 1.0)
	_door("tech", "Technikraum", Vector2(-8, cz), Vector2(36, cz), door_xs["tech"] + 8.0, 1.0, false, 1.0)
	_door("buero", "Büro Schichtführung", Vector2(-8, cz), Vector2(36, cz), door_xs["buero"] + 8.0, 1.0, false, 1.0)
	var names := {"umkl": "Umkleide", "pause": "Pausenraum", "bespr": "Besprechung", "wcd": "WC Damen", "wch": "WC Herren", "tech": "Technik / Server", "buero": "Schichtführung"}
	for k in door_xs:
		_sign(names[k], Vector3(float(door_xs[k]) + 0.85, 1.6, cz + 0.085), 0.0)
	_sign("Leitstellenraum", Vector3(6.85, 1.6, -0.115), PI)
	_sign("Leitstellenraum", Vector3(30.85, 1.6, -0.115), PI)
	_sign("Leitstellenraum", Vector3(-0.115, 2.4, 4.0), -PI / 2)
	_ceiling(Rect2(-8, -2.6, 44, 2.6), ROOM_H)
	_ceiling(Rect2(-8, 0, 8, 10), ROOM_H)
	# Flur: Einbauleuchten, Sockelleisten, Ausstattung nach Arbeitsstätten-Vorgaben
	for x in range(-6, 36, 3):
		_panel_light(Vector3(float(x), ROOM_H, -1.3))
	_plinth(Vector3(-7.9, 0, -2.52), Vector3(35.9, 0.07, -2.5))
	_plinth(Vector3(0.1, 0, -0.12), Vector3(35.9, 0.07, -0.1))
	_fire_extinguisher(Vector3(2.2, 0, -0.12), PI)
	_fire_extinguisher(Vector3(23.0, 0, -0.12), PI)
	_fire_extinguisher(Vector3(-0.3, 0, 9.85), PI)
	# Erste-Hilfe-Kasten und Defibrillator
	g.block("desk_white", Vector3(10.0, 1.3, -0.16), Vector3(10.5, 1.75, -0.1))
	g.block("green_sign", Vector3(10.17, 1.47, -0.165), Vector3(10.33, 1.53, -0.16))
	g.block("green_sign", Vector3(10.22, 1.42, -0.165), Vector3(10.28, 1.58, -0.16))
	_label("ERSTE HILFE", Vector3(10.25, 1.8, -0.17), PI, 0.003, Color(0.1, 0.45, 0.25), 40, 0.5, 0.08)
	g.block("green_sign", Vector3(10.7, 1.2, -0.17), Vector3(11.1, 1.65, -0.1))
	_label("AED", Vector3(10.9, 1.43, -0.175), PI, 0.004, Color(1, 1, 1), 48, 0.3, 0.15)
	# Fluchtweg-Kennzeichnung (leuchtend)
	for p in [[Vector3(-7.85, 2.35, -1.3), PI / 2], [Vector3(35.85, 2.35, -1.3), -PI / 2], [Vector3(-4.0, 2.55, 0.0), PI]]:
		_exit_sign(p[0], p[1])
	# Pinnwände und Infobildschirm (Dienstplan)
	_notice_board(Vector3(8.2, 1.5, -2.51), 0.0, 1.4)
	_notice_board(Vector3(27.8, 1.5, -2.51), 0.0, 1.4)
	g.block("bezel", Vector3(15.1, 1.2, -0.17), Vector3(16.5, 2.0, -0.1))
	_screen_quad("screen_b", Vector3(15.8, 1.6, -0.175), Vector2(1.34, 0.74), PI)
	# Bilder (Einsatzfotos als abstrakte Drucke, fiktiv)
	for p in [[Vector3(3.6, 1.6, -2.51), 0.0, "art_a"], [Vector3(19.0, 1.6, -0.11), PI, "art_b"], [Vector3(34.0, 1.6, -0.11), PI, "art_c"], [Vector3(-6.0, 1.6, -2.51), 0.0, "art_b"]]:
		_picture(p[0], p[1], 1.0, 0.7, p[2])
	# Wertstofftrennung vor dem Pausenraum
	for k in 3:
		var bx := 6.2 + k * 0.42
		g.block(["binder_d", "logo_a", "fruit_y"][k], Vector3(bx, 0, -2.5), Vector3(bx + 0.38, 0.75, -2.1), true)
		g.block("dark", Vector3(bx + 0.02, 0.75, -2.48), Vector3(bx + 0.36, 0.78, -2.12))
	# Wanduhr
	_wall_clock(Vector3(13.0, 2.35, -0.115), PI)
	_plant(Vector3(35.5, 0, -2.2), 1.1)
	_plant(Vector3(-7.5, 0, -2.2), 1.1)

	# Foyer: Außenwand West mit Haupteingang (Windfang), Südwand
	g.wall("plaster", Vector2(-8, -9.1), Vector2(-8, 10), ROOM_H, 0.25, [{"at": 14.1, "w": 2.0, "h": 2.2}, {"at": 17.6, "w": 1.6, "h": 1.6, "sill": 0.6}])
	_glass_panes(Vector2(-8, -9.1), Vector2(-8, 10), [{"at": 17.6, "w": 1.6, "h": 1.6, "sill": 0.6}], 0.0)
	_door("main", "Haupteingang", Vector2(-8, -9.1), Vector2(-8, 10), 14.1, 2.0, true, 1.0, true, false)
	g.wall("plaster", Vector2(-8, 10), Vector2(0.1, 10), ROOM_H, 0.2)
	g.block("rug", Vector3(-7.86, 0.0, 3.9), Vector3(-6.3, 0.012, 6.1))
	for z in [2.5, 5.0, 7.5]:
		for x in [-6.0, -2.5]:
			_panel_light(Vector3(x, ROOM_H, z))
	_plinth(Vector3(-7.85, 0, 9.88), Vector3(-0.1, 0.07, 9.9))
	# Empfangstresen: Besuchertheke (1,10 m) mit Arbeitsplatz dahinter
	var rx0 := -5.6
	var rx1 := -2.6
	g.block("oak", Vector3(rx0, 0.0, 7.0), Vector3(rx1, 1.08, 7.12), true)
	g.block("oak", Vector3(rx0, 0.0, 7.0), Vector3(rx0 + 0.12, 1.08, 8.4), true)
	g.block("desk_white", Vector3(rx0 - 0.02, 1.08, 6.94), Vector3(rx1 + 0.02, 1.12, 7.3))
	g.block("led_white", Vector3(rx0 + 0.05, 0.04, 6.99), Vector3(rx1 - 0.05, 0.06, 7.0))
	g.block("desk_top", Vector3(rx0 + 0.12, 0.72, 7.12), Vector3(rx1, 0.75, 7.8))
	g.block("cabinet", Vector3(rx1 - 0.5, 0.0, 7.15), Vector3(rx1 - 0.05, 0.72, 7.75), true)
	for k in 2:
		var mx := -4.7 + k * 0.62
		g.block("bezel", Vector3(mx, 0.85, 7.2), Vector3(mx + 0.56, 1.2, 7.23))
		_screen_quad(["screen_b", "screen_a"][k], Vector3(mx + 0.28, 1.025, 7.235), Vector2(0.53, 0.32), 0.0)
		g.block("metal", Vector3(mx + 0.25, 0.75, 7.24), Vector3(mx + 0.31, 0.85, 7.28))
	g.block("dark", Vector3(-4.6, 0.75, 7.4), Vector3(-4.15, 0.77, 7.55))
	g.block("dark", Vector3(-3.6, 0.75, 7.35), Vector3(-3.38, 0.8, 7.58))
	_chair(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-4.3, 0, 8.25)), true)
	g.collider(Vector3(-4.3, 0.5, 8.25), Vector3(0.5, 1.0, 0.5))
	_label("EMPFANG", Vector3(-4.1, 0.75, 6.995), PI, 0.004, Color(0.25, 0.2, 0.15), 48, 1.6, 0.25)
	g.block("desk_white", Vector3(-3.1, 1.12, 6.98), Vector3(-2.85, 1.15, 7.2))
	_area({"kind": "info", "text": "Willkommen in der Integrierten Leitstelle Bavaria.\nBesucher melden sich bitte am Empfang. Der Leitstellenraum liegt hinter der Glastür – Zutritt nur für Dienstpersonal."}, Vector3(-4.1, 1.1, 6.7), Vector3(3.0, 1.2, 0.6))
	# Logo-Wand hinter dem Empfang
	g.block("red_matte", Vector3(-6.4, 1.3, 9.88), Vector3(-1.8, 2.5, 9.9))
	var lt := _label("INTEGRIERTE LEITSTELLE BAVARIA\nfür Feuerwehr und Rettungsdienst", Vector3(-4.1, 1.9, 9.875), PI, 0.0035, Color(1, 1, 1), 48, 4.2, 1.0)
	# Wartebereich mit Sesseln und Tisch
	for s in [[Vector3(-7.3, 0, 1.6), 0.0, "fb1"], [Vector3(-7.3, 0, 2.9), 0.0, "fb2"], [Vector3(-5.6, 0, 0.75), -PI / 2, "fb3"]]:
		_armchair(s[0], s[1])
		_lounge_seat(s[2], "Sessel im Foyer", s[0], s[1], false, 0.44)
	g.cyl("oak", Vector3(-6.2, 0.42, 2.0), 0.4, 0.04, 24)
	g.cyl("metal", Vector3(-6.2, 0.2, 2.0), 0.04, 0.4, 8)
	g.collider_cyl(Vector3(-6.2, 0.22, 2.0), 0.4, 0.44)
	g.block("paper", Vector3(-6.35, 0.44, 1.85), Vector3(-6.1, 0.455, 2.15))
	g.block("art_a", Vector3(-6.05, 0.44, 1.9), Vector3(-5.85, 0.47, 2.2))
	# Garderobe am Eingang
	g.block("metal", Vector3(-7.9, 1.7, 6.2), Vector3(-7.84, 1.74, 7.6))
	for k in 6:
		g.block("metal", Vector3(-7.86, 1.6, 6.3 + k * 0.22), Vector3(-7.74, 1.64, 6.34 + k * 0.22))
	g.block("trousers", Vector3(-7.84, 0.95, 6.4), Vector3(-7.66, 1.62, 6.8))
	g.block("fabric_red", Vector3(-7.84, 1.05, 7.0), Vector3(-7.68, 1.62, 7.35))
	# Zutritt: Kartenleser an der Glastür zum Leitstellenraum
	g.block("dark", Vector3(-0.17, 1.15, 5.15), Vector3(-0.1, 1.33, 5.27))
	g.block("led_green", Vector3(-0.175, 1.29, 5.18), Vector3(-0.17, 1.31, 5.24))
	_label("Zutritt nur für Dienstpersonal", Vector3(-0.115, 2.62, 4.0), -PI / 2, 0.0024, Color(0.25, 0.25, 0.27), 36, 1.4, 0.08)
	# Infobildschirm im Foyer
	g.block("bezel", Vector3(-0.16, 1.35, 1.1), Vector3(-0.1, 2.15, 2.5))
	_screen_quad("screen_a", Vector3(-0.165, 1.75, 1.8), Vector2(1.34, 0.74), -PI / 2)
	_plant(Vector3(-7.4, 0, 9.3))
	_plant(Vector3(-0.6, 0, 9.3))
	_plant(Vector3(-7.4, 0, 0.5), 1.0)

# ------------------------------------------------------------------ Ausstattungs-Bausteine
func _panel_light(p: Vector3) -> void:
	g.block("frame", Vector3(p.x - 0.33, p.y - 0.02, p.z - 0.33), Vector3(p.x + 0.33, p.y, p.z + 0.33))
	g.block("emit_light", Vector3(p.x - 0.3, p.y - 0.03, p.z - 0.3), Vector3(p.x + 0.3, p.y - 0.02, p.z + 0.3))

func _picture(c: Vector3, yaw: float, w: float, h: float, mat: String) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), c)
	g.box_t("black", T, Vector3(w, h, 0.03))
	g.box_t("desk_white", T * Transform3D(Basis(), Vector3(0, 0, 0.016)), Vector3(w - 0.06, h - 0.06, 0.004))
	g.box_t(mat, T * Transform3D(Basis(), Vector3(0, 0, 0.019)), Vector3(w - 0.2, h - 0.2, 0.004))
	g.box_t("art_c" if mat != "art_c" else "art_a", T * Transform3D(Basis(Vector3.FORWARD, 0.3), Vector3(-w * 0.12, -h * 0.05, 0.022)), Vector3(w * 0.3, h * 0.12, 0.003))

func _fire_extinguisher(p: Vector3, yaw: float) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), p)
	var c := T * Vector3(0, 0, 0.11)
	g.cyl("red_ext", c + Vector3(0, 0.62, 0), 0.08, 0.5, 14)
	g.cyl("black", c + Vector3(0, 0.92, 0), 0.03, 0.1, 8)
	g.box_t("black", T * Transform3D(Basis(), Vector3(0.06, 0.98, 0.11)), Vector3(0.12, 0.025, 0.03))
	g.box_t("dark", T * Transform3D(Basis(), Vector3(0, 0.75, 0.02)), Vector3(0.1, 0.06, 0.03))
	g.box_t("red_ext", T * Transform3D(Basis(), Vector3(0, 1.45, 0.005)), Vector3(0.2, 0.2, 0.004))
	_label("F", T * Vector3(0, 1.45, 0.009), yaw, 0.004, Color(1, 1, 1), 40, 0.14, 0.14)

func _exit_sign(p: Vector3, yaw: float) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), p)
	g.box_t("green_sign", T, Vector3(0.42, 0.16, 0.03))
	_label("NOTAUSGANG  ➜", T * Vector3(0, 0, 0.018), yaw, 0.0025, Color(1, 1, 1), 40, 0.38, 0.1)

func _notice_board(c: Vector3, yaw: float, w: float) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), c)
	g.box_t("frame", T, Vector3(w, 0.9, 0.03))
	g.box_t("cork", T * Transform3D(Basis(), Vector3(0, 0, 0.017)), Vector3(w - 0.06, 0.84, 0.004))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x * 100.0)
	for k in 6:
		var px := rng.randf_range(-w * 0.38, w * 0.38)
		var py := rng.randf_range(-0.25, 0.25)
		g.box_t(["paper", "paper", "fruit_y", "paper", "art_a", "paper"][k], T * Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.06, 0.06)), Vector3(px, py, 0.021)), Vector3(0.21, 0.29, 0.002))
		g.sphere("red", T * Vector3(px, py + 0.13, 0.025), 0.008)

func _wall_clock(c: Vector3, yaw: float) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), c)
	g.cyl_t("desk_white", T * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, 0.02)), 0.17, 0.035, 24)
	g.cyl_t("black", T * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, 0.012)), 0.18, 0.025, 24)
	g.box_t("black", T * Transform3D(Basis(Vector3.FORWARD, 0.5), Vector3(0.02, 0.04, 0.04)), Vector3(0.012, 0.1, 0.004))
	g.box_t("black", T * Transform3D(Basis(Vector3.FORWARD, -1.8), Vector3(0.05, 0.0, 0.04)), Vector3(0.01, 0.13, 0.004))

func _armchair(p: Vector3, yaw: float) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), p)
	g.box_t("leather", T * Transform3D(Basis(), Vector3(0.02, 0.3, 0)), Vector3(0.62, 0.26, 0.66))
	g.box_t("leather", T * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-8)), Vector3(-0.26, 0.62, 0)), Vector3(0.14, 0.52, 0.66))
	for s in [-1.0, 1.0]:
		g.box_t("leather", T * Transform3D(Basis(), Vector3(0.02, 0.5, s * 0.3)), Vector3(0.62, 0.2, 0.08))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box_t("metal", T * Transform3D(Basis(), Vector3(sx * 0.25, 0.08, sz * 0.27)), Vector3(0.03, 0.16, 0.03))
	g.collider(T * Vector3(0, 0.4, 0), Vector3(0.66, 0.8, 0.7), yaw)

## Jalousien vor einer Fensterreihe (teilweise heruntergelassen).
func _blinds(z: float, x0: float, x1: float, step: float, w: float, sill: float, h: float) -> void:
	var x := x0 + step * 0.5
	while x < x1:
		var top := sill + h
		var low := top - h * 0.45
		g.block("blind", Vector3(x - w * 0.5, top - 0.06, z + 0.13), Vector3(x + w * 0.5, top, z + 0.2))
		var y := top - 0.1
		while y > low:
			g.block("blind", Vector3(x - w * 0.5 + 0.02, y, z + 0.15), Vector3(x + w * 0.5 - 0.02, y + 0.012, z + 0.19))
			y -= 0.045
		x += step

# ------------------------------------------------------------------ Räume nördlich des Flurs
func _room_walls(x0: float, x1: float, windows := true) -> void:
	var z0 := -9.0
	if windows:
		var ops := _window_row(z0, x0, x1, 2.4, 1.6, 0.9, 1.5)
		g.wall("plaster", Vector2(x0, z0), Vector2(x1, z0), ROOM_H, 0.25, ops)
		_glass_panes(Vector2(x0, z0), Vector2(x1, z0), ops, 0.0)
		_blinds(z0, x0, x1, 2.4, 1.6, 0.9, 1.5)
		# Fensterbänke
		for o in ops:
			var cx := x0 + float(o["at"])
			g.block("desk_white", Vector3(cx - 0.85, 0.88, z0 + 0.12), Vector3(cx + 0.85, 0.91, z0 + 0.3))
	else:
		g.wall("plaster", Vector2(x0, z0), Vector2(x1, z0), ROOM_H, 0.25)
	_ceiling(Rect2(x0, z0, x1 - x0, 6.4), ROOM_H)
	var x := x0 + 1.5
	while x < x1 - 0.5:
		for z in [-7.4, -4.4]:
			_panel_light(Vector3(x, ROOM_H, z))
		x += 2.6
	_plinth(Vector3(x0 + 0.1, 0, z0 + 0.125), Vector3(x1 - 0.1, 0.07, z0 + 0.14))
	_plinth(Vector3(x0 + 0.1, 0, -2.69), Vector3(x1 - 0.1, 0.07, -2.675))

func _break_room() -> void:
	var x0 := 0.0
	var x1 := 10.0
	_room_walls(x0, x1)
	_floor("parquet", Rect2(x0, -9, x1 - x0, 6.4))
	g.wall("plaster", Vector2(x1, -9), Vector2(x1, -2.6), ROOM_H, 0.15)
	# Akzentwand hinter dem Sofa, Leuchten
	g.block("accent_green", Vector3(9.9, 0.0, -8.9), Vector3(9.92, ROOM_H, -2.7))
	_plinth(Vector3(0.1, 0, -2.74), Vector3(9.9, 0.07, -2.72))
	# Küchenzeile an der Westwand: Eichenfronten, dunkle Steinplatte, Glasrückwand,
	# hellgraue Hängeschränke mit Unterbauleuchte, offenes Regal mit Tassen
	var kx := 0.08
	var z0 := -8.55
	var z1 := -3.3
	g.block("plinth", Vector3(kx + 0.04, 0.0, z0), Vector3(kx + 0.56, 0.1, z1))
	g.block("kitchen", Vector3(kx, 0.1, z0), Vector3(kx + 0.58, 0.88, z1), true)
	var z := z0
	var fronts := [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.45]
	var fi := 0
	for wv in fronts:
		var w: float = wv
		if z + w > z1 + 0.001:
			w = z1 - z
		var kind := "door"
		if absf(z + w * 0.5 - (-5.3)) < 0.31:
			kind = "oven"
		elif absf(z + w * 0.5 - (-6.0)) < 0.31:
			kind = "dishwasher"
		var zc: float = z + w * 0.5
		if kind == "oven":
			g.block("steel", Vector3(kx + 0.58, 0.12, z + 0.003), Vector3(kx + 0.6, 0.86, z + w - 0.003))
			g.block("black", Vector3(kx + 0.601, 0.2, z + 0.04), Vector3(kx + 0.605, 0.68, z + w - 0.04))
			g.block("metal", Vector3(kx + 0.61, 0.74, zc - 0.22), Vector3(kx + 0.63, 0.76, zc + 0.22))
			g.block("dark", Vector3(kx + 0.601, 0.76, zc - 0.2), Vector3(kx + 0.605, 0.83, zc + 0.2))
		else:
			g.block("oak", Vector3(kx + 0.58, 0.12, z + 0.003), Vector3(kx + 0.6, 0.86, z + w - 0.003))
			if kind == "dishwasher":
				g.block("metal", Vector3(kx + 0.605, 0.78, zc - 0.2), Vector3(kx + 0.615, 0.795, zc + 0.2))
			else:
				g.block("oak", Vector3(kx + 0.6, 0.47, z + 0.003), Vector3(kx + 0.601, 0.474, z + w - 0.003))
				g.block("metal", Vector3(kx + 0.605, 0.78, zc - 0.15), Vector3(kx + 0.615, 0.795, zc + 0.15))
				g.block("metal", Vector3(kx + 0.605, 0.4, zc - 0.15), Vector3(kx + 0.615, 0.415, zc + 0.15))
		z += w
		fi += 1
	g.block("worktop", Vector3(kx, 0.88, z0 - 0.02), Vector3(kx + 0.64, 0.92, z1 + 0.02))
	g.block("glass", Vector3(kx, 0.92, z0), Vector3(kx + 0.012, 1.48, z1))
	g.block("accent_green", Vector3(kx - 0.002, 0.92, z0), Vector3(kx + 0.004, 1.48, z1))
	# Hängeschränke (mit Lücke für das offene Regal über dem Kaffeeautomaten)
	var shelf_z0 := -8.55
	var shelf_z1 := -7.35
	g.block("kitchen_front", Vector3(kx, 1.5, shelf_z1), Vector3(kx + 0.36, 2.25, z1), true)
	var uz := shelf_z1
	while uz < z1 - 0.1:
		var w2 := minf(0.6, z1 - uz)
		g.block("kitchen_front", Vector3(kx + 0.36, 1.505, uz + 0.003), Vector3(kx + 0.375, 2.245, uz + w2 - 0.003))
		g.block("metal", Vector3(kx + 0.375, 1.53, uz + w2 * 0.5 - 0.12), Vector3(kx + 0.385, 1.545, uz + w2 * 0.5 + 0.12))
		uz += w2
	g.block("warm_light", Vector3(kx + 0.28, 1.49, shelf_z1 + 0.05), Vector3(kx + 0.32, 1.5, z1 - 0.05))
	# offenes Regal mit Tassen und Gläsern
	for sy in [1.55, 1.9]:
		g.block("oak", Vector3(kx, sy, shelf_z0), Vector3(kx + 0.3, sy + 0.03, shelf_z1))
		for k in 7:
			var cz := shelf_z0 + 0.12 + k * 0.16
			if sy < 1.6:
				g.cyl(["cup", "fruit_r", "cup", "accent_green", "cup", "cup", "art_a"][k], Vector3(kx + 0.15, sy + 0.08, cz), 0.04, 0.1, 12)
			else:
				g.cyl("glass", Vector3(kx + 0.15, sy + 0.09, cz), 0.035, 0.12, 10)
	# Kaffeevollautomat (Edelstahl, Tassenablage, Bohnenbehälter)
	var cm := Vector3(kx + 0.3, 0.92, -8.1)
	g.block("steel", cm + Vector3(-0.22, 0, -0.17), cm + Vector3(0.16, 0.46, 0.17))
	g.block("black", cm + Vector3(-0.22, 0.46, -0.17), cm + Vector3(0.16, 0.5, 0.17))
	g.block("black", cm + Vector3(0.16, 0.06, -0.1), cm + Vector3(0.2, 0.24, 0.1))
	g.block("dark", cm + Vector3(0.12, 0.22, -0.05), cm + Vector3(0.24, 0.26, 0.05))
	g.block("led_blue", cm + Vector3(0.161, 0.34, -0.08), cm + Vector3(0.165, 0.42, 0.08))
	g.cyl("cup", cm + Vector3(0.18, 0.11, 0), 0.04, 0.09, 12)
	g.cyl("glass", cm + Vector3(-0.08, 0.56, 0.05), 0.07, 0.12, 12)
	g.cyl("coffee", cm + Vector3(-0.08, 0.535, 0.05), 0.065, 0.06, 12)
	_area({"kind": "coffee"}, cm + Vector3(0.2, 0.25, 0), Vector3(0.6, 0.6, 0.6))
	_spot("coffee", cm)
	# Wasserkocher, Toaster, Brett mit Brot
	g.cyl("steel", Vector3(kx + 0.28, 1.02, -7.55), 0.08, 0.2, 14)
	g.cyl("black", Vector3(kx + 0.28, 0.925, -7.55), 0.09, 0.01, 14)
	g.block("art_c", Vector3(kx + 0.18, 0.92, -7.25), Vector3(kx + 0.42, 1.1, -7.05))
	g.block("oak", Vector3(kx + 0.2, 0.92, -6.95), Vector3(kx + 0.5, 0.94, -6.75))
	g.sphere("bread", Vector3(kx + 0.35, 0.97, -6.85), 0.07, Vector3(1.5, 0.7, 1.0))
	# Spüle mit Bogenarmatur und Abtropfgitter
	var sk := Vector3(kx + 0.32, 0.92, -6.25)
	g.block("steel", sk + Vector3(-0.22, -0.005, -0.22), sk + Vector3(0.2, 0.006, 0.22))
	g.block("dark", sk + Vector3(-0.18, 0.0, -0.18), sk + Vector3(0.16, 0.007, 0.18))
	g.cyl("metal", sk + Vector3(-0.2, 0.16, 0), 0.016, 0.32, 10)
	g.box_t("metal", Transform3D(Basis(Vector3.FORWARD, PI / 2), sk + Vector3(-0.1, 0.32, 0)), Vector3(0.022, 0.21, 0.022))
	g.cyl("metal", sk + Vector3(0.0, 0.28, 0), 0.014, 0.08, 8)
	g.block("metal", sk + Vector3(-0.12, 0.006, 0.3), sk + Vector3(0.2, 0.1, 0.55))
	for k in 3:
		g.box_t("ceramic", Transform3D(Basis(Vector3.FORWARD, 0.25), sk + Vector3(0.0, 0.14, 0.34 + k * 0.07)), Vector3(0.02, 0.22, 0.2))
	_area({"kind": "water", "text": "Wasser zapfen"}, sk + Vector3(0.1, 0.2, 0), Vector3(0.6, 0.5, 0.7))
	_spot("water", sk)
	# Kochfeld (Glaskeramik) über dem Backofen
	var hb := Vector3(kx + 0.32, 0.92, -5.3)
	g.block("black", hb + Vector3(-0.26, 0, -0.29), hb + Vector3(0.26, 0.008, 0.29))
	g.cyl("steel", hb + Vector3(0.05, 0.09, 0.12), 0.1, 0.16, 16)
	g.cyl("black", hb + Vector3(0.05, 0.175, 0.12), 0.105, 0.012, 16)
	var plates := Node3D.new()
	root.add_child(plates)
	for dx in [-0.12, 0.12]:
		for dz in [-0.14, 0.14]:
			var hp := MeshInstance3D.new()
			var cmesh := CylinderMesh.new()
			cmesh.top_radius = 0.09
			cmesh.bottom_radius = 0.09
			cmesh.height = 0.004
			cmesh.radial_segments = 20
			hp.mesh = cmesh
			hp.position = hb + Vector3(dx, 0.011, dz)
			hp.material_override = MATS.get_mat("dark")
			plates.add_child(hp)
			hotplates.append(hp)
	_area({"kind": "stove", "id": "stove"}, hb + Vector3(0.1, 0.2, 0), Vector3(0.6, 0.4, 0.7))
	# Messerblock, Gewürze, Küchenrolle
	g.block("oak", Vector3(kx + 0.08, 0.92, -4.85), Vector3(kx + 0.2, 1.15, -4.73))
	for k in 5:
		g.cyl(["fruit_r", "fruit_y", "fruit_g", "fruit_o", "fruit_r"][k], Vector3(kx + 0.1, 0.97, -4.62 + k * 0.06), 0.022, 0.09, 8)
	g.box_t("ceramic", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(kx + 0.12, 1.42, -4.45)), Vector3(0.12, 0.25, 0.12))
	# Mikrowelle
	var mw := Vector3(kx + 0.3, 0.92, -4.0)
	g.block("steel", mw + Vector3(-0.2, 0, -0.27), mw + Vector3(0.18, 0.3, 0.27))
	g.block("black", mw + Vector3(0.18, 0.04, -0.24), mw + Vector3(0.19, 0.26, 0.12))
	g.block("led_green", mw + Vector3(0.185, 0.2, 0.15), mw + Vector3(0.195, 0.24, 0.24))
	_area({"kind": "microwave"}, mw + Vector3(0.2, 0.15, 0), Vector3(0.6, 0.5, 0.7))
	_spot("microwave", mw)
	# Obstschale und Kräutertopf
	var fb := Vector3(kx + 0.33, 0.92, -3.55)
	g.cyl("ceramic", fb + Vector3(0, 0.03, 0), 0.13, 0.06, 18, 0.07)
	for k in 6:
		var a := TAU * k / 6.0
		g.sphere(["fruit_o", "fruit_g", "fruit_r", "fruit_y", "fruit_o", "fruit_g"][k], fb + Vector3(cos(a) * 0.06, 0.09 + (k % 2) * 0.03, sin(a) * 0.06), 0.04)
	g.cyl("pot", Vector3(kx + 0.3, 1.66, -3.55), 0.06, 0.12, 12)
	g.sphere("plant", Vector3(kx + 0.3, 1.78, -3.55), 0.1, Vector3(1, 0.8, 1))
	_label("KAFFEEKASSE\n0,50 € pro Tasse", Vector3(kx + 0.015, 1.2, -7.55), PI / 2, 0.003, Color(0.15, 0.15, 0.15), 40, 0.4, 0.14)
	g.block("desk_white", Vector3(kx + 0.008, 1.11, -7.78), Vector3(kx + 0.012, 1.29, -7.32))
	# Kühlschrank (Tür über den Türmechanismus)
	var fx := 9.2
	g.block("steel", Vector3(fx - 0.33, 0, -8.85), Vector3(fx + 0.33, 1.85, -8.22), true)
	var hinge := Node3D.new()
	hinge.position = Vector3(fx + 0.33, 0, -8.2)
	root.add_child(hinge)
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1 | 2
	hinge.add_child(body)
	var fd := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(0.66, 1.83, 0.05)
	fd.mesh = fbm
	fd.material_override = MATS.get_mat("steel")
	fd.position = Vector3(-0.33, 0.93, 0.0)
	body.add_child(fd)
	var fh := MeshInstance3D.new()
	var fhm := BoxMesh.new()
	fhm.size = Vector3(0.03, 0.6, 0.04)
	fh.mesh = fhm
	fh.material_override = MATS.get_mat("black")
	fh.position = Vector3(-0.6, 1.2, 0.04)
	body.add_child(fh)
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(0.66, 1.83, 0.06)
	fcs.shape = fsh
	fcs.position = fd.position
	body.add_child(fcs)
	body.set_meta("ia", {"kind": "door", "id": "fridge", "name": "Kühlschrank"})
	doors["fridge"] = {"hinge": hinge, "open_angle": deg_to_rad(105), "group": "fridge", "name": "Kühlschrank"}
	g.block("ceramic", Vector3(fx - 0.3, 0.2, -8.8), Vector3(fx + 0.3, 1.7, -8.75))
	for yy in [0.6, 1.0, 1.4]:
		g.block("glass", Vector3(fx - 0.3, yy, -8.8), Vector3(fx + 0.3, yy + 0.01, -8.3))
	g.block("food", Vector3(fx - 0.2, 1.01, -8.7), Vector3(fx - 0.05, 1.12, -8.5))
	g.block("cup", Vector3(fx + 0.05, 0.61, -8.7), Vector3(fx + 0.15, 0.82, -8.6))
	_spot("fridge", Vector3(fx, 1.0, -8.5))
	# Wasserspender
	var wd := Vector3(7.9, 0, -8.6)
	g.block("desk_white", wd + Vector3(-0.17, 0, -0.17), wd + Vector3(0.17, 1.05, 0.17), true)
	g.cyl("water", wd + Vector3(0, 1.28, 0), 0.14, 0.45, 16)
	g.block("led_blue", wd + Vector3(-0.05, 0.85, 0.17), wd + Vector3(0.05, 0.9, 0.18))
	_area({"kind": "water", "text": "Wasser zapfen (Wasserspender)"}, wd + Vector3(0, 0.9, 0.3), Vector3(0.6, 0.8, 0.5))
	# Esstisch (Eiche) mit sechs Stühlen und drei Pendelleuchten
	var tc := Vector3(4.6, 0, -6.0)
	_table(tc, Vector3(2.4, 0.75, 1.0), "oak")
	for dx in [-0.8, 0.0, 0.8]:
		var lp := tc + Vector3(dx, 0, 0)
		g.cyl("black", lp + Vector3(0, (ROOM_H + 1.75) * 0.5, 0), 0.006, ROOM_H - 1.75, 6)
		g.cyl("lamp_shade", lp + Vector3(0, 1.66, 0), 0.04, 0.18, 18, 0.2)
		g.cyl("warm_light", lp + Vector3(0, 1.575, 0), 0.17, 0.01, 18)
	g.cyl("glass", tc + Vector3(0, 0.84, 0), 0.05, 0.18, 12)
	g.sphere("plant", tc + Vector3(0, 0.98, 0), 0.09, Vector3(1, 1.3, 1))
	for k in 3:
		g.cyl("cup", tc + Vector3(-0.7 + k * 0.6, 0.8, -0.25 + (k % 2) * 0.5), 0.04, 0.09, 12)
	var i := 1
	for dx in [-0.75, 0.0, 0.75]:
		_lounge_seat("pr%d" % i, "Stuhl im Pausenraum", tc + Vector3(dx, 0, -0.85), -PI / 2)
		i += 1
		_lounge_seat("pr%d" % i, "Stuhl im Pausenraum", tc + Vector3(dx, 0, 0.85), PI / 2)
		i += 1
	# Sofa an der Ostwand
	g.block("fabric", Vector3(9.2, 0.0, -7.2), Vector3(9.9, 0.42, -4.2), true)
	g.block("fabric", Vector3(9.65, 0.42, -7.2), Vector3(9.92, 0.95, -4.2))
	g.block("fabric", Vector3(9.2, 0.42, -7.3), Vector3(9.92, 0.65, -7.1))
	g.block("fabric", Vector3(9.2, 0.42, -4.3), Vector3(9.92, 0.65, -4.1))
	_lounge_seat("so1", "Sofa", Vector3(9.55, 0, -6.4), PI, false, 0.42)
	_lounge_seat("so2", "Sofa", Vector3(9.55, 0, -5.0), PI, false, 0.42)
	g.block("desk_top", Vector3(8.2, 0.38, -6.2), Vector3(8.8, 0.42, -5.2))
	g.block("metal", Vector3(8.45, 0, -5.75), Vector3(8.55, 0.38, -5.65))
	# Teppich vor dem Sofa, Bilder, Wanduhr
	g.block("rug", Vector3(7.6, 0.0, -7.0), Vector3(9.1, 0.012, -4.4))
	for pic in [[Vector3(9.89, 1.55, -6.6), "art_a"], [Vector3(9.89, 1.55, -5.0), "art_b"]]:
		g.block("black", pic[0] + Vector3(-0.02, -0.38, -0.5), pic[0] + Vector3(0.0, 0.38, 0.5))
		g.block(pic[1], pic[0] + Vector3(-0.025, -0.33, -0.45), pic[0] + Vector3(-0.02, 0.33, 0.45))
	g.cyl_t("desk_white", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(3.0, 2.25, -2.69)), 0.17, 0.04, 24)
	g.cyl_t("black", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(3.0, 2.25, -2.7)), 0.18, 0.03, 24)
	g.box_t("black", Transform3D(Basis(Vector3.FORWARD, 0.6), Vector3(3.0, 2.29, -2.715)), Vector3(0.012, 0.11, 0.004))
	g.box_t("black", Transform3D(Basis(Vector3.FORWARD, -1.9), Vector3(3.04, 2.25, -2.715)), Vector3(0.012, 0.08, 0.004))
	_plant(Vector3(6.9, 0, -8.5), 1.2)
	_plant(Vector3(9.4, 0, -3.2), 0.9)
	# Pinnwand
	g.block("wood", Vector3(4.0, 1.2, -2.78), Vector3(6.2, 2.1, -2.75))
	_label("PAUSENRAUM\nDienstplan · Aushänge · Kochplan", Vector3(5.1, 1.65, -2.79), PI, 0.0024, Color(0.2, 0.15, 0.1), 40, 2.0, 0.8)
	_plant(Vector3(0.45, 0, -2.98), 0.9)
	_spot("murmur_soft", Vector3(4.6, 1.2, -6.0))

func _meeting_room() -> void:
	var x0 := 10.0
	var x1 := 16.0
	_room_walls(x0, x1)
	_floor("carpet", Rect2(x0, -9, x1 - x0, 6.4))
	g.wall("plaster", Vector2(x1, -9), Vector2(x1, -2.6), ROOM_H, 0.15)
	# Konferenztisch (Eiche) mit Konferenzstühlen, Telefon, Wasser
	var tc := Vector3(13.0, 0, -5.6)
	_table(tc, Vector3(1.3, 0.75, 3.2), "oak")
	var i := 1
	for dz in [-1.0, 0.0, 1.0]:
		_lounge_seat("bs%d" % i, "Stuhl im Besprechungsraum", tc + Vector3(-1.0, 0, dz), 0.0, true, 0.46, true)
		i += 1
		_lounge_seat("bs%d" % i, "Stuhl im Besprechungsraum", tc + Vector3(1.0, 0, dz), PI, true, 0.46, true)
		i += 1
	g.cyl("dark", tc + Vector3(0, 0.77, 0), 0.14, 0.035, 3)
	g.cyl("led_green", tc + Vector3(0, 0.79, 0), 0.02, 0.006, 8)
	for k in 3:
		g.cyl("water", tc + Vector3(-0.2 + k * 0.2, 0.88, -1.15), 0.035, 0.26, 10)
		g.cyl("glass", tc + Vector3(-0.3 + k * 0.3, 0.8, 0.9), 0.035, 0.1, 10)
	g.block("paper", tc + Vector3(-0.5, 0.75, 0.3), tc + Vector3(-0.29, 0.755, 0.6))
	g.block("paper", tc + Vector3(0.3, 0.75, -0.6), tc + Vector3(0.51, 0.755, -0.3))
	# Großbildschirm mit Lowboard an der Nordwand
	g.block("bezel", Vector3(11.6, 1.05, -8.87), Vector3(14.4, 2.65, -8.82))
	_screen_quad("screen_a", Vector3(13.0, 1.85, -8.815), Vector2(2.74, 1.54), 0.0)
	g.block("oak", Vector3(11.8, 0.0, -8.86), Vector3(14.2, 0.55, -8.45), true)
	g.block("cabinet", Vector3(11.8, 0.05, -8.452), Vector3(14.2, 0.5, -8.45))
	g.block("dark", Vector3(12.8, 0.55, -8.75), Vector3(13.2, 0.62, -8.6))
	# Whiteboard mit Ablage an der Ostwand
	g.block("frame", Vector3(15.88, 0.9, -7.3), Vector3(15.92, 2.05, -4.3))
	g.block("desk_white", Vector3(15.87, 0.93, -7.27), Vector3(15.88, 2.02, -4.33))
	g.block("frame", Vector3(15.78, 0.88, -7.2), Vector3(15.88, 0.91, -4.4))
	for k in 3:
		g.cyl_t(["logo_a", "fruit_r", "black"][k], Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(15.83, 0.925, -6.5 + k * 0.2)), 0.01, 0.13, 6)
	_label("Lagebesprechung Schichtwechsel\n– Übergabe offener Einsätze\n– Ausfälle Fahrzeuge / Wachen\n– Übung Großschadenslage Do.", Vector3(15.865, 1.5, -5.8), -PI / 2, 0.0025, Color(0.15, 0.25, 0.6), 40, 2.6, 0.95)
	# Flipchart, Sideboard mit Thermoskannen, Uhr, Bild, Pflanze
	var fp := Vector3(15.2, 0, -3.4)
	for s in [-1.0, 1.0]:
		g.box_t("metal", Transform3D(Basis(Vector3.FORWARD, s * 0.12), fp + Vector3(s * 0.25, 0.9, 0)), Vector3(0.025, 1.8, 0.025))
	g.box_t("metal", Transform3D(Basis(Vector3.RIGHT, 0.3), fp + Vector3(0, 0.85, 0.25)), Vector3(0.025, 1.7, 0.025))
	g.block("paper", fp + Vector3(-0.35, 1.0, -0.03), fp + Vector3(0.35, 1.85, -0.01))
	g.collider(fp + Vector3(0, 0.9, 0.1), Vector3(0.7, 1.8, 0.4))
	g.block("oak", Vector3(10.08, 0.0, -7.6), Vector3(10.5, 0.85, -5.2), true)
	for k in 2:
		g.cyl("steel", Vector3(10.3, 1.0, -7.2 + k * 0.3), 0.06, 0.3, 12)
	for k in 6:
		g.cyl("cup", Vector3(10.25, 0.9, -6.4 + k * 0.17), 0.04, 0.09, 12)
	_wall_clock(Vector3(10.085, 2.3, -4.0), PI / 2)
	_picture(Vector3(10.09, 1.6, -3.6), PI / 2, 0.9, 0.6, "art_c")
	_plant(Vector3(15.4, 0, -8.4), 1.0)

func _toilets() -> void:
	for room in [[16.0, 19.0, "WC Damen", false], [19.0, 22.0, "WC Herren", true]]:
		var x0: float = room[0]
		var x1: float = room[1]
		var men: bool = room[3]
		var wx0 := x0 + 0.075
		var wx1 := x1 - 0.075
		_room_walls(x0, x1, false)
		_floor("tiles_floor", Rect2(x0, -9, x1 - x0, 6.4))
		g.wall("plaster", Vector2(x1, -9), Vector2(x1, -2.6), ROOM_H, 0.15)
		# Wandfliesen bis 2,10 m (Tür zum Flur ausgespart)
		g.block("tiles_wall", Vector3(wx0, 0, -8.875), Vector3(wx1, 2.1, -8.865))
		g.block("tiles_wall", Vector3(wx0, 0, -8.875), Vector3(wx0 + 0.01, 2.1, -2.675))
		g.block("tiles_wall", Vector3(wx1 - 0.01, 0, -8.875), Vector3(wx1, 2.1, -2.675))
		g.block("tiles_wall", Vector3(wx0, 0, -2.685), Vector3(x0 + 0.95, 2.1, -2.675))
		g.block("tiles_wall", Vector3(x0 + 2.05, 0, -2.685), Vector3(wx1, 2.1, -2.675))
		# Kabinen (raumhohe HPL-Trennwände, Türen leicht geöffnet)
		var cabins := 1 if men else 2
		var cw := (wx1 - wx0) / 2.0
		for k in cabins:
			var cx0 := wx0 + k * cw
			var cx1 := cx0 + cw
			var ccx := (cx0 + cx1) * 0.5
			if k == 0 or not men:
				g.block("hpl", Vector3(cx1 - 0.015, 0.15, -8.875), Vector3(cx1 + 0.015, 2.05, -7.35), true)
			g.block("hpl", Vector3(cx0 + 0.02, 0.15, -7.37), Vector3(cx0 + 0.3, 2.05, -7.34), true)
			g.block("hpl", Vector3(cx1 - 0.2, 0.15, -7.37), Vector3(cx1 - 0.015, 2.05, -7.34), true)
			var dw := cw - 0.52
			g.box_t("hpl", Transform3D(Basis(Vector3.UP, 0.5), Vector3(cx0 + 0.3 + cos(0.5) * dw * 0.5, 1.1, -7.355 - sin(0.5) * dw * 0.5)), Vector3(dw, 1.9, 0.025))
			g.box_t("metal", Transform3D(Basis(Vector3.UP, 0.5), Vector3(cx0 + 0.3 + cos(0.5) * dw * 0.92, 1.0, -7.33 - sin(0.5) * dw * 0.92)), Vector3(0.1, 0.03, 0.03))
			# Vorwand, wandhängendes WC mit Sitz, Drückerplatte, Papier- und Bürstenhalter
			g.block("tiles_wall", Vector3(cx0 + 0.03, 0, -8.875), Vector3(cx1 - 0.03, 1.1, -8.68))
			g.block("ceramic", Vector3(ccx - 0.18, 0.28, -8.68), Vector3(ccx + 0.18, 0.42, -8.35), true)
			g.sphere("ceramic", Vector3(ccx, 0.36, -8.33), 0.18, Vector3(1.0, 0.45, 0.8))
			g.cyl("desk_white", Vector3(ccx, 0.43, -8.42), 0.19, 0.025, 20)
			g.block("desk_white", Vector3(ccx - 0.12, 0.85, -8.68), Vector3(ccx + 0.12, 1.0, -8.67))
			g.block("metal", Vector3(ccx - 0.05, 0.9, -8.672), Vector3(ccx + 0.05, 0.96, -8.665))
			g.cyl_t("paper", Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(cx1 - 0.08, 0.7, -8.3)), 0.06, 0.1, 12)
			g.block("metal", Vector3(cx1 - 0.03, 0.75, -8.34), Vector3(cx1 - 0.015, 0.78, -8.26))
			g.cyl("metal", Vector3(cx0 + 0.15, 0.2, -8.6), 0.05, 0.4, 10)
		if men:
			# zwei Urinale mit Schamwand an der Ostwand
			for k in 2:
				var uz := -6.7 + k * 0.8
				g.block("ceramic", Vector3(wx1 - 0.32, 0.5, uz - 0.18), Vector3(wx1 - 0.01, 0.95, uz + 0.18), true)
				g.sphere("ceramic", Vector3(wx1 - 0.3, 0.6, uz), 0.15, Vector3(0.8, 0.9, 1.0))
				g.block("desk_white", Vector3(wx1 - 0.012, 1.15, uz - 0.06), Vector3(wx1 - 0.005, 1.25, uz + 0.06))
			g.block("hpl", Vector3(wx1 - 0.45, 0.5, -6.31), Vector3(wx1 - 0.01, 1.45, -6.29), true)
		# Waschtisch mit zwei Becken, Spiegel, Spender, Händetrockner
		var sz0 := -6.3
		var sz1 := -4.4
		g.block("ceramic", Vector3(wx0, 0.82, sz0), Vector3(wx0 + 0.52, 0.86, sz1), true)
		g.block("hpl", Vector3(wx0, 0.7, sz0), Vector3(wx0 + 0.5, 0.82, sz1))
		for k in 2:
			var bz := sz0 + 0.48 + k * 0.95
			g.block("dark", Vector3(wx0 + 0.12, 0.855, bz - 0.2), Vector3(wx0 + 0.42, 0.862, bz + 0.2))
			g.cyl("metal", Vector3(wx0 + 0.07, 0.96, bz), 0.016, 0.2, 8)
			g.box_t("metal", Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(wx0 + 0.14, 1.05, bz)), Vector3(0.02, 0.14, 0.02))
			g.block("desk_white", Vector3(wx0 + 0.005, 1.0, bz + 0.32), Vector3(wx0 + 0.09, 1.2, bz + 0.4))
		g.block("mirror", Vector3(wx0 + 0.008, 1.1, sz0 + 0.05), Vector3(wx0 + 0.018, 1.95, sz1 - 0.05))
		g.block("desk_white", Vector3(wx0 + 0.008, 1.2, -4.15), Vector3(wx0 + 0.13, 1.55, -3.75))
		g.cyl("dark", Vector3(wx0 + 0.2, 0.3, -3.95), 0.16, 0.6, 14)
		g.block("steel", Vector3(wx1 - 0.15, 1.1, -4.0), Vector3(wx1 - 0.01, 1.4, -3.7))
		_area({"kind": "sink", "text": "Hände waschen"}, Vector3(wx0 + 0.45, 1.0, (sz0 + sz1) * 0.5), Vector3(0.7, 0.6, 1.8))
		_spot("water", Vector3(wx0 + 0.3, 1.0, (sz0 + sz1) * 0.5))

func _server_room() -> void:
	var x0 := 22.0
	var x1 := 29.0
	_room_walls(x0, x1, false)
	_floor("raised_floor", Rect2(x0, -9, x1 - x0, 6.4))
	g.wall("plaster", Vector2(x1, -9), Vector2(x1, -2.6), ROOM_H, 0.15)
	# Zwei Rack-Reihen mit Kaltgang dazwischen (Fronten zueinander)
	for row in [[-7.6, 1.0], [-5.0, -1.0]]:
		var rz: float = row[0]
		var face: float = row[1]
		for k in 8:
			var x := x0 + 1.1 + k * 0.64
			g.block("rack", Vector3(x, 0, rz - 0.5), Vector3(x + 0.62, 2.05, rz + 0.5), true)
			g.block("rack_door", Vector3(x + 0.02, 0.06, rz + face * 0.5), Vector3(x + 0.6, 2.0, rz + face * 0.505))
			g.block("rack_door", Vector3(x + 0.02, 0.06, rz - face * 0.5), Vector3(x + 0.6, 2.0, rz - face * 0.505))
			g.block("metal", Vector3(x + 0.52, 0.95, rz + face * 0.5), Vector3(x + 0.54, 1.15, rz + face * 0.53))
			for led in 4:
				var lm := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.025, 0.012, 0.01)
				lm.mesh = bm
				lm.material_override = MATS.get_mat("led_green" if (k + led) % 3 else "led_blue")
				lm.position = Vector3(x + 0.08 + led * 0.1, 0.35 + ((k * 7 + led * 3) % 10) * 0.15, rz + face * 0.512)
				root.add_child(lm)
				leds.append(lm)
		# Kabeltrasse über der Reihe
		g.block("metal", Vector3(x0 + 1.0, 2.35, rz - 0.22), Vector3(x0 + 6.3, 2.37, rz - 0.2))
		g.block("metal", Vector3(x0 + 1.0, 2.35, rz + 0.2), Vector3(x0 + 6.3, 2.37, rz + 0.22))
		var cx := x0 + 1.1
		while cx < x0 + 6.3:
			g.block("metal", Vector3(cx, 2.33, rz - 0.22), Vector3(cx + 0.02, 2.35, rz + 0.22))
			cx += 0.3
		for c in 4:
			g.box_t(["logo_a", "fruit_y", "fruit_r", "art_c"][c], Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(x0 + 3.65, 2.39, rz - 0.12 + c * 0.08)), Vector3(0.03, 5.2, 0.03))
		for k in 8:
			g.cyl("metal", Vector3(x0 + 1.4 + k * 0.64, 2.2, rz), 0.012, 0.3, 6)
	# Präzisionsklima, USV, Löschanlage
	g.block("plaster_grey", Vector3(x0 + 0.1, 0, -8.8), Vector3(x0 + 0.95, 2.1, -7.2), true)
	var gy := 0.3
	while gy < 1.9:
		g.block("dark", Vector3(x0 + 0.95, gy, -8.7), Vector3(x0 + 0.96, gy + 0.02, -7.3))
		gy += 0.08
	g.block("screen_off", Vector3(x0 + 0.96, 1.75, -8.2), Vector3(x0 + 0.965, 1.85, -8.0))
	_label("Präzisionsklima", Vector3(x0 + 0.966, 1.95, -8.0), PI / 2, 0.003, Color(0.15, 0.15, 0.15), 36, 0.8, 0.08)
	for k in 2:
		var ux := x1 - 1.0 + k * 0.45
		g.block("plaster_grey", Vector3(ux, 0, -8.85), Vector3(ux + 0.42, 1.9, -8.15), true)
		g.block("led_green", Vector3(ux + 0.15, 1.5, -8.149), Vector3(ux + 0.27, 1.58, -8.145))
	_label("USV", Vector3(x1 - 0.55, 1.75, -8.144), 0.0, 0.004, Color(0.15, 0.15, 0.15), 40, 0.3, 0.1)
	for k in 3:
		g.cyl("red_ext", Vector3(x1 - 0.35, 0.75, -6.9 + k * 0.32), 0.13, 1.5, 16)
		g.cyl("metal", Vector3(x1 - 0.35, 1.55, -6.9 + k * 0.32), 0.04, 0.12, 8)
	g.collider(Vector3(x1 - 0.35, 0.75, -6.58), Vector3(0.3, 1.5, 0.95))
	_label("LÖSCHANLAGE – bei Alarm Raum verlassen", Vector3(x1 - 0.09, 1.95, -6.6), -PI / 2, 0.0024, Color(0.6, 0.08, 0.05), 36, 1.4, 0.1)
	# Systemkonsole
	g.block("desk_top", Vector3(x1 - 1.8, 0.72, -3.4), Vector3(x1 - 0.2, 0.75, -2.75))
	g.block("cabinet", Vector3(x1 - 1.78, 0, -3.38), Vector3(x1 - 1.4, 0.72, -2.77), true)
	g.collider(Vector3(x1 - 1.0, 0.37, -3.07), Vector3(1.6, 0.74, 0.65))
	g.block("bezel", Vector3(x1 - 1.4, 0.8, -2.83), Vector3(x1 - 0.8, 1.17, -2.8))
	_screen_quad("screen_c", Vector3(x1 - 1.1, 0.985, -2.835), Vector2(0.57, 0.34), PI)
	g.block("dark", Vector3(x1 - 1.3, 0.75, -3.2), Vector3(x1 - 0.85, 0.77, -3.05))
	_area({"kind": "server", "text": "Einsatzleitsystem – Systemkonsole"}, Vector3(x1 - 1.0, 1.0, -3.4), Vector3(1.6, 0.8, 0.8))
	_label("ELS-RECHENZENTRUM\nZutritt nur für Systembetreuung", Vector3((x0 + x1) * 0.5, 2.45, -8.86), 0.0, 0.004, Color(0.2, 0.2, 0.22), 48, 4.0, 0.5)
	_spot("server", Vector3((x0 + x1) * 0.5, 1.2, -6.3))

func _office() -> void:
	var x0 := 29.0
	var x1 := 36.0
	_room_walls(x0, x1)
	_floor("carpet", Rect2(x0, -9, x1 - x0, 6.4))
	g.wall("plaster", Vector2(x1, -9.1), Vector2(x1, -2.6), ROOM_H, 0.2)
	# Schreibtisch (Eiche) mit zwei Monitoren, Blick zur Tür
	var dc := Vector3(32.4, 0, -6.5)
	g.block("oak", dc + Vector3(-1.0, 0.72, -0.4), dc + Vector3(1.0, 0.75, 0.4))
	g.block("cabinet", dc + Vector3(-0.98, 0, -0.38), dc + Vector3(-0.55, 0.72, 0.38))
	g.block("cabinet", dc + Vector3(0.96, 0, -0.38), dc + Vector3(0.98, 0.72, 0.38))
	g.block("cabinet", dc + Vector3(-0.55, 0.2, 0.36), dc + Vector3(0.96, 0.72, 0.38))
	g.collider(dc + Vector3(0, 0.37, 0), Vector3(2.0, 0.74, 0.8))
	for k in 2:
		var mx := dc.x - 0.62 + k * 0.64
		g.block("bezel", Vector3(mx, 0.85, dc.z + 0.12), Vector3(mx + 0.58, 1.2, dc.z + 0.145))
		_screen_quad(["screen_b", "screen_a"][k], Vector3(mx + 0.29, 1.025, dc.z + 0.11), Vector2(0.55, 0.32), PI)
		g.block("metal", Vector3(mx + 0.26, 0.75, dc.z + 0.15), Vector3(mx + 0.32, 0.85, dc.z + 0.2))
	g.block("dark", dc + Vector3(-0.25, 0.75, -0.25), dc + Vector3(0.2, 0.77, -0.1))
	g.block("dark", dc + Vector3(0.55, 0.75, -0.2), dc + Vector3(0.78, 0.8, 0.05))
	g.cyl("black", dc + Vector3(-0.85, 0.76, 0.25), 0.07, 0.02, 12)
	g.box_t("black", Transform3D(Basis(Vector3.FORWARD, 0.4), dc + Vector3(-0.78, 0.95, 0.25)), Vector3(0.02, 0.4, 0.02))
	g.cyl("lamp_shade", dc + Vector3(-0.68, 1.12, 0.25), 0.03, 0.09, 12, 0.07)
	g.block("paper", dc + Vector3(0.3, 0.75, -0.35), dc + Vector3(0.51, 0.757, -0.05))
	g.cyl("cup", dc + Vector3(0.85, 0.8, -0.3), 0.04, 0.09, 12)
	_chair(Transform3D(Basis(Vector3.UP, -PI / 2), dc + Vector3(0, 0, -0.85)), true)
	_lounge_seat("of1", "Bürostuhl Schichtführung", dc + Vector3(0, 0, -0.85), -PI / 2, false, 0.49)
	g.collider(dc + Vector3(0, 0.5, -0.85), Vector3(0.5, 1.0, 0.5))
	# Regale mit Ordnern (Alarm- und Ausrückeordnung, Dienstanweisungen)
	_shelf(Vector3(35.88, 0, -8.7), 2.2, -PI / 2)
	_shelf(Vector3(35.88, 0, -6.4), 2.2, -PI / 2)
	_label("Alarm- und Ausrückeordnung · Sonderlagen · Dienstanweisungen", Vector3(35.87, 1.35, -6.4), -PI / 2, 0.0022, Color(0.2, 0.2, 0.2), 40, 3.8, 0.12)
	# Dienstplan-Whiteboard an der Westwand
	g.block("frame", Vector3(29.075, 1.0, -7.8), Vector3(29.1, 2.0, -5.6))
	g.block("desk_white", Vector3(29.1, 1.03, -7.77), Vector3(29.11, 1.97, -5.63))
	_label("DIENSTPLAN\nFrühdienst 07–19 · Nachtdienst 19–07\nSchichtführung: siehe Aushang", Vector3(29.115, 1.5, -6.7), PI / 2, 0.0025, Color(0.15, 0.2, 0.45), 40, 2.0, 0.85)
	# Besprechungsecke, Garderobe, Pflanze, Bild
	g.cyl("oak", Vector3(30.4, 0.72, -4.0), 0.45, 0.035, 24)
	g.cyl("metal", Vector3(30.4, 0.36, -4.0), 0.04, 0.72, 8)
	g.collider_cyl(Vector3(30.4, 0.37, -4.0), 0.45, 0.74)
	_lounge_seat("of2", "Stuhl im Büro", Vector3(29.6, 0, -4.0), 0.0)
	_lounge_seat("of3", "Stuhl im Büro", Vector3(30.4, 0, -4.85), -PI / 2)
	var cr := Vector3(34.9, 0, -3.2)
	g.cyl("metal", cr + Vector3(0, 0.9, 0), 0.02, 1.8, 8)
	g.cyl("dark", cr + Vector3(0, 0.02, 0), 0.22, 0.04, 14)
	g.block("trousers", cr + Vector3(-0.15, 0.95, 0.0), cr + Vector3(0.15, 1.7, 0.12))
	g.collider_cyl(cr + Vector3(0, 0.9, 0), 0.2, 1.8)
	_picture(Vector3(29.09, 1.6, -3.6), PI / 2, 0.8, 0.6, "art_b")
	_wall_clock(Vector3(34.2, 2.2, -2.69), PI)
	_plant(Vector3(29.6, 0, -8.4), 1.1)

func _lockers() -> void:
	var x0 := -8.0
	var x1 := 0.0
	_room_walls(x0, x1)
	_floor("tiles_floor", Rect2(x0, -9, x1 - x0, 6.4))
	g.wall("plaster", Vector2(x1, -9), Vector2(x1, -2.6), ROOM_H, 0.15)
	# Spindreihen (zweitürig, mit Lüftungsschlitzen, Nummern) an West- und Ostwand
	var nr := 1
	for side in [[x0 + 0.125, 1.0], [x1 - 0.075, -1.0]]:
		var wx: float = side[0]
		var dir: float = side[1]
		var front := wx + dir * 0.5
		var zz := -8.7
		while zz < -4.1:
			var a := Vector3(minf(wx, front), 0.1, zz)
			var b := Vector3(maxf(wx, front), 1.9, zz + 0.4)
			g.block("locker", a, b, true)
			g.block("plinth", Vector3(a.x, 0, zz), Vector3(b.x, 0.1, zz + 0.4))
			for tier in 2:
				var y0 := 0.14 + tier * 0.88
				var fx := front + dir * 0.005
				g.block("locker_door", Vector3(minf(front, fx), y0, zz + 0.015), Vector3(maxf(front, fx), y0 + 0.84, zz + 0.385))
				for sl in 4:
					var sy := y0 + 0.62 + sl * 0.04
					g.block("dark", Vector3(minf(front, fx + dir * 0.002), sy, zz + 0.12), Vector3(maxf(front, fx + dir * 0.002), sy + 0.012, zz + 0.28))
				g.block("metal", Vector3(minf(front, fx + dir * 0.02), y0 + 0.38, zz + 0.31), Vector3(maxf(front, fx + dir * 0.02), y0 + 0.5, zz + 0.34))
				_label(str(nr), Vector3(fx + dir * 0.004, y0 + 0.75, zz + 0.2), PI / 2 if dir > 0 else -PI / 2, 0.002, Color(0.1, 0.1, 0.1), 36, 0.1, 0.06)
				nr += 1
			zz += 0.41
	# Sitzbänke mit Schuhablage
	for bx in [-4.4]:
		g.block("oak", Vector3(bx - 0.2, 0.42, -7.2), Vector3(bx + 0.2, 0.46, -4.4), true)
		g.block("metal", Vector3(bx - 0.18, 0.1, -7.15), Vector3(bx + 0.18, 0.12, -4.45))
		for zl in [-7.1, -4.5]:
			g.block("metal", Vector3(bx - 0.17, 0, zl - 0.02), Vector3(bx + 0.17, 0.42, zl + 0.02))
	_lounge_seat("uk1", "Bank in der Umkleide", Vector3(-4.4, 0, -6.2), 0.0, false, 0.46)
	_lounge_seat("uk2", "Bank in der Umkleide", Vector3(-4.4, 0, -5.4), PI, false, 0.46)
	# Spiegel, Garderobenhaken, Wäschesammler
	g.block("mirror", Vector3(-3.4, 0.9, -2.69), Vector3(-2.2, 2.0, -2.68))
	g.block("oak", Vector3(-6.2, 1.62, -2.7), Vector3(-5.0, 1.68, -2.66))
	for k in 5:
		g.block("metal", Vector3(-6.1 + k * 0.26, 1.55, -2.74), Vector3(-6.06 + k * 0.26, 1.6, -2.66))
	g.block("fabric", Vector3(-5.9, 0.95, -2.78), Vector3(-5.6, 1.55, -2.7))
	g.cyl("fabric_red", Vector3(-1.2, 0.35, -3.3), 0.22, 0.7, 14)
	g.collider_cyl(Vector3(-1.2, 0.35, -3.3), 0.22, 0.7)
	_area({"kind": "info", "text": "Spind – Dienstkleidung, Einsatzjacke und Funkmeldeempfänger."}, Vector3(x0 + 0.9, 1.0, -6.4), Vector3(0.6, 1.6, 4.6))

func _outside() -> void:
	# Umgebung hinter den Fenstern: Vorplatz, Wiese und Nachbargebäude
	g.block("outside", Vector3(-60, -0.08, -60), Vector3(90, -0.06, 80))
	g.block("asphalt", Vector3(-30, -0.06, 18.3), Vector3(60, -0.05, 30))
	g.block("asphalt", Vector3(-30, -0.06, -30), Vector3(-8.3, -0.05, 18.3))
	for b in [[Vector3(-10, 0, 34), Vector3(14, 14, 46)], [Vector3(20, 0, 36), Vector3(46, 9, 50)], [Vector3(-40, 0, -6), Vector3(-26, 18, 16)], [Vector3(-12, 0, -40), Vector3(30, 11, -24)]]:
		g.block("outside_bld", b[0], b[1])
	for i in 9:
		var p := Vector3(-4 + i * 5.5, 0, 25.0)
		g.cyl("dark", p + Vector3(0, 1.2, 0), 0.12, 2.4, 8)
		g.sphere("plant", p + Vector3(0, 3.4, 0), 1.6, Vector3(1, 1.2, 1))

func _lights() -> void:
	var q := quality
	var hall_l: Array = []
	for x in [3.0, 9.5, 16.0, 22.5, 29.0, 34.0]:
		for z in [4.2, 10.2]:
			hall_l.append([Vector3(x, 4.7, z), 10.0, 0.75])
	for x in [6.0, 18.0, 30.0]:
		hall_l.append([Vector3(x, 2.6, 16.0), 7.0, 0.5])
	hall_l.append([Vector3(33.5, 3.5, 9.5), 7.0, 0.45])
	for x in [-4.0, 5.0, 15.0, 25.0, 33.0]:
		hall_l.append([Vector3(x, 2.6, -1.3), 6.0, 0.55])
	hall_l.append([Vector3(-4.0, 2.6, 5.0), 7.0, 0.6])
	for c in [[-4.0, -5.8], [2.5, -5.8], [7.5, -5.8], [13.0, -5.8], [17.5, -5.8], [20.5, -5.8], [25.5, -5.8], [32.5, -5.8]]:
		hall_l.append([Vector3(c[0], 2.6, c[1]), 6.5, 0.6])
	for xx in [6.0, 18.0, 30.0]:
		hall_l.append([Vector3(xx, 5.0, 16.0), 6.0, 0.35])
	for d in hall_l:
		var l := OmniLight3D.new()
		l.position = d[0]
		l.omni_range = d[1]
		l.light_energy = d[2]
		l.light_color = Color(1.0, 0.97, 0.92)
		l.omni_attenuation = 0.8
		l.shadow_enabled = false
		l.light_specular = 0.3
		root.add_child(l)
	if q >= 2:
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(160), 0)
		sun.light_energy = 0.55
		sun.light_color = Color(1.0, 0.96, 0.88)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 45.0
		root.add_child(sun)
