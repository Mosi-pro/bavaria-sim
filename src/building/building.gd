extends Control
## Begehbare Leitstelle (Ebene 1) mit Übergang in den Disponentenbetrieb (Ebene 2).
##
## - 3D-Ansicht in einem SubViewport (wird beim Sitzen am Arbeitsplatz angehalten).
## - Der bestehende Leitstellenarbeitsplatz (workstation.gd) wird unverändert als Kind
##   angelegt und beim Hinsetzen eingeblendet – es gibt keine zweite Leitstellenlogik.
## - Mehrspieler-Anwesenheit (Positionen, Plätze, Türen) über das Autoload „Presence“.

const UI = preload("res://src/ui/kit.gd")
const Workstation = preload("res://src/ui/workstation.gd")
const Layout = preload("res://src/building/layout.gd")
const Avatar = preload("res://src/building/avatar.gd")
const Sfx = preload("res://src/building/sfx.gd")
const MATS = preload("res://src/building/materials.gd")

const WALK_SPEED := 1.55
const RUN_SPEED := 3.3
const EYE_H := 1.64
const REACH := 2.3
const MOUSE_SENS := 0.0024
const NPCS := [["ws2", "K. Huber"], ["ws9", "S. Yilmaz"], ["sf1", "M. Brandl"], ["pr3", "T. Wagner"]]

var vpc: SubViewportContainer
var vp: SubViewport
var world: Node3D
var layout: Layout
var body: CharacterBody3D
var cam: Camera3D
var ray: RayCast3D
var ws: Control
var hud: Control
var _prompt: Label
var _cross: ColorRect
var _status: Label
var _toast: Label
var _hint_panel: PanelContainer
var _tl_time: Label
var _minimap: Control
var _toast_t := 0.0
var _progress: ProgressBar
var _item_hint: Label
var _menu: PanelContainer
var _help: Label

var mode := "walk"          # walk | sit_trans | desk | lounge | stand_trans
var seat_id := ""
var pending_seat := ""
var yaw := -PI / 2
var pitch := 0.0
var item := 0
var item_uses := 0
var busy := {}              # laufende Tätigkeit {kind, t, dur, text}
var avatars := {}           # Peer-ID bzw. NPC-Name -> Avatar
var _trans := {}            # Kamerafahrt {from: Transform3D, to: Transform3D, t, dur, then}
var _stored_windows: Array = []
var _door_angles := {}
var _t_slow := 0.0
var _t_led := 0.0
var _t_keys := 0.0
var _step_dist := 0.0
var _bob := 0.0
var _sfx_pool: Array = []
var _loops: Array = []
var _target: Dictionary = {}
var _npc_on := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_world()
	_build_hud()
	# Bestehender Leitstellenarbeitsplatz (Ebene 2), zunächst ausgeblendet
	ws = Control.new()
	ws.set_script(Workstation)
	ws.set("building", self)
	ws.visible = false
	add_child(ws)
	Presence.seats_changed.connect(_on_seats_changed)
	Presence.toggles_changed.connect(_apply_toggles)
	Presence.seat_denied.connect(func(_s, text):
		pending_seat = ""
		if mode in ["desk", "lounge", "sit_trans"]:
			stand_up(true)
		_show_toast(text))
	_on_seats_changed()
	_apply_toggles(true)
	_spawn()
	_capture(true)
	_show_toast("Willkommen in der Integrierten Leitstelle Bavaria.\nGehe in den Leitstellenraum und übernimm mit [E] einen freien Arbeitsplatz.", 7.0)

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Presence.my_seat() != "":
		Presence.release_seat()
	Presence.local_pose = {}

# ================================================================== Aufbau
func _build_world() -> void:
	vpc = SubViewportContainer.new()
	vpc.stretch = true
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	vpc.gui_input.connect(_on_view_input)
	add_child(vpc)
	vp = SubViewport.new()
	vp.handle_input_locally = false
	vp.audio_listener_enable_3d = true
	vp.positional_shadow_atlas_size = 0
	var q: int = Settings.quality_level()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	vp.scaling_3d_scale = [0.75, 1.0, 1.0][q]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	vpc.add_child(vp)
	world = Node3D.new()
	world.name = "Leitstelle"
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.74, 0.82, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.87, 0.82)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.glow_enabled = q >= 1
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	# Umgebungsverdeckung und indirektes Licht (ab mittlerer bzw. hoher Qualität)
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssil_enabled = q >= 2
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.8
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 48
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.02
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	layout = Layout.new()
	layout.build(world, q)
	if q >= 2:
		# Reflexionen im Leitstellenraum (einmalig berechnet)
		var probe := ReflectionProbe.new()
		probe.position = Vector3(18, 2.6, 8)
		probe.size = Vector3(36, 5.4, 18)
		probe.box_projection = true
		probe.interior = true
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		probe.ambient_color = Color(0.32, 0.3, 0.28)
		world.add_child(probe)
	_build_screens()
	# Spieler (Kapsel mit Kollision)
	body = CharacterBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.floor_snap_length = 0.2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	body.add_child(cs)
	world.add_child(body)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 220.0
	world.add_child(cam)
	cam.current = true
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 2
	ray.collide_with_areas = true
	ray.add_exception(body)
	cam.add_child(ray)
	_build_audio()

func _build_audio() -> void:
	var amb := float(Settings.get_v("audio", "ambient"))
	var base := linear_to_db(maxf(amb, 0.0001))
	for kind in ["murmur", "murmur_soft", "server", "fridge"]:
		for p in layout.sound_spots.get(kind, []):
			var a := AudioStreamPlayer3D.new()
			a.stream = Sfx.get_stream(kind)
			a.position = p
			a.unit_size = {"murmur": 5.0, "murmur_soft": 2.5, "server": 3.0, "fridge": 1.2}[kind]
			a.max_distance = 30.0
			a.volume_db = base + {"murmur": -4.0, "murmur_soft": -8.0, "server": -2.0, "fridge": -10.0}[kind]
			a.autoplay = amb > 0.001
			world.add_child(a)
			_loops.append(a)
	for i in 6:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 3.0
		a.max_distance = 25.0
		world.add_child(a)
		_sfx_pool.append(a)

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	_cross = ColorRect.new()
	_cross.color = Color(1, 1, 1, 0.75)
	_cross.size = Vector2(4, 4)
	_cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_cross.offset_left = -2; _cross.offset_top = -2; _cross.offset_right = 2; _cross.offset_bottom = 2
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_cross)
	_prompt = _hud_label("", 16, Color(1, 1, 1))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_top = 26; _prompt.offset_bottom = 70; _prompt.offset_left = -400; _prompt.offset_right = 400
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_prompt)
	# oben links: Logo, Name, Datum und Uhrzeit
	var tl := _panel()
	tl.position = Vector2(14, 12)
	var logo := Control.new()
	logo.set_script(preload("res://src/building/hud_widgets.gd"))
	logo.kind = "logo"
	logo.custom_minimum_size = Vector2(36, 34)
	var name_l := _hud_label("Leitstelle\nBavaria", 15, Color(0.95, 0.96, 0.97))
	name_l.add_theme_constant_override("line_spacing", -4)
	_tl_time = _hud_label("", 13, Color(0.9, 0.91, 0.93))
	var sep := VSeparator.new()
	sep.custom_minimum_size.x = 14
	tl.add_child(UI.hbox([logo, name_l, sep, _hud_label("◷", 22, Color(0.9, 0.91, 0.93)), _tl_time], 8))
	hud.add_child(tl)
	# oben rechts: Kennzahlen
	var tr := _panel()
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_right = -14
	tr.offset_top = 12
	_status = _hud_label("", 14, Color(0.93, 0.94, 0.96))
	tr.add_child(_status)
	hud.add_child(tr)
	# unten links: Lageplan
	_minimap = Control.new()
	_minimap.set_script(preload("res://src/building/hud_widgets.gd"))
	_minimap.building = self
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap.offset_left = 14; _minimap.offset_right = 254; _minimap.offset_top = -214; _minimap.offset_bottom = -44
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_minimap)
	_help = _hud_label("W A S D laufen  ·  Maus umsehen  ·  Umschalt schneller  ·  E benutzen  ·  Esc Menü", 12, Color(0.85, 0.86, 0.88, 0.85))
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 16; _help.offset_top = -34; _help.offset_bottom = -12; _help.offset_right = 900
	hud.add_child(_help)
	# unten rechts: Hinweise
	_hint_panel = _panel()
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_panel.offset_right = -14
	_hint_panel.offset_bottom = -44
	var hint_title := _hud_label("ⓘ  Hinweis", 14, Color(0.55, 0.75, 1.0))
	_toast = _hud_label("", 13, Color(0.92, 0.93, 0.95))
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size.x = 300
	_hint_panel.add_child(UI.vbox([hint_title, _toast], 2))
	hud.add_child(_hint_panel)
	_progress = ProgressBar.new()
	_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_progress.offset_top = 70; _progress.offset_bottom = 84; _progress.offset_left = -130; _progress.offset_right = 130
	_progress.show_percentage = false
	_progress.visible = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_progress)
	_item_hint = _hud_label("", 13, Color(1, 1, 1))
	_item_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_item_hint.offset_left = -520; _item_hint.offset_right = -16; _item_hint.offset_top = -34; _item_hint.offset_bottom = -12
	_item_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(_item_hint)
	_build_menu()

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.11, 0.86)
	sb.border_color = Color(0.3, 0.32, 0.35, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _hud_label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.11, 0.12, 0.95), UI.BORDER, 1, 18))
	var v := UI.vbox([], 8)
	var title := UI.label("LEITSTELLE 112 – Pause der Steuerung", UI.TEXT, 16)
	title.add_theme_font_override("font", UI.bold())
	v.add_child(title)
	v.add_child(UI.label("Die Simulation läuft weiter. Notrufe gehen ein, auch wenn du nicht am Platz sitzt.", UI.TEXT2, 12))
	v.add_child(UI.button("Weiter", func(): _close_menu()))
	v.add_child(UI.button("Direkt an einen freien Arbeitsplatz setzen", func():
		_close_menu()
		_quick_seat()))
	v.add_child(UI.button("Sitzung beenden (Hauptmenü)", func():
		UI.confirm(self, "Sitzung beenden", "Sitzung beenden und zum Hauptmenü zurückkehren?\nNicht gespeicherter Fortschritt geht verloren." + ("\n\nAls Host beenden Sie damit die Sitzung für alle Mitspieler." if Game.is_host() else ""), func(): Game.leave(""))))
	v.add_child(HSeparator.new())
	v.add_child(UI.label("Steuerung:  W A S D / Pfeiltasten laufen  ·  Maus umsehen  ·  Umschalt schneller\nE benutzen / hinsetzen / aufstehen  ·  F trinken/essen  ·  G abstellen\nAm Arbeitsplatz: F8 oder Knopf »Aufstehen« – zurück in die Leitstelle", UI.TEXT2, 12))
	_menu.add_child(UI.margin(v, 6))
	_menu.visible = false
	hud.add_child(_menu)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

func _spawn() -> void:
	var n := int(Presence.me()) % 5
	body.position = layout.spawn + Vector3(0, 0.05, -1.0 + n * 0.5)
	yaw = layout.spawn_yaw
	pitch = 0.0
	mode = "walk"

# ================================================================== Eingabe
func _capture(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and mode in ["walk", "lounge"] and not _menu.visible:
		_capture(true)

func _input(ev: InputEvent) -> void:
	if mode == "desk" or not is_visible_in_tree():
		return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and mode in ["walk", "lounge"]:
		yaw = wrapf(yaw - ev.relative.x * MOUSE_SENS, -PI, PI)
		pitch = clampf(pitch - ev.relative.y * MOUSE_SENS, -1.45, 1.45)
		if mode == "lounge" and layout.seats.has(seat_id):
			var base := float(layout.seats[seat_id]["yaw"]) - PI / 2
			yaw = base + clampf(wrapf(yaw - base, -PI, PI), -1.9, 1.9)
		get_viewport().set_input_as_handled()

func _unhandled_key_input(ev: InputEvent) -> void:
	if mode == "desk" or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode
	if k == KEY_ESCAPE:
		if _menu.visible:
			_close_menu()
		else:
			_open_menu()
		get_viewport().set_input_as_handled()
		return
	if _menu.visible:
		return
	match k:
		KEY_E:
			if mode == "lounge":
				stand_up()
			elif mode == "walk":
				_interact()
		KEY_SPACE:
			if mode == "lounge":
				stand_up()
		KEY_F:
			_use_item()
		KEY_G:
			if item > 0:
				_set_item(0)
				_show_toast("Abgestellt.")
		KEY_F8:
			if mode == "lounge":
				stand_up()
	if ev.is_action_pressed("ls_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN else Window.MODE_FULLSCREEN

func _open_menu() -> void:
	_menu.visible = true
	_capture(false)

func _close_menu() -> void:
	_menu.visible = false
	if mode in ["walk", "lounge"]:
		_capture(true)

# ================================================================== Bewegung
func _physics_process(delta: float) -> void:
	if mode != "walk":
		body.velocity = Vector3.ZERO
		return
	var dir := Vector2.ZERO
	var can_move := not _menu.visible and busy.is_empty() and get_window().has_focus()
	if can_move:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			dir.y += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			dir.x += 1
	dir = dir.normalized()
	var spd := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	var basis := Basis(Vector3.UP, yaw)
	var want := basis * Vector3(dir.x, 0, dir.y) * spd
	var v := body.velocity
	var acc := 12.0 if dir != Vector2.ZERO else 14.0
	v.x = move_toward(v.x, want.x, acc * delta * spd)
	v.z = move_toward(v.z, want.z, acc * delta * spd)
	if not body.is_on_floor():
		v.y -= 9.8 * delta
	else:
		v.y = 0.0
	body.velocity = v
	var before := body.position
	body.move_and_slide()
	# Sicherheitsnetz: nie aus dem Gebäude fallen
	if body.position.y < -2.0:
		_spawn()
	var moved := Vector2(body.position.x - before.x, body.position.z - before.z).length()
	_step_dist += moved
	_bob += moved * 5.2
	if _step_dist > (0.7 if spd > 2 else 0.62):
		_step_dist = 0.0
		_play_sfx("step", body.position + Vector3(0, 0.05, 0), -18.0)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_update_camera(delta)
	_animate_doors(delta)
	_update_busy(delta)
	_update_avatars(delta)
	if mode in ["walk", "lounge", "sit_trans", "stand_trans"]:
		_hide_stray_windows()
	_update_prompt()
	_toast_t -= delta
	_t_slow += delta
	if _t_slow >= 1.0:
		_t_slow = 0.0
		_slow_update()
	_t_led += delta
	if _t_led >= 0.35:
		_t_led = 0.0
		for i in 6:
			var led: Node3D = layout.leds[randi() % layout.leds.size()]
			led.visible = not led.visible
	_t_keys -= delta
	if _t_keys <= 0.0:
		_t_keys = randf_range(0.08, 0.35)
		_keyboard_tick()
	# eigene Pose an die Mitspieler
	var p := body.position
	var py := yaw
	if seat_id != "" and layout.seats.has(seat_id):
		p = layout.seats[seat_id]["pos"]
		py = float(layout.seats[seat_id]["yaw"]) - PI / 2
	Presence.set_local_pose(p, py, pitch, item)

func _update_camera(delta: float) -> void:
	if not _trans.is_empty():
		_trans["t"] = float(_trans["t"]) + delta
		var k := clampf(float(_trans["t"]) / float(_trans["dur"]), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var a: Transform3D = _trans["from"]
		var b: Transform3D = _trans["to"]
		cam.global_transform = Transform3D(a.basis.slerp(b.basis, k).orthonormalized(), a.origin.lerp(b.origin, k))
		if k >= 1.0:
			var then: Callable = _trans["then"]
			_trans = {}
			then.call()
		return
	match mode:
		"walk":
			var bob := sin(_bob) * 0.018 if body.velocity.length() > 0.3 else 0.0
			cam.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), body.position + Vector3(0, EYE_H + bob, 0))
		"lounge":
			var s: Dictionary = layout.seats[seat_id]
			cam.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), s["eye"])

func _walk_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), body.position + Vector3(0, EYE_H, 0))

func _seat_transform(s: Dictionary) -> Transform3D:
	var eye: Vector3 = s["eye"]
	var t := Transform3D(Basis(), eye)
	return t.looking_at(s["look"], Vector3.UP)

func _fly(to: Transform3D, dur: float, then: Callable) -> void:
	_trans = {"from": cam.global_transform, "to": to, "t": 0.0, "dur": dur, "then": then}

# ================================================================== Interaktion
func _target_meta() -> Dictionary:
	if mode != "walk" or _menu.visible:
		return {}
	ray.force_raycast_update()
	if not ray.is_colliding():
		return {}
	var c := ray.get_collider()
	if c == null:
		return {}
	var n: Node = c
	if not n.has_meta("ia") and n.get_parent() != null and n.get_parent().has_meta("ia"):
		n = n.get_parent()
	if not n.has_meta("ia"):
		return {}
	return n.get_meta("ia")

func _update_prompt() -> void:
	_target = _target_meta()
	var text := ""
	if not busy.is_empty():
		text = String(busy["text"])
	elif mode == "lounge":
		text = "[E] Aufstehen"
	elif not _target.is_empty():
		text = _prompt_for(_target)
	_prompt.text = text
	_cross.color = Color(1.0, 0.85, 0.35, 0.95) if not _target.is_empty() else Color(1, 1, 1, 0.6)
	_cross.visible = mode == "walk" and not _menu.visible
	_help.visible = mode in ["walk", "lounge"]
	if item > 0 and mode != "desk":
		_item_hint.text = "%s   ·   [F] %s   ·   [G] abstellen" % [["", "Kaffee", "Wasser", "Essen"][item], "essen" if item == 3 else "trinken"]
	else:
		_item_hint.text = ""

func _prompt_for(m: Dictionary) -> String:
	match String(m.get("kind", "")):
		"seat":
			var id: String = m["id"]
			if not layout.seats.has(id):
				return ""
			var s: Dictionary = layout.seats[id]
			var holder := Presence.owner_of(id)
			var npc := _npc_at(id)
			if npc != "":
				return "%s – besetzt (%s)" % [s["name"], npc]
			if holder != 0 and holder != Presence.me():
				return "%s – belegt von %s" % [s["name"], Presence.player_name(holder)]
			if pending_seat == id:
				return "Platz wird angefragt …"
			return "[E] Arbeitsplatz übernehmen – %s" % s["name"] if s["kind"] == "desk" else "[E] Hinsetzen"
		"door":
			var open := Presence.is_on(String(m["id"]))
			return "[E] %s %s" % [String(m.get("name", "Tür")), "schließen" if open else "öffnen"]
		"coffee":
			return "[E] Kaffee zubereiten" if item == 0 else "Hände voll – erst mit [G] abstellen"
		"water":
			return "[E] %s" % m.get("text", "Wasser zapfen") if item == 0 else "Hände voll – erst mit [G] abstellen"
		"microwave":
			return "[E] Essen aufwärmen" if item == 0 else "Hände voll – erst mit [G] abstellen"
		"stove":
			return "[E] Kochfeld %s" % ("ausschalten" if Presence.is_on("stove") else "einschalten")
		"sink":
			return "[E] Hände waschen"
		"server":
			return "[E] Systemstatus anzeigen"
		"info":
			return "[E] Ansehen"
	return ""

func _interact() -> void:
	if _target.is_empty() or not busy.is_empty():
		return
	var m := _target
	match String(m.get("kind", "")):
		"seat":
			var id: String = m["id"]
			if _npc_at(id) != "" or (Presence.owner_of(id) != 0 and Presence.owner_of(id) != Presence.me()):
				_play_ui("error")
				return
			pending_seat = id
			Presence.request_seat(id)
		"door":
			var id: String = m["id"]
			var group := id
			if layout.doors.has(id):
				group = layout.doors[id].get("group", id)
			Presence.set_toggle(group, not Presence.is_on(group))
		"coffee":
			if item == 0:
				_start_busy("coffee", 4.5, "Kaffee läuft durch …", func():
					_set_item(Presence.ITEM_COFFEE)
					_show_toast("Frisch gebrühter Kaffee. [F] trinken, [G] abstellen."))
				_play_sfx("coffee", _spot("coffee"), -4.0)
		"water":
			if item == 0:
				_start_busy("water", 2.0, "Wasser wird gezapft …", func():
					_set_item(Presence.ITEM_WATER)
					_show_toast("Ein Glas Wasser. [F] trinken, [G] abstellen."))
				_play_sfx("water", body.position + Vector3(0, 1, 0), -6.0)
		"microwave":
			if item == 0:
				_start_busy("microwave", 6.0, "Essen wird aufgewärmt …", func():
					_set_item(Presence.ITEM_FOOD)
					_show_toast("Mahlzeit! [F] essen, [G] abstellen."))
				_play_sfx("microwave", _spot("microwave"), -6.0)
		"stove":
			Presence.set_toggle("stove", not Presence.is_on("stove"))
		"sink":
			_start_busy("sink", 2.0, "Hände waschen …", func(): _show_toast("Hände gewaschen."))
			_play_sfx("water", body.position + Vector3(0, 1, 0), -6.0)
		"server":
			_show_toast(_server_status(), 8.0)
		"info":
			_show_toast(String(m.get("text", "")), 6.0)

func _spot(name: String) -> Vector3:
	var arr: Array = layout.sound_spots.get(name, [])
	return arr[0] if not arr.is_empty() else body.position

func _start_busy(kind: String, dur: float, text: String, done: Callable) -> void:
	busy = {"kind": kind, "t": 0.0, "dur": dur, "text": text, "done": done}
	_progress.visible = true
	_progress.value = 0

func _update_busy(delta: float) -> void:
	if busy.is_empty():
		_progress.visible = false
		return
	busy["t"] = float(busy["t"]) + delta
	_progress.value = 100.0 * float(busy["t"]) / float(busy["dur"])
	if float(busy["t"]) >= float(busy["dur"]):
		var done: Callable = busy["done"]
		busy = {}
		_progress.visible = false
		done.call()

func _set_item(k: int) -> void:
	item = k
	item_uses = 0

func _use_item() -> void:
	if item == 0 or mode == "desk":
		return
	item_uses += 1
	var texts := ["", "Ein Schluck Kaffee – das tut gut.", "Ein Schluck Wasser.", "Lecker!"]
	var done_texts := ["", "Tasse leer.", "Glas leer.", "Teller leer – satt."]
	if item_uses >= 3:
		_show_toast(done_texts[item])
		_set_item(0)
	else:
		_show_toast(texts[item])

func _server_status() -> String:
	var online := Presence.seats.size()
	return "Einsatzleitsystem ELS Bavaria – alle Dienste in Betrieb.\nEinsätze: %d  ·  Notrufe: %d  ·  Fahrzeuge: %d  ·  belegte Plätze: %d\nVerbindung: %s" % [State.incidents.size(), State.calls.size(), State.vehicles.size(), online, Net.status_text]

func _show_toast(text: String, dur := 4.0) -> void:
	_toast.text = text
	_toast_t = dur

func _play_ui(name: String) -> void:
	Audio.play(name)

func _play_sfx(name: String, pos: Vector3, vol_db := 0.0) -> void:
	var amb := float(Settings.get_v("audio", "effects"))
	if amb <= 0.001:
		return
	for a in _sfx_pool:
		if not a.playing:
			a.stream = Sfx.get_stream(name)
			a.position = pos
			a.volume_db = linear_to_db(amb) + vol_db
			a.play()
			return

func _keyboard_tick() -> void:
	if not Settings.get_v("audio", "keys"):
		return
	var occupied: Array = []
	for id in layout.seats:
		if layout.seats[id]["kind"] != "desk":
			continue
		if _npc_at(id) != "" or (Presence.owner_of(id) != 0 and Presence.owner_of(id) != Presence.me()):
			occupied.append(id)
	if occupied.is_empty() or randf() < 0.45:
		return
	var s: Dictionary = layout.seats[occupied[randi() % occupied.size()]]
	for a in _sfx_pool:
		if not a.playing:
			a.stream = Audio._streams.get("key%d" % (randi() % 3 + 1))
			if a.stream == null:
				return
			a.position = Vector3(s["look"]) * 0.6 + Vector3(s["eye"]) * 0.4
			a.volume_db = linear_to_db(maxf(float(Settings.get_v("audio", "ambient")), 0.0001)) - 8.0
			a.play()
			return

# ================================================================== Hinsetzen / Aufstehen
func _quick_seat() -> void:
	if mode != "walk":
		return
	for id in layout.seat_order:
		if layout.seats[id]["kind"] == "desk" and Presence.owner_of(id) == 0 and _npc_at(id) == "":
			pending_seat = id
			Presence.request_seat(id)
			return
	_show_toast("Zurzeit ist kein Arbeitsplatz frei.")

func _on_seats_changed() -> void:
	# Beschilderung und Bildschirme der Arbeitsplätze
	for id in layout.seats:
		var s: Dictionary = layout.seats[id]
		if s["kind"] != "desk":
			continue
		var holder := Presence.owner_of(id)
		var npc := _npc_at(id)
		var used := holder != 0 or npc != ""
		var plate: Label3D = s["plate"]
		var who := npc if npc != "" else (Presence.player_name(holder) if holder != 0 else "frei")
		plate.text = "%s · %s" % [s["name"], who]
		plate.modulate = Color(0.85, 0.25, 0.2) if used else Color(0.15, 0.65, 0.3)
		var scr: Node3D = s["screens"]
		for sc in scr.get_children():
			(sc as MeshInstance3D).material_override = MATS.get_mat(String(sc.get_meta("on")) if used else "screen_login")
	# Eigener Platz bestätigt → hinsetzen
	if pending_seat != "" and Presence.owner_of(pending_seat) == Presence.me():
		var id := pending_seat
		pending_seat = ""
		_sit(id)
	elif seat_id != "" and Presence.owner_of(seat_id) != Presence.me() and mode in ["desk", "lounge"] and Net.mode != Net.MODE_CLIENT:
		stand_up(true)

func _sit(id: String) -> void:
	if not layout.seats.has(id) or mode != "walk":
		return
	seat_id = id
	var s: Dictionary = layout.seats[id]
	busy = {}
	_capture(false)
	mode = "sit_trans"
	body.position = Vector3(s["pos"]) + Vector3(0, 0.02, 0)
	var to := _seat_transform(s)
	if s["kind"] == "desk":
		_fly(to, 0.75, func(): _enter_desk())
	else:
		_fly(to, 0.55, func():
			mode = "lounge"
			yaw = float(s["yaw"]) - PI / 2
			pitch = 0.0
			_capture(true))

## Ebene 2: bestehendes Leitstellen-UI einblenden, 3D-Ansicht anhalten.
func _enter_desk() -> void:
	mode = "desk"
	hud.visible = false
	vpc.visible = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ws.visible = true
	ws.set_process_unhandled_key_input(true)
	for w in _stored_windows:
		if is_instance_valid(w):
			w.show()
	_stored_windows = []
	_capture(false)
	Audio.play("system")
	if ws.has_method("set_status"):
		ws.set_status("Arbeitsplatz übernommen: %s. Mit F8 oder »Aufstehen« zurück in die Leitstelle." % layout.seats[seat_id]["name"], UI.GREEN)

## Zurück in die begehbare Leitstelle (Ebene 1).
func stand_up(forced := false) -> void:
	if mode == "walk" or mode == "stand_trans":
		return
	var s: Dictionary = layout.seats.get(seat_id, {})
	if mode == "desk":
		_hide_windows()
		ws.visible = false
		vpc.visible = true
		hud.visible = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_trans = {}
	if Presence.owner_of(seat_id) == Presence.me():
		Presence.release_seat()
	Presence.want_seat = ""
	var stand: Vector3 = s.get("stand", body.position)
	body.position = stand + Vector3(0, 0.05, 0)
	body.velocity = Vector3.ZERO
	var look_yaw := float(s.get("yaw", 0.0)) - PI / 2
	yaw = look_yaw
	pitch = -0.15
	mode = "stand_trans"
	cam.global_transform = _seat_transform(s) if not s.is_empty() else cam.global_transform
	_fly(_walk_transform(), 0.6 if not forced else 0.2, func():
		mode = "walk"
		seat_id = ""
		_capture(true))

func _hide_windows() -> void:
	for c in ws.get_children():
		if c is Window and not (c is PopupMenu) and c.visible:
			c.hide()
			_stored_windows.append(c)

func _hide_stray_windows() -> void:
	for c in ws.get_children():
		if c is Window and c.visible:
			if c is PopupMenu:
				c.hide()
			else:
				c.hide()
				if not _stored_windows.has(c):
					_stored_windows.append(c)

# ================================================================== Türen, Geräte, Anzeigen
func _apply_toggles(instant := false) -> void:
	if layout == null:
		return
	for id in layout.doors:
		var d: Dictionary = layout.doors[id]
		var open := Presence.is_on(String(d["group"]))
		var target := float(d["open_angle"]) if open else 0.0
		if not _door_angles.has(id):
			_door_angles[id] = {"cur": target if instant else 0.0, "target": target}
		elif not instant and absf(float(_door_angles[id]["target"]) - target) > 0.01:
			_play_sfx("cabinet" if id == "fridge" else "door", (d["hinge"] as Node3D).global_position + Vector3(0, 1.0, 0), -8.0)
		_door_angles[id]["target"] = target
	var on := Presence.is_on("stove")
	for hp in layout.hotplates:
		(hp as MeshInstance3D).material_override = MATS.get_mat("hotplate_on" if on else "dark")

func _animate_doors(delta: float) -> void:
	for id in _door_angles:
		var st: Dictionary = _door_angles[id]
		var cur := float(st["cur"])
		var tgt := float(st["target"])
		if absf(cur - tgt) < 0.0005:
			continue
		cur = move_toward(cur, tgt, delta * 2.4)
		st["cur"] = cur
		var hinge: Node3D = layout.doors[id]["hinge"]
		hinge.rotation.y = _door_base(hinge) + cur

func _door_base(hinge: Node3D) -> float:
	if not hinge.has_meta("base_rot"):
		hinge.set_meta("base_rot", hinge.rotation.y)
	return float(hinge.get_meta("base_rot"))

func _slow_update() -> void:
	_update_wall()
	_update_status()
	_update_npcs()

func _update_status() -> void:
	if not State.active:
		return
	var ringing := 0
	for id in State.calls:
		if State.calls[id]["state"] == "ringing":
			ringing += 1
	var used := 0
	var total := 0
	for id in layout.seats:
		if layout.seats[id]["kind"] != "desk":
			continue
		total += 1
		if Presence.owner_of(id) != 0 or _npc_at(id) != "":
			used += 1
	var wd := ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
	var dt := Time.get_datetime_dict_from_unix_time(State.game_unix())
	_tl_time.text = "%s, %s\n%s Uhr" % [wd[int(dt["weekday"])], State.date_str().split(" ")[-1], State.time_str().substr(0, 5)]
	_status.text = "Plätze %d / %d     ☎ %d     ⚠ %d" % [used, total, ringing, State.incidents.size()]
	_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.68) if ringing > 0 else Color(0.93, 0.94, 0.96))
	if _toast_t <= 0.0:
		if ringing > 0:
			_toast.text = "%d Notruf%s wartend – setz dich an einen freien Arbeitsplatz." % [ringing, "e" if ringing != 1 else ""]
		elif State.incidents.is_empty():
			_toast.text = "Keine aktuellen Einsätze."
		else:
			_toast.text = "%d laufende Einsätze." % State.incidents.size()

## Live-Bildschirme: Karte, Einsatzliste, Fahrzeugstatus und Großbildwand werden in
## SubViewports gezeichnet und von allen Monitoren gemeinsam genutzt (geringe Last).
var _screens := {}
var _screen_t := 0

func _build_screens() -> void:
	var defs := {"map": [Vector2i(512, 310), "screen_a"], "list": [Vector2i(512, 310), "screen_b"], "status": [Vector2i(512, 310), "screen_c"], "wall": [Vector2i(1640, 520), "wall_screen"], "login": [Vector2i(512, 310), "screen_login"]}
	for k in defs:
		var sv := SubViewport.new()
		sv.size = defs[k][0]
		sv.transparent_bg = false
		sv.disable_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
		var c := Control.new()
		c.set_script(preload("res://src/building/screen_canvas.gd"))
		c.kind = k
		c.size = Vector2(defs[k][0])
		sv.add_child(c)
		add_child(sv)
		_screens[k] = [sv, c]
		# Bildschirme leuchten selbst: unbeleuchtet mit Farbtextur (Viewport-Texturen
		# lassen sich nicht zuverlässig als Emissionstextur verwenden)
		var m: StandardMaterial3D = MATS.get_mat(defs[k][1])
		m.emission_enabled = false
		m.emission_texture = null
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.93, 0.93, 0.93)
		m.albedo_texture = sv.get_texture()

func _update_screens(all := false) -> void:
	_screen_t += 1
	for k in _screens:
		if k == "login" and not all:
			continue
		if k == "map" and not all and _screen_t % 2 == 0:
			continue
		var sv: SubViewport = _screens[k][0]
		(_screens[k][1] as Control).queue_redraw()
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE

func _update_wall() -> void:
	if not State.active:
		return
	_update_screens(_screen_t == 0)
	(layout.labels["clock"] as Label3D).text = State.time_str().substr(0, 5)

# ================================================================== Mitspieler und Kollegen
func _npc_at(seat: String) -> String:
	if not _npc_on:
		return ""
	for n in NPCS:
		if n[0] == seat:
			return n[1]
	return ""

func _update_npcs() -> void:
	# Im Einzelspiel sitzen einige Kolleginnen und Kollegen (KI) im Raum – für die Atmosphäre.
	var want := not Net.is_online()
	if want == _npc_on:
		return
	_npc_on = want
	for n in NPCS:
		var key := "npc_" + String(n[0])
		if want and Presence.owner_of(n[0]) == 0 and layout.seats.has(n[0]):
			var a := _make_avatar(hash(n[1]), String(n[1]))
			var s: Dictionary = layout.seats[n[0]]
			a.position = s["pos"]
			a.target_pos = s["pos"]
			a.rotation.y = float(s["yaw"]) - PI / 2
			a.target_yaw = a.rotation.y
			a.sitting = true
			a.sit = 1.0
			a.at_desk = s["kind"] == "desk"
			a.seat_h = float(s.get("seat_h", 0.49))
			if n[0] == "pr3":
				a.set_item(1)
			avatars[key] = a
		elif not want and avatars.has(key):
			avatars[key].queue_free()
			avatars.erase(key)
	_on_seats_changed()

func _make_avatar(look_seed: int, name: String) -> Avatar:
	var a := Avatar.new()
	world.add_child(a)
	a.setup(look_seed, name)
	return a

func _update_avatars(delta: float) -> void:
	for pid in Presence.poses:
		if pid == Presence.me():
			continue
		var pose: Dictionary = Presence.poses[pid]
		var a: Avatar = avatars.get(pid)
		var nm := Presence.player_name(pid)
		if a == null:
			a = _make_avatar(hash(nm), nm)
			a.position = pose["p"]
			a.rotation.y = float(pose["yaw"])
			avatars[pid] = a
		a.set_display_name(nm)
		var seat := ""
		for s in Presence.seats:
			if int(Presence.seats[s]) == pid:
				seat = s
		a.sitting = seat != "" and layout.seats.has(seat)
		if a.sitting:
			var sd: Dictionary = layout.seats[seat]
			a.target_pos = sd["pos"]
			a.target_yaw = float(sd["yaw"]) - PI / 2
			a.at_desk = sd["kind"] == "desk"
			a.seat_h = float(sd.get("seat_h", 0.49))
		else:
			a.target_pos = pose["p"]
			a.target_yaw = float(pose["yaw"])
		a.pitch = float(pose["pitch"]) if not a.at_desk or not a.sitting else -0.1
		a.set_item(int(pose["item"]))
		a.follow(delta)
	for key in avatars.keys():
		if key is int and not Presence.poses.has(key):
			avatars[key].queue_free()
			avatars.erase(key)
	for key in avatars:
		(avatars[key] as Avatar).animate(delta)
