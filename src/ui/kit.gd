extends RefCounted
## UI-Baukasten: Leitstellen-Theme (sachliches, dichtes Desktop-Design) und Hilfsfunktionen.

const BG := Color("#202326")
const MAIN := Color("#292D31")
const SEC := Color("#34393E")
const TABLE := Color("#25292D")
const TEXT := Color("#E5E7E9")
const TEXT2 := Color("#A4ADB5")
const RED := Color("#C83D3D")
const YELLOW := Color("#D6A83B")
const GREEN := Color("#4C9868")
const BLUE := Color("#497FA8")
const BORDER := Color("#454B52")
const HOVER := Color("#3D434A")
const SELECT := Color("#35506A")

static var _font: Font
static var _mono: Font
static var _bold: Font
static var _theme: Theme

static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "DejaVu Sans", "Arial", "sans-serif"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_NORMAL
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_font = f
	return _font

static func bold() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Semibold", "Segoe UI", "Noto Sans", "DejaVu Sans", "Arial", "sans-serif"])
		f.font_weight = 600
		_bold = f
	return _bold

static func mono() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Lucida Console", "DejaVu Sans Mono", "Noto Sans Mono", "monospace"])
		_mono = f
	return _mono

static func box(bg: Color, border: Color = Color(0, 0, 0, 0), bw := 1, pad := 4, radius := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	if border.a > 0.0:
		s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = max(1, pad - 2)
	s.content_margin_bottom = max(1, pad - 2)
	s.anti_aliasing = false
	return s

static func _icon(kind: String, col: Color, n := 12) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(2, n - 2):
		match kind:
			"x":
				img.set_pixel(i, i, col); img.set_pixel(n - 1 - i, i, col)
				img.set_pixel(i + 1 if i + 1 < n else i, i, col); img.set_pixel(n - i if n - i < n else n - 1 - i, i, col)
			"down":
				pass
	if kind == "down":
		for y in 4:
			for x in range(y, 8 - y):
				img.set_pixel(2 + x, 4 + y, col)
	return ImageTexture.create_from_image(img)

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 12
	var flat := box(SEC, BORDER, 1, 8)
	var flat_h := box(HOVER, Color("#5a626b"), 1, 8)
	var flat_p := box(Color("#2b3035"), BLUE, 1, 8)
	var flat_d := box(Color("#2b2f33"), Color("#3a3f45"), 1, 8)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, flat)
		t.set_stylebox("hover", cls, flat_h)
		t.set_stylebox("pressed", cls, flat_p)
		t.set_stylebox("disabled", cls, flat_d)
		t.set_stylebox("focus", cls, box(Color(0, 0, 0, 0), BLUE, 1, 8))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color("#6b737b"))
		t.set_constant("h_separation", cls, 4)
	t.set_stylebox("normal", "MenuButton", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8))
	for cls in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("hover", cls, box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("pressed", cls, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("hover_pressed", cls, box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("focus", cls, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2))
		t.set_color("font_color", cls, TEXT)
	var edit := box(Color("#1c1f22"), BORDER, 1, 5)
	var edit_f := box(Color("#1c1f22"), BLUE, 1, 5)
	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, edit)
		t.set_stylebox("focus", cls, edit_f)
		t.set_stylebox("read_only", cls, box(Color("#23262a"), Color("#3a3f45"), 1, 5))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_placeholder_color", cls, Color("#6b737b"))
		t.set_color("caret_color", cls, TEXT)
		t.set_color("selection_color", cls, SELECT)
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 2)
	t.set_stylebox("panel", "PanelContainer", box(MAIN, BORDER, 1, 4))
	t.set_stylebox("panel", "Panel", box(MAIN, BORDER, 1, 0))
	# Tabellen / Listen
	for cls in ["Tree", "ItemList"]:
		t.set_stylebox("panel", cls, box(TABLE, BORDER, 1, 1))
		t.set_stylebox("focus", cls, box(Color(0, 0, 0, 0)))
		t.set_stylebox("selected", cls, box(SELECT, Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("selected_focus", cls, box(SELECT, Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("hovered", cls, box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("cursor", cls, box(Color(0, 0, 0, 0), Color("#5d7f9c"), 1, 2))
		t.set_stylebox("cursor_unfocused", cls, box(Color(0, 0, 0, 0)))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_selected_color", cls, Color.WHITE)
		t.set_color("guide_color", cls, Color("#30353a"))
		t.set_constant("v_separation", cls, 3)
		t.set_constant("h_separation", cls, 4)
	t.set_stylebox("title_button_normal", "Tree", box(SEC, BORDER, 1, 4))
	t.set_stylebox("title_button_hover", "Tree", box(HOVER, BORDER, 1, 4))
	t.set_stylebox("title_button_pressed", "Tree", box(HOVER, BORDER, 1, 4))
	t.set_color("title_button_color", "Tree", TEXT2)
	t.set_color("relationship_line_color", "Tree", Color("#3a3f45"))
	t.set_constant("draw_guides", "Tree", 1)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_constant("item_margin", "Tree", 10)
	t.set_constant("inner_item_margin_left", "Tree", 3)
	t.set_constant("scrollbar_margin_right", "Tree", 0)
	# Menüs
	t.set_stylebox("panel", "PopupMenu", box(Color("#2d3136"), Color("#5a626b"), 1, 3))
	t.set_stylebox("hover", "PopupMenu", box(SELECT, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("separator", "PopupMenu", _line(BORDER))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", Color("#6b737b"))
	t.set_color("font_accelerator_color", "PopupMenu", TEXT2)
	t.set_color("font_separator_color", "PopupMenu", TEXT2)
	t.set_constant("v_separation", "PopupMenu", 5)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 16)
	t.set_stylebox("normal", "MenuBar", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 7))
	t.set_stylebox("hover", "MenuBar", box(HOVER, Color(0, 0, 0, 0), 0, 7))
	t.set_stylebox("pressed", "MenuBar", box(SELECT, Color(0, 0, 0, 0), 0, 7))
	t.set_stylebox("focus", "MenuBar", box(Color(0, 0, 0, 0)))
	t.set_color("font_color", "MenuBar", TEXT)
	t.set_color("font_hover_color", "MenuBar", Color.WHITE)
	t.set_constant("h_separation", "MenuBar", 0)
	# Reiter
	t.set_stylebox("panel", "TabContainer", box(MAIN, BORDER, 1, 2))
	for cls in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", cls, _tab(MAIN, true))
		t.set_stylebox("tab_unselected", cls, _tab(Color("#23272a"), false))
		t.set_stylebox("tab_hovered", cls, _tab(SEC, false))
		t.set_stylebox("tab_disabled", cls, _tab(Color("#23272a"), false))
		t.set_stylebox("tab_focus", cls, box(Color(0, 0, 0, 0)))
		t.set_color("font_selected_color", cls, Color.WHITE)
		t.set_color("font_unselected_color", cls, TEXT2)
		t.set_color("font_hovered_color", cls, TEXT)
	t.set_stylebox("tabbar_background", "TabContainer", box(BG, Color(0, 0, 0, 0), 0, 0))
	# Fenster
	var wb := box(MAIN, Color("#5a626b"), 1, 0)
	wb.expand_margin_top = 26
	wb.border_width_top = 26
	wb.border_color = Color("#3b4148")
	wb.shadow_color = Color(0, 0, 0, 0.45)
	wb.shadow_size = 8
	var wbu: StyleBoxFlat = wb.duplicate()
	wbu.border_color = Color("#30353a")
	wbu.shadow_size = 3
	t.set_stylebox("embedded_border", "Window", wb)
	t.set_stylebox("embedded_unfocused_border", "Window", wbu)
	t.set_constant("title_height", "Window", 26)
	t.set_constant("resize_margin", "Window", 5)
	t.set_constant("close_h_offset", "Window", 20)
	t.set_constant("close_v_offset", "Window", 19)
	t.set_color("title_color", "Window", TEXT)
	t.set_font("title_font", "Window", bold())
	t.set_font_size("title_font_size", "Window", 12)
	t.set_icon("close", "Window", _icon("x", TEXT2))
	t.set_icon("close_pressed", "Window", _icon("x", Color.WHITE))
	for cls in ["AcceptDialog", "ConfirmationDialog"]:
		t.set_stylebox("panel", cls, box(MAIN, Color(0, 0, 0, 0), 0, 10))
	# Scrollbars
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, box(Color("#1f2225"), Color(0, 0, 0, 0), 0, 5))
		t.set_stylebox("grabber", cls, box(Color("#4a5159"), Color(0, 0, 0, 0), 0, 5))
		t.set_stylebox("grabber_highlight", cls, box(Color("#5d656e"), Color(0, 0, 0, 0), 0, 5))
		t.set_stylebox("grabber_pressed", cls, box(BLUE, Color(0, 0, 0, 0), 0, 5))
	t.set_stylebox("separator", "HSeparator", _line(BORDER))
	t.set_stylebox("separator", "VSeparator", _line(BORDER, true))
	t.set_stylebox("normal", "RichTextLabel", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("focus", "RichTextLabel", box(Color(0, 0, 0, 0)))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(Color("#16181a"), Color("#5a626b"), 1, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("background", "ProgressBar", box(Color("#1c1f22"), BORDER, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(BLUE, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("slider", "HSlider", box(Color("#1c1f22"), BORDER, 1, 3))
	t.set_stylebox("grabber_area", "HSlider", box(BLUE, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(BLUE, Color(0, 0, 0, 0), 0, 3))
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 4)
	t.set_constant("separation", "HSplitContainer", 4)
	t.set_constant("separation", "VSplitContainer", 4)
	t.set_constant("h_separation", "GridContainer", 8)
	t.set_constant("v_separation", "GridContainer", 4)
	_theme = t
	return t

static func _line(col: Color, vertical := false) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = col
	s.thickness = 1
	s.vertical = vertical
	return s

static func _tab(bg: Color, selected: bool) -> StyleBoxFlat:
	var s := box(bg, BORDER, 1, 10)
	s.border_width_bottom = 0
	if selected:
		s.border_width_top = 2
		s.border_color = BLUE
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

# ---------------------------------------------------------------- Bausteine
static func label(text: String, col: Color = TEXT, size := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	if size != 12:
		l.add_theme_font_size_override("font_size", size)
	return l

static func caption(text: String) -> Label:
	var l := label(text.to_upper(), TEXT2, 10)
	return l

static func button(text: String, cb: Callable = Callable(), tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func accent(b: Button, col: Color) -> Button:
	b.add_theme_stylebox_override("normal", box(col.darkened(0.25), col, 1, 10))
	b.add_theme_stylebox_override("hover", box(col.darkened(0.1), col.lightened(0.2), 1, 10))
	b.add_theme_stylebox_override("pressed", box(col.darkened(0.35), col, 1, 10))
	b.add_theme_color_override("font_color", Color.WHITE)
	return b

static func hbox(children: Array = [], sep := 4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h

static func vbox(children: Array = [], sep := 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for c in children:
		v.add_child(c)
	return v

static func expand(c: Control, h := true, v := false) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func margin(child: Control, m := 6) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(child)
	return mc

## Titelzeile eines Bereichs (dunkler Streifen mit Beschriftung).
static func header(text: String, right: Array = []) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(SEC, BORDER, 1, 6))
	var l := label(text, TEXT)
	l.add_theme_font_override("font", bold())
	var h := hbox([l, spacer()])
	for c in right:
		h.add_child(c)
	p.add_child(h)
	p.set_meta("label", l)
	return p

static func tree(columns: Array, titles := true) -> Tree:
	var t := Tree.new()
	t.columns = columns.size()
	t.hide_root = true
	t.column_titles_visible = titles
	t.select_mode = Tree.SELECT_ROW
	t.allow_rmb_select = true
	t.scroll_horizontal_enabled = false
	for i in columns.size():
		var c: Dictionary = columns[i]
		t.set_column_title(i, c.get("title", ""))
		t.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		if c.has("width"):
			t.set_column_custom_minimum_width(i, int(c["width"]))
			t.set_column_expand(i, c.get("expand", false))
		else:
			t.set_column_expand(i, true)
		t.set_column_clip_content(i, true)
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return t

static func rich(mono_font := false) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_following = true
	r.selection_enabled = true
	r.focus_mode = Control.FOCUS_CLICK
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mono_font:
		r.add_theme_font_override("normal_font", mono())
		r.add_theme_font_override("bold_font", mono())
		r.add_theme_font_size_override("normal_font_size", 12)
	r.add_theme_stylebox_override("normal", box(TABLE, BORDER, 1, 6))
	return r

static func line_edit(placeholder := "", text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e

static func option(items: Array, selected := 0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	if items.size() > 0:
		o.select(clampi(selected, 0, items.size() - 1))
	o.focus_mode = Control.FOCUS_NONE
	return o

static func form(rows: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	for r in rows:
		var l := label(r[0], TEXT2)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(l)
		var c: Control = r[1]
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(c)
	return g

## Eingebettetes Programmfenster mit Standardverhalten.
static func window(parent: Node, title: String, size: Vector2i, content: Control, key := "") -> Window:
	if key != "":
		for c in parent.get_children():
			if c is Window and c.get_meta("key", "") == key:
				c.grab_focus()
				c.move_to_foreground()
				return null
	var w := Window.new()
	w.title = title
	w.size = size
	w.min_size = Vector2i(min(size.x, 320), min(size.y, 200))
	w.wrap_controls = true
	w.set_meta("key", key)
	w.close_requested.connect(w.queue_free)
	var bgp := Panel.new()
	bgp.add_theme_stylebox_override("panel", box(MAIN))
	bgp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(bgp)
	var m := margin(content, 8)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(m)
	parent.add_child(w)
	var vp: Vector2 = parent.get_viewport().get_visible_rect().size
	var n: int = parent.get_meta("win_n", 0)
	parent.set_meta("win_n", (n + 1) % 8)
	var pos := (Vector2i(vp) - size) / 2 + Vector2i(n * 22 - 60, n * 22 - 30)
	pos.x = clampi(pos.x, 4, max(4, int(vp.x) - size.x - 4))
	pos.y = clampi(pos.y, 60, max(60, int(vp.y) - size.y - 4))
	w.position = pos
	w.show()
	return w

static func message(parent: Node, title: String, text: String) -> void:
	var d := AcceptDialog.new()
	d.title = title
	d.dialog_text = text
	d.dialog_autowrap = true
	d.min_size = Vector2i(420, 140)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	parent.add_child(d)
	d.popup_centered()

static func confirm(parent: Node, title: String, text: String, cb: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	d.dialog_text = text
	d.dialog_autowrap = true
	d.min_size = Vector2i(420, 140)
	d.ok_button_text = "Ja"
	d.cancel_button_text = "Abbrechen"
	d.confirmed.connect(func():
		cb.call()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	parent.add_child(d)
	d.popup_centered()

static func short_callsign(v: Dictionary) -> String:
	var cs: String = v["callsign"]
	return cs.replace("Florian Bavaria ", "FL ").replace("Rettung Bavaria ", "RK ").replace("Kater Bavaria ", "KAT ").replace("Heros Bavaria ", "HRS ").replace("Pelikan Bavaria ", "PEL ")

static func money(v: int) -> String:
	var s := str(abs(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out + " €"

static func hex(c: Color) -> String:
	return "#" + c.to_html(false)
