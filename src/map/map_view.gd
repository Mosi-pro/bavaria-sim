extends Control
## Interaktive Lagekarte: Verschieben, Zoomen, Auswahl von Fahrzeugen, Einsätzen,
## Wachen. Straßen/Gebäude werden chunkweise mit Detailstufen (LOD) gezeichnet.

const ChunkScript = preload("res://src/map/map_chunk.gd")
const GroundScript = preload("res://src/map/map_ground.gd")
const OverlayScript = preload("res://src/map/map_overlay.gd")

signal object_clicked(kind, id)
signal object_context(kind, id, screen_pos)
signal map_clicked(world_pos)
signal view_changed

var center := Vector2.ZERO
var zoom := 0.05
var sel := {"kind": "", "id": ""}
var hover := {}
var tool := ""
var tool_cb := Callable()
var tool_hint := ""
var mouse_world := Vector2.ZERO
var layers := {}

var _world_root: Node2D
var _ground: Node2D
var _chunk_root: Node2D
var _overlay: Control
var _chunks: Array = []
var _shown := {}
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _dirty := true

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	World.ensure_built()
	_world_root = Node2D.new()
	add_child(_world_root)
	_ground = Node2D.new()
	_ground.set_script(GroundScript)
	_world_root.add_child(_ground)
	_chunk_root = Node2D.new()
	_world_root.add_child(_chunk_root)
	_chunks.resize(World.chunks_x * World.chunks_y)
	_overlay = Control.new()
	_overlay.set_script(OverlayScript)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.view = self
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(func(): _dirty = true)
	Settings.changed.connect(reload_layers)
	reload_layers()
	call_deferred("zoom_fit")

func reload_layers() -> void:
	for k in ["labels", "buildings", "districts", "traffic", "pois", "stations", "routes", "idle_vehicles"]:
		layers[k] = Settings.get_v("map", k)
	_apply_ground()
	_dirty = true

func _apply_ground() -> void:
	if _ground != null and _ground.show_borders != layers.get("districts", true):
		_ground.show_borders = layers.get("districts", true)
		_ground.queue_redraw()

func set_layer(k: String, on: bool) -> void:
	layers[k] = on
	Settings.set_v("map", k, on)
	_apply_ground()
	_dirty = true

func fit_zoom() -> float:
	return min(size.x / World.bounds.size.x, size.y / World.bounds.size.y) * 0.98

func zoom_fit() -> void:
	center = World.bounds.get_center()
	zoom = max(0.005, fit_zoom())
	_dirty = true

func focus_on(p: Vector2, min_zoom := 0.6) -> void:
	center = p
	if zoom < min_zoom:
		zoom = min_zoom
	_dirty = true

func w2s(p: Vector2) -> Vector2:
	return (p - center) * zoom + size * 0.5

func s2w(p: Vector2) -> Vector2:
	return (p - size * 0.5) / zoom + center

func view_rect() -> Rect2:
	var half := size * 0.5 / zoom
	return Rect2(center - half, half * 2.0)

func set_tool(name: String, hint := "", cb := Callable()) -> void:
	tool = name
	tool_hint = hint
	tool_cb = cb
	mouse_default_cursor_shape = Control.CURSOR_CROSS if name != "" else Control.CURSOR_ARROW

func select(kind: String, id: String) -> void:
	sel = {"kind": kind, "id": id}

func _lod() -> int:
	if zoom < 0.03:
		return 0
	if zoom < 0.075:
		return 1
	if zoom < 0.2:
		return 2
	return 3

func _update_view() -> void:
	_dirty = false
	var b: Rect2 = World.bounds
	center.x = clampf(center.x, b.position.x, b.end.x)
	center.y = clampf(center.y, b.position.y, b.end.y)
	_world_root.position = size * 0.5 - center * zoom
	_world_root.scale = Vector2(zoom, zoom)
	var lod := _lod()
	var buildings: bool = zoom >= 0.5 and layers.get("buildings", true)
	var aa := Settings.quality_level() >= 1
	var vr := view_rect().grow(60.0)
	var cs: float = World.chunk_size
	var x0 := clampi(int((vr.position.x - b.position.x) / cs), 0, World.chunks_x - 1)
	var x1 := clampi(int((vr.end.x - b.position.x) / cs), 0, World.chunks_x - 1)
	var y0 := clampi(int((vr.position.y - b.position.y) / cs), 0, World.chunks_y - 1)
	var y1 := clampi(int((vr.end.y - b.position.y) / cs), 0, World.chunks_y - 1)
	var now := {}
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var idx := cy * World.chunks_x + cx
			if World.chunk_edges[idx].is_empty():
				continue
			var ch: Node2D = _chunks[idx]
			if ch == null:
				ch = Node2D.new()
				ch.set_script(ChunkScript)
				ch.setup(idx)
				_chunk_root.add_child(ch)
				_chunks[idx] = ch
			ch.visible = true
			ch.update_view(lod, zoom, buildings, aa)
			now[idx] = true
	for idx in _shown:
		if not now.has(idx):
			var ch: Node2D = _chunks[idx]
			ch.visible = false
			if not buildings or _shown.size() > 120:
				ch.drop_buildings()
	_shown = now
	_overlay.camera_changed()
	view_changed.emit()

func _process(_delta: float) -> void:
	if _dirty and size.x > 4.0:
		_update_view()
	# höchstens ein Gebäude-Chunk je Frame nachladen
	for idx in _shown:
		var ch: Node2D = _chunks[idx]
		if ch.needs_buildings():
			ch.generate_buildings()
			break
	if is_visible_in_tree():
		_overlay.queue_redraw()

func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := s2w(screen)
	zoom = clampf(zoom * factor, max(0.004, fit_zoom() * 0.7), 6.0)
	center += before - s2w(screen)
	_dirty = true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.18)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.18)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_pos = mb.position
				if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
					_zoom_at(mb.position, 1.6)
			else:
				if _pressed and not _dragging and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position)
				_pressed = false
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if tool != "":
				set_tool("")
			else:
				var o := object_at(mb.position)
				if not o.is_empty():
					object_context.emit(o["kind"], o["id"], mb.global_position)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		mouse_world = s2w(mm.position)
		if _pressed:
			if not _dragging and mm.position.distance_to(_press_pos) > 4.0:
				_dragging = true
			if _dragging:
				center -= mm.relative / zoom
				_dirty = true
		else:
			hover = object_at(mm.position)
	elif event is InputEventKey and event.pressed:
		var step := 120.0 / zoom
		match event.keycode:
			KEY_LEFT: center.x -= step; _dirty = true
			KEY_RIGHT: center.x += step; _dirty = true
			KEY_UP: center.y -= step; _dirty = true
			KEY_DOWN: center.y += step; _dirty = true
			KEY_PLUS, KEY_KP_ADD: _zoom_at(size * 0.5, 1.18)
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom_at(size * 0.5, 1.0 / 1.18)
			KEY_ESCAPE:
				if tool != "":
					set_tool("")

func _click(pos: Vector2) -> void:
	var wp := s2w(pos)
	if tool != "":
		var cb := tool_cb
		var t := tool
		if t != "closure":
			set_tool("")
		if cb.is_valid():
			cb.call(wp)
		return
	var o := object_at(pos)
	if o.is_empty():
		sel = {"kind": "", "id": ""}
		map_clicked.emit(wp)
	else:
		sel = {"kind": o["kind"], "id": o["id"]}
		object_clicked.emit(o["kind"], o["id"])

func vehicle_drawn(v: Dictionary) -> bool:
	if v["state"] == "station" or v["state"] == "oos":
		return layers.get("idle_vehicles", false) and zoom >= 0.8
	return true

## Objekt unter dem Mauszeiger: {kind, id, text}
func object_at(pos: Vector2) -> Dictionary:
	if not State.active:
		return {}
	var best := {}
	var bd := 13.0
	for id in State.vehicles:
		var v: Dictionary = State.vehicles[id]
		if not vehicle_drawn(v):
			continue
		var d := w2s(State.veh_pos(v)).distance_to(pos)
		if d < bd:
			bd = d
			best = {"kind": "vehicle", "id": id, "text": "%s  ·  %s  ·  Status %d %s" % [v["callsign"], Data.vehicle_types[v["type"]]["short"], int(v["status"]), Data.fms_text(int(v["status"]))]}
	if not best.is_empty():
		return best
	for id in State.incidents:
		var inc: Dictionary = State.incidents[id]
		var d := w2s(Vector2(inc["x"], inc["y"])).distance_to(pos)
		if d < bd:
			bd = d
			best = {"kind": "incident", "id": id, "text": "Einsatz %s  ·  %s  ·  %s" % [inc["nr"], inc["keyword"], inc["address"]]}
	for id in State.calls:
		var c: Dictionary = State.calls[id]
		if c["state"] != "active" or c["loc"].is_empty():
			continue
		var d := w2s(Vector2(c["loc"]["x"], c["loc"]["y"])).distance_to(pos)
		if d < bd:
			bd = d
			best = {"kind": "call", "id": id, "text": "Notruf  ·  %s" % c["loc"]["text"]}
	if not best.is_empty():
		return best
	if layers.get("stations", true) and zoom >= 0.02:
		for id in State.stations:
			var st: Dictionary = State.stations[id]
			var d := w2s(Vector2(st["x"], st["y"])).distance_to(pos)
			if d < bd:
				bd = d
				best = {"kind": "station", "id": id, "text": "%s  ·  %s" % [st["name"], st["address"]]}
		for h in Sim.hospitals:
			var d := w2s(h["p"]).distance_to(pos)
			if d < bd:
				bd = d
				best = {"kind": "hospital", "id": h["id"], "text": "%s  ·  Versorgungsstufe %d  ·  %d Betten" % [h["name"], int(h["level"]), int(h["beds"])]}
	if best.is_empty() and layers.get("pois", true) and zoom >= 0.1:
		for p in World.pois:
			var d := w2s(p["p"]).distance_to(pos)
			if d < bd:
				bd = d
				best = {"kind": "poi", "id": p["id"], "text": p["name"]}
	return best
