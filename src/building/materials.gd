extends RefCounted
## Materialien und selbst erzeugte Texturen der begehbaren Leitstelle
## (keine Fremdgrafiken, keine Logos – alles prozedural).

static var _cache := {}
static var _tex := {}

static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m := StandardMaterial3D.new()
	m.roughness = 0.8
	match name:
		"plaster":
			m.albedo_color = Color(0.93, 0.92, 0.89)
		"plaster_grey":
			m.albedo_color = Color(0.78, 0.79, 0.8)
		"wood":
			_tri(m, tex("wood"), 0.9)
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.65
		"carpet":
			_tri(m, tex("carpet"), 0.55)
			m.roughness = 1.0
		"ceiling":
			_tri(m, tex("ceiling"), 0.42)
			m.roughness = 0.95
		"tiles_floor":
			_tri(m, tex("tiles"), 0.5)
			m.albedo_color = Color(0.72, 0.72, 0.7)
			m.roughness = 0.45
		"tiles_wall":
			_tri(m, tex("tiles"), 1.6)
			m.albedo_color = Color(0.96, 0.96, 0.95)
			m.roughness = 0.3
		"desk_top":
			_tri(m, tex("wood"), 1.6)
			m.albedo_color = Color(1.0, 0.97, 0.9)
			m.roughness = 0.5
		"desk_body":
			m.albedo_color = Color(0.86, 0.87, 0.87)
			m.roughness = 0.55
		"desk_white":
			m.albedo_color = Color(0.95, 0.95, 0.94)
			m.roughness = 0.4
		"metal":
			m.albedo_color = Color(0.78, 0.79, 0.8)
			m.metallic = 0.85
			m.roughness = 0.28
		"steel":
			m.albedo_color = Color(0.7, 0.71, 0.72)
			m.metallic = 0.7
			m.roughness = 0.35
		"black":
			m.albedo_color = Color(0.06, 0.065, 0.07)
			m.roughness = 0.45
		"dark":
			m.albedo_color = Color(0.17, 0.18, 0.19)
			m.roughness = 0.6
		"chair":
			m.albedo_color = Color(0.1, 0.1, 0.11)
			m.roughness = 0.95
		"glass":
			m.albedo_color = Color(0.7, 0.8, 0.85, 0.18)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.3
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"frame":
			m.albedo_color = Color(0.28, 0.29, 0.3)
			m.metallic = 0.4
			m.roughness = 0.5
		"door":
			_tri(m, tex("wood"), 1.2)
			m.albedo_color = Color(0.92, 0.86, 0.76)
			m.roughness = 0.6
		"red":
			m.albedo_color = Color(0.75, 0.06, 0.04)
			m.emission_enabled = true
			m.emission = Color(0.9, 0.05, 0.02)
			m.emission_energy_multiplier = 0.6
		"red_matte":
			m.albedo_color = Color(0.72, 0.1, 0.08)
		"emit_light":
			m.albedo_color = Color(1, 1, 1)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.98, 0.94)
			m.emission_energy_multiplier = 2.2
		"kitchen":
			m.albedo_color = Color(0.94, 0.94, 0.93)
			m.roughness = 0.25
		"worktop":
			m.albedo_color = Color(0.22, 0.22, 0.23)
			m.roughness = 0.35
		"fabric":
			m.albedo_color = Color(0.32, 0.38, 0.45)
			m.roughness = 1.0
		"fabric_red":
			m.albedo_color = Color(0.55, 0.16, 0.14)
			m.roughness = 1.0
		"plant":
			m.albedo_color = Color(0.2, 0.42, 0.18)
			m.roughness = 0.85
		"pot":
			m.albedo_color = Color(0.3, 0.3, 0.31)
		"ceramic":
			m.albedo_color = Color(0.97, 0.97, 0.97)
			m.roughness = 0.15
		"rack":
			m.albedo_color = Color(0.08, 0.085, 0.09)
			m.metallic = 0.5
			m.roughness = 0.5
		"led_green":
			m.albedo_color = Color(0.1, 0.9, 0.3)
			m.emission_enabled = true
			m.emission = Color(0.2, 1.0, 0.3)
			m.emission_energy_multiplier = 2.0
		"led_blue":
			m.albedo_color = Color(0.2, 0.5, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.2, 0.5, 1.0)
			m.emission_energy_multiplier = 1.6
		"screen_a", "screen_b", "screen_c", "screen_off", "screen_tablet":
			var t := tex(name)
			m.albedo_texture = t
			m.emission_enabled = name != "screen_off"
			m.emission_texture = t
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = 0.9
			m.roughness = 0.3
		"wall_display":
			m.albedo_color = Color(0.05, 0.06, 0.07)
			m.roughness = 0.2
		"outside":
			m.albedo_color = Color(0.52, 0.56, 0.5)
			m.roughness = 1.0
		"outside_bld":
			m.albedo_color = Color(0.82, 0.8, 0.76)
		"asphalt":
			m.albedo_color = Color(0.36, 0.37, 0.38)
		"skin":
			m.albedo_color = Color(0.87, 0.7, 0.58)
			m.roughness = 0.7
		"shirt":
			m.albedo_color = Color(0.95, 0.95, 0.96)
		"trousers":
			m.albedo_color = Color(0.11, 0.14, 0.22)
		"hair":
			m.albedo_color = Color(0.25, 0.18, 0.12)
		"cup":
			m.albedo_color = Color(0.96, 0.96, 0.95)
			m.roughness = 0.2
		"coffee":
			m.albedo_color = Color(0.22, 0.12, 0.06)
			m.roughness = 0.1
		"water":
			m.albedo_color = Color(0.7, 0.85, 1.0, 0.5)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
		"food":
			m.albedo_color = Color(0.85, 0.55, 0.2)
		"hotplate_on":
			m.albedo_color = Color(0.5, 0.06, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.2, 0.05)
			m.emission_energy_multiplier = 1.4
		"highlight":
			m.albedo_color = Color(1.0, 0.85, 0.3, 0.25)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.no_depth_test = false
		_:
			m.albedo_color = Color(0.8, 0.8, 0.8)
	_cache[name] = m
	return m

static func _tri(m: StandardMaterial3D, t: Texture2D, scale: float) -> void:
	m.albedo_texture = t
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var img: Image
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	match name:
		"wood":
			img = Image.create(256, 256, false, Image.FORMAT_RGB8)
			for x in 256:
				var stripe := 0.5 + 0.5 * sin(float(x) * 0.21 + sin(float(x) * 0.037) * 3.0)
				var base := Color(0.86, 0.74, 0.56).lerp(Color(0.8, 0.66, 0.47), stripe * 0.6)
				for y in 256:
					var n := rng.randf() * 0.035
					img.set_pixel(x, y, Color(base.r - n, base.g - n, base.b - n))
		"carpet":
			img = Image.create(128, 128, false, Image.FORMAT_RGB8)
			for x in 128:
				for y in 128:
					var v := 0.33 + rng.randf() * 0.16
					if rng.randf() < 0.07:
						v = 0.58 + rng.randf() * 0.15
					elif rng.randf() < 0.06:
						v = 0.18
					img.set_pixel(x, y, Color(v, v, v * 1.02))
		"ceiling":
			img = Image.create(128, 128, false, Image.FORMAT_RGB8)
			for x in 128:
				for y in 128:
					var v := 0.94 - rng.randf() * 0.03
					if x < 2 or y < 2:
						v = 0.8
					img.set_pixel(x, y, Color(v, v, v))
		"tiles":
			img = Image.create(128, 128, false, Image.FORMAT_RGB8)
			for x in 128:
				for y in 128:
					var v := 0.92 - rng.randf() * 0.04
					if x % 64 < 2 or y % 64 < 2:
						v = 0.62
					img.set_pixel(x, y, Color(v, v, v))
		"screen_a":
			img = _screen(rng, 0)
		"screen_b":
			img = _screen(rng, 1)
		"screen_c":
			img = _screen(rng, 2)
		"screen_off":
			img = _screen(rng, 3)
		"screen_tablet":
			img = _screen(rng, 4)
		_:
			img = Image.create(4, 4, false, Image.FORMAT_RGB8)
			img.fill(Color(0.5, 0.5, 0.5))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[name] = t
	return t

## Bildschirminhalte im Stil des Leitstellenprogramms (dunkles Thema, Listen, Karte).
static func _screen(rng: RandomNumberGenerator, kind: int) -> Image:
	var img := Image.create(160, 96, false, Image.FORMAT_RGB8)
	var bg := Color(0.12, 0.13, 0.14)
	img.fill(bg)
	if kind == 3:
		img.fill(Color(0.03, 0.04, 0.05))
		img.fill_rect(Rect2i(66, 42, 28, 12), Color(0.12, 0.18, 0.28))
		return img
	img.fill_rect(Rect2i(0, 0, 160, 6), Color(0.2, 0.22, 0.24))
	match kind:
		0:  # Karte
			img.fill_rect(Rect2i(0, 6, 160, 90), Color(0.16, 0.19, 0.17))
			for i in 14:
				var y := rng.randi_range(8, 94)
				img.fill_rect(Rect2i(0, y, 160, 1), Color(0.42, 0.42, 0.38))
				var x := rng.randi_range(0, 159)
				img.fill_rect(Rect2i(x, 6, 1, 90), Color(0.42, 0.42, 0.38))
			for i in 9:
				var c: Color = [Color(0.95, 0.3, 0.2), Color(0.3, 0.75, 0.35), Color(0.95, 0.8, 0.2), Color(0.3, 0.55, 0.95)][i % 4]
				img.fill_rect(Rect2i(rng.randi_range(4, 150), rng.randi_range(10, 88), 4, 4), c)
		1:  # Einsatzliste
			for i in 11:
				var y := 9 + i * 8
				img.fill_rect(Rect2i(3, y, 154, 6), Color(0.17, 0.18, 0.2) if i % 2 == 0 else Color(0.14, 0.15, 0.16))
				img.fill_rect(Rect2i(4, y + 1, 10, 4), [Color(0.85, 0.25, 0.2), Color(0.95, 0.75, 0.2), Color(0.3, 0.6, 0.9)][i % 3])
				img.fill_rect(Rect2i(18, y + 2, rng.randi_range(40, 120), 2), Color(0.75, 0.76, 0.78))
		2:  # Fahrzeugstatus
			for i in 10:
				for j in 4:
					var col: Color = [Color(0.25, 0.7, 0.35), Color(0.25, 0.7, 0.35), Color(0.95, 0.75, 0.2), Color(0.85, 0.3, 0.25), Color(0.3, 0.55, 0.95)][rng.randi_range(0, 4)]
					img.fill_rect(Rect2i(4 + j * 39, 9 + i * 8, 6, 6), col)
					img.fill_rect(Rect2i(12 + j * 39, 11 + i * 8, 24, 2), Color(0.72, 0.73, 0.75))
		4:  # Telefon / Funk
			img.fill(Color(0.18, 0.2, 0.23))
			for i in 4:
				for j in 3:
					img.fill_rect(Rect2i(8 + j * 50, 14 + i * 20, 44, 16), Color(0.28, 0.32, 0.38) if (i + j) % 3 else Color(0.2, 0.5, 0.3))
	return img
