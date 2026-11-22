extends Node3D
## Spielfigur (Disponent/in in Dienstkleidung) mit einfacher Lauf- und Sitzanimation.
## Blickrichtung: lokal -Z. Ursprung: zwischen den Füßen auf dem Boden.

const MATS = preload("res://src/building/materials.gd")
const HIP_Y := 0.92

var body: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var legs: Array = []      # [hüfte, knie]
var arms: Array = []      # [schulter, ellbogen]
var hand_r: Node3D
var item_node: Node3D
var name_label: Label3D
var phase := 0.0
var sit := 0.0            # 0 = stehen, 1 = sitzen
var sitting := false
var at_desk := false
var seat_h := 0.49
var speed := 0.0
var item := -1
var pitch := 0.0
var _prev := Vector3.ZERO
var _has_prev := false
var target_pos := Vector3.ZERO
var target_yaw := 0.0

static var _meshes := {}

static func _box(s: Vector3) -> BoxMesh:
	var k := str(s)
	if not _meshes.has(k):
		var m := BoxMesh.new()
		m.size = s
		_meshes[k] = m
	return _meshes[k]

static func _cap(r: float, h: float) -> CapsuleMesh:
	var k := "k%f_%f" % [r, h]
	if not _meshes.has(k):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 14
		m.rings = 4
		_meshes[k] = m
	return _meshes[k]

static func _sph(r: float) -> SphereMesh:
	var k := "s%f" % r
	if not _meshes.has(k):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 16
		m.rings = 10
		_meshes[k] = m
	return _meshes[k]

static func _cyl(r: float, h: float) -> CylinderMesh:
	var k := "c%f_%f" % [r, h]
	if not _meshes.has(k):
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 12
		_meshes[k] = m
	return _meshes[k]

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi

func _mat(base: String, tint: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = MATS.get_mat(base).duplicate()
	m.albedo_color = tint
	return m

## Aussehen aus einer Kennzahl ableiten (gleiche Person sieht bei allen Spielern gleich aus).
func setup(look_seed: int, display_name: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed * 7919 + 17
	var skin := _mat("skin", [Color(0.93, 0.78, 0.66), Color(0.86, 0.68, 0.55), Color(0.72, 0.53, 0.4), Color(0.55, 0.38, 0.27), Color(0.95, 0.82, 0.72)][rng.randi_range(0, 4)])
	var hair := _mat("hair", [Color(0.12, 0.09, 0.07), Color(0.35, 0.24, 0.14), Color(0.62, 0.48, 0.3), Color(0.5, 0.5, 0.5), Color(0.2, 0.14, 0.1)][rng.randi_range(0, 4)])
	var shirt := _mat("shirt", [Color(0.95, 0.95, 0.96), Color(0.95, 0.95, 0.96), Color(0.82, 0.88, 0.95)][rng.randi_range(0, 2)])
	var trousers := _mat("trousers", Color(0.1, 0.13, 0.2))
	var dark := MATS.get_mat("black")
	var long_hair := rng.randf() < 0.4
	body = Node3D.new()
	add_child(body)
	hips = Node3D.new()
	hips.position.y = HIP_Y
	body.add_child(hips)
	_part(hips, _cap(0.13, 0.4), trousers, Vector3(0, 0.02, 0), Vector3(1.0, 1.0, 0.75)).rotation.z = PI / 2
	_part(hips, _box(Vector3(0.37, 0.05, 0.23)), dark, Vector3(0, 0.1, 0))
	for s in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(s * 0.1, -0.04, 0)
		hips.add_child(hip)
		_part(hip, _cap(0.082, 0.5), trousers, Vector3(0, -0.23, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.45, 0)
		hip.add_child(knee)
		_part(knee, _cap(0.068, 0.46), trousers, Vector3(0, -0.21, 0))
		_part(knee, _cap(0.055, 0.26), dark, Vector3(0, -0.425, -0.05)).rotation.x = PI / 2
		legs.append([hip, knee])
	torso = Node3D.new()
	torso.position = Vector3(0, 0.1, 0)
	hips.add_child(torso)
	_part(torso, _cap(0.19, 0.62), shirt, Vector3(0, 0.3, 0), Vector3(1.05, 1.0, 0.62))
	_part(torso, _cap(0.07, 0.48), shirt, Vector3(0, 0.52, 0), Vector3(1.0, 1.0, 1.5)).rotation.z = PI / 2
	for s in [-1.0, 1.0]:
		_part(torso, _box(Vector3(0.12, 0.02, 0.07)), dark, Vector3(s * 0.15, 0.59, 0))
	_part(torso, _box(Vector3(0.08, 0.05, 0.01)), dark, Vector3(-0.1, 0.42, -0.118))
	_part(torso, _cyl(0.055, 0.1), skin, Vector3(0, 0.62, 0))
	head = Node3D.new()
	head.position = Vector3(0, 0.68, 0)
	torso.add_child(head)
	_part(head, _sph(0.115), skin, Vector3(0, 0.1, 0), Vector3(0.92, 1.08, 1.0))
	_part(head, _sph(0.12), hair, Vector3(0, 0.15, 0.02), Vector3(0.95, 0.85, 1.0))
	if long_hair:
		_part(head, _box(Vector3(0.2, 0.22, 0.08)), hair, Vector3(0, 0.03, 0.09))
	_part(head, _sph(0.022), skin, Vector3(0, 0.08, -0.115))
	for s in [-1.0, 1.0]:
		_part(head, _sph(0.012), dark, Vector3(s * 0.04, 0.12, -0.105))
		var sh := Node3D.new()
		sh.position = Vector3(s * 0.26, 0.5, 0)
		torso.add_child(sh)
		_part(sh, _cap(0.058, 0.34), shirt, Vector3(0, -0.13, 0))
		var el := Node3D.new()
		el.position = Vector3(0, -0.29, 0)
		sh.add_child(el)
		_part(el, _cap(0.045, 0.3), skin, Vector3(0, -0.13, 0))
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.29, 0)
		el.add_child(hand)
		_part(hand, _sph(0.045), skin, Vector3.ZERO, Vector3(0.9, 1.2, 1.0))
		if s > 0:
			hand_r = hand
		arms.append([sh, el])
	name_label = Label3D.new()
	name_label.text = display_name
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.pixel_size = 0.002
	name_label.font_size = 36
	name_label.outline_size = 8
	name_label.modulate = Color(1, 1, 1)
	name_label.outline_modulate = Color(0, 0, 0, 0.7)
	name_label.position = Vector3(0, 2.08, 0)
	name_label.no_depth_test = false
	add_child(name_label)

func set_display_name(n: String) -> void:
	if name_label != null and name_label.text != n:
		name_label.text = n

func set_item(kind: int) -> void:
	if kind == item:
		return
	item = kind
	if item_node != null:
		item_node.queue_free()
		item_node = null
	if kind <= 0 or hand_r == null:
		return
	item_node = Node3D.new()
	hand_r.add_child(item_node)
	match kind:
		1:
			_part(item_node, _cyl(0.04, 0.09), MATS.get_mat("cup"), Vector3(0, -0.03, -0.03))
			_part(item_node, _cyl(0.035, 0.005), MATS.get_mat("coffee"), Vector3(0, 0.013, -0.03))
		2:
			_part(item_node, _cyl(0.035, 0.11), MATS.get_mat("glass"), Vector3(0, -0.02, -0.03))
			_part(item_node, _cyl(0.032, 0.07), MATS.get_mat("water"), Vector3(0, -0.04, -0.03))
		3:
			_part(item_node, _cyl(0.11, 0.015), MATS.get_mat("cup"), Vector3(0, -0.05, -0.08))
			_part(item_node, _box(Vector3(0.1, 0.04, 0.08)), MATS.get_mat("food"), Vector3(0, -0.02, -0.08))

## Bewegung von außen (entfernte Spieler): weich zur Zielpose gleiten.
func follow(delta: float) -> void:
	var k := clampf(delta * 10.0, 0.0, 1.0)
	position = position.lerp(target_pos, k)
	rotation.y = lerp_angle(rotation.y, target_yaw, k)

func animate(delta: float) -> void:
	if _has_prev and delta > 0.0:
		var d := position - _prev
		d.y = 0.0
		speed = lerpf(speed, d.length() / delta, clampf(delta * 8.0, 0.0, 1.0))
	_prev = position
	_has_prev = true
	sit = move_toward(sit, 1.0 if sitting else 0.0, delta * 3.0)
	var walk := clampf(speed / 1.4, 0.0, 1.8) * (1.0 - sit)
	if walk > 0.05:
		phase = fmod(phase + delta * (4.2 + speed * 2.4), TAU)
	else:
		phase = lerpf(phase, 0.0 if phase < PI else TAU, clampf(delta * 4.0, 0, 1))
	var sw := sin(phase) * 0.55 * minf(walk, 1.2)
	# Beine: Hüfte vor/zurück, Knie beim Rückschwung gebeugt; beim Sitzen 90°
	for i in 2:
		var s := sw if i == 0 else -sw
		var hip: Node3D = legs[i][0]
		var knee: Node3D = legs[i][1]
		var knee_bend := maxf(0.0, -s) * 1.1 + 0.05 * walk
		hip.rotation.x = lerpf(s, deg_to_rad(88), sit)
		knee.rotation.x = lerpf(-knee_bend, deg_to_rad(-88), sit)
	# Körperhöhe: beim Sitzen auf Sitzhöhe absenken, beim Gehen leicht wippen
	body.position.y = lerpf(absf(sin(phase * 2.0)) * 0.025 * walk, seat_h + 0.02 - HIP_Y, sit)
	torso.rotation.x = lerpf(-0.04 * walk, deg_to_rad(-4) if at_desk else deg_to_rad(4), sit)
	# Arme: Gegenschwung, am Arbeitsplatz Hände auf der Tastatur
	for i in 2:
		var sh: Node3D = arms[i][0]
		var el: Node3D = arms[i][1]
		var s := -sw if i == 0 else sw
		var holding := i == 1 and item > 0
		var stand_sh := s * 0.8
		var stand_el := -0.15 - maxf(0.0, s) * 0.3
		if holding:
			stand_sh = deg_to_rad(25)
			stand_el = deg_to_rad(-75)
		var sit_sh := deg_to_rad(45) if at_desk else deg_to_rad(20)
		var sit_el := deg_to_rad(-55) if at_desk else deg_to_rad(-60)
		if holding and not at_desk:
			sit_el = deg_to_rad(-85)
		sh.rotation.x = lerpf(stand_sh, sit_sh, sit)
		el.rotation.x = lerpf(stand_el, sit_el, sit)
		sh.rotation.z = (0.08 if i == 1 else -0.08) * (1.0 - sit)
	if item_node != null:
		item_node.rotation.x = -arms[1][1].rotation.x - arms[1][0].rotation.x
	head.rotation.x = clampf(pitch, -0.6, 0.5)
