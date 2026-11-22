extends RefCounted
## Baukasten für die begehbare Leitstelle: sammelt statische Geometrie pro Material und
## fasst sie zu wenigen Meshes zusammen (wenige Draw-Calls, auch auf schwächeren Rechnern).
## Kollisionen werden als einfache Quader in einem gemeinsamen StaticBody3D angelegt.

const MATS := preload("res://src/building/materials.gd")

var root: Node3D
var body: StaticBody3D
var _st := {}          # Materialname -> SurfaceTool
var _mesh_cache := {}
var colliders := 0

func _init(parent: Node3D) -> void:
	root = parent
	body = StaticBody3D.new()
	body.name = "Kollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)

func _tool(mat: String) -> SurfaceTool:
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
	return _st[mat]

func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]

func _cyl_mesh(r_top: float, r_bot: float, h: float, seg: int) -> CylinderMesh:
	var key := "c%.3f_%.3f_%.3f_%d" % [r_top, r_bot, h, seg]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bot
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		_mesh_cache[key] = m
	return _mesh_cache[key]

func _sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 14
		m.rings = 8
		_mesh_cache[key] = m
	return _mesh_cache[key]

## Quader mit Mittelpunkt c und Größe s, optional um die Y-Achse gedreht (Bogenmaß).
func box(mat: String, c: Vector3, s: Vector3, rot_y := 0.0, collide := false) -> void:
	var t := Transform3D(Basis(Vector3.UP, rot_y), c)
	_tool(mat).append_from(_box_mesh(s), 0, t)
	if collide:
		collider(c, s, rot_y)

## Quader über zwei Eckpunkte (achsparallel).
func block(mat: String, a: Vector3, b: Vector3, collide := false) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	box(mat, (lo + hi) * 0.5, hi - lo, 0.0, collide)

func box_t(mat: String, t: Transform3D, s: Vector3) -> void:
	_tool(mat).append_from(_box_mesh(s), 0, t)

func cyl(mat: String, c: Vector3, r: float, h: float, seg := 12, r_bot := -1.0) -> void:
	_tool(mat).append_from(_cyl_mesh(r, r if r_bot < 0.0 else r_bot, h, seg), 0, Transform3D(Basis(), c))

func cyl_t(mat: String, t: Transform3D, r: float, h: float, seg := 10) -> void:
	_tool(mat).append_from(_cyl_mesh(r, r, h, seg), 0, t)

func sphere(mat: String, c: Vector3, r: float, scale := Vector3.ONE) -> void:
	_tool(mat).append_from(_sphere_mesh(r), 0, Transform3D(Basis().scaled(scale), c))

func collider(c: Vector3, s: Vector3, rot_y := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	cs.transform = Transform3D(Basis(Vector3.UP, rot_y), c)
	body.add_child(cs)
	colliders += 1

func collider_cyl(c: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = c
	body.add_child(cs)
	colliders += 1

## Gebogener Körper (Ringsegment) um den Mittelpunkt c in der XZ-Ebene:
## Innen-/Außenradius, Winkel a0..a1 (Bogenmaß, 0 = +X, positiv Richtung -Z), Höhe y0..y1.
func arc(mat: String, c: Vector3, r_in: float, r_out: float, a0: float, a1: float, y0: float, y1: float, seg := 12, xform := Transform3D()) -> void:
	# eigenes Teil-Mesh (gleiches Vertexformat wie die Grundkörper), dann anhängen
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts_in: Array = []
	var pts_out: Array = []
	for i in seg + 1:
		var a := lerpf(a0, a1, float(i) / seg)
		var d := Vector3(cos(a), 0.0, -sin(a))
		pts_in.append(c + d * r_in)
		pts_out.append(c + d * r_out)
	var up := Vector3(0, y1, 0)
	var lo := Vector3(0, y0, 0)
	for i in seg:
		var a := lerpf(a0, a1, (float(i) + 0.5) / seg)
		var n_out := Vector3(cos(a), 0.0, -sin(a))
		# Oberseite / Unterseite
		_quad(st, xform, pts_in[i] + up, pts_in[i + 1] + up, pts_out[i + 1] + up, pts_out[i] + up, Vector3.UP)
		_quad(st, xform, pts_in[i] + lo, pts_out[i] + lo, pts_out[i + 1] + lo, pts_in[i + 1] + lo, Vector3.DOWN)
		# Außen- und Innenfläche
		_quad(st, xform, pts_out[i] + lo, pts_out[i] + up, pts_out[i + 1] + up, pts_out[i + 1] + lo, n_out)
		_quad(st, xform, pts_in[i + 1] + lo, pts_in[i + 1] + up, pts_in[i] + up, pts_in[i] + lo, -n_out)
	# Stirnseiten
	var e0 := Vector3(sin(a0), 0.0, cos(a0))
	var e1 := -Vector3(sin(a1), 0.0, cos(a1))
	_quad(st, xform, pts_in[0] + lo, pts_in[0] + up, pts_out[0] + up, pts_out[0] + lo, -e0)
	_quad(st, xform, pts_out[seg] + lo, pts_out[seg] + up, pts_in[seg] + up, pts_in[seg] + lo, -e1)
	st.index()
	st.generate_tangents()
	_tool(mat).append_from(st.commit(), 0, Transform3D())

func _quad(st: SurfaceTool, t: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	a = t * a; b = t * b; c = t * c; d = t * d
	# Normale aus der Geometrie bestimmen (Wicklung so, dass sie nach außen zeigt)
	var gn := (b - a).cross(c - a).normalized()
	var wn := (t.basis * n).normalized()
	if gn.dot(wn) > 0.0:
		var tmp := b
		b = d
		d = tmp
	for p in [a, b, c, a, c, d]:
		st.set_normal(wn)
		st.set_uv(Vector2(p.x + p.z, p.y))
		st.add_vertex(p)

## Wand von a nach b (in der XZ-Ebene) mit Öffnungen [{"at": Abstand ab a, "w": Breite, "h": Höhe, "sill": Brüstung}].
func wall(mat: String, a: Vector2, b: Vector2, h: float, thick := 0.2, openings: Array = [], y0 := 0.0, collide := true) -> void:
	var dir := (b - a)
	var length := dir.length()
	dir = dir / length
	var rot := -atan2(dir.y, dir.x)
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return float(p["at"]) < float(q["at"]))
	var cur := 0.0
	for o in ops:
		var s0: float = float(o["at"]) - float(o["w"]) * 0.5
		var s1: float = float(o["at"]) + float(o["w"]) * 0.5
		if s0 > cur:
			_wall_piece(mat, a, dir, rot, cur, s0, y0, y0 + h, thick, collide)
		var sill := float(o.get("sill", 0.0))
		if sill > 0.0:
			_wall_piece(mat, a, dir, rot, s0, s1, y0, y0 + sill, thick, collide)
		var top := sill + float(o["h"])
		if top < h:
			_wall_piece(mat, a, dir, rot, s0, s1, y0 + top, y0 + h, thick, collide)
		cur = s1
	if cur < length:
		_wall_piece(mat, a, dir, rot, cur, length, y0, y0 + h, thick, collide)

func _wall_piece(mat: String, a: Vector2, dir: Vector2, rot: float, s0: float, s1: float, y0: float, y1: float, thick: float, collide: bool) -> void:
	if s1 - s0 < 0.001 or y1 - y0 < 0.001:
		return
	var mid := a + dir * ((s0 + s1) * 0.5)
	box(mat, Vector3(mid.x, (y0 + y1) * 0.5, mid.y), Vector3(s1 - s0, y1 - y0, thick), rot, collide)

## Alle gesammelten Flächen als MeshInstance3D anlegen.
func commit() -> void:
	for mat in _st:
		var st: SurfaceTool = _st[mat]
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Geo_" + mat
		mi.mesh = mesh
		mi.material_override = MATS.get_mat(mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mat in ["glass", "screen_a", "screen_b", "screen_c", "emit_light"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)
	_st = {}
