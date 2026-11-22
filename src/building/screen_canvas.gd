extends Control
## Zeichenfläche für die Bildschirme der 3D-Leitstelle (wird in ein SubViewport gerendert).
## Inhalte kommen live aus der Simulation; alle Texte werden auf ihre Felder gekürzt,
## damit nichts über die Ränder hinausläuft.

var kind := "map"
var font: Font
var _map_cache: PackedVector2Array
var _map_cls: PackedByteArray
var _map_rect := Rect2()

const BG := Color(0.07, 0.085, 0.1)
const HEAD := Color(0.12, 0.15, 0.19)
const TXT := Color(0.86, 0.88, 0.9)
const DIM := Color(0.55, 0.6, 0.65)
const RED := Color(0.9, 0.25, 0.2)
const YEL := Color(0.95, 0.75, 0.2)
const GRN := Color(0.3, 0.75, 0.4)
const BLU := Color(0.3, 0.6, 0.95)
const STATUS_COL := {1: GRN, 2: GRN, 3: YEL, 4: RED, 5: BLU, 6: Color(0.45, 0.45, 0.48), 7: Color(0.95, 0.5, 0.2), 8: Color(0.6, 0.45, 0.9)}

func _ready() -> void:
	font = ThemeDB.fallback_font

## Text in ein Feld der Breite w setzen (bei Bedarf mit „…“ kürzen).
func _text(t: String, pos: Vector2, size: int, w: float, col := TXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var s := t
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
		while s.length() > 1 and font.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
			s = s.substr(0, s.length() - 1)
		s += "…"
	draw_string(font, pos, s, align, w, size, col)

func _header(title: String, right := "") -> void:
	draw_rect(Rect2(0, 0, size.x, 26), HEAD)
	_text(title, Vector2(10, 18), 14, size.x * 0.65, TXT)
	if right != "":
		_text(right, Vector2(size.x * 0.65, 18), 14, size.x * 0.35 - 10, DIM, HORIZONTAL_ALIGNMENT_RIGHT)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if not State.active and kind != "login":
		_header("ELS Bavaria")
		return
	match kind:
		"map": _draw_map()
		"list": _draw_list()
		"status": _draw_status()
		"wall": _draw_wall()
		"login": _draw_login()

func _build_map_cache() -> void:
	# Ausschnitt um die Stadtmitte, nur Hauptstraßen (Klassen 0–2) für eine ruhige Darstellung
	_map_rect = Rect2(-4200, -3200, 8400, 5600)
	var pts := PackedVector2Array()
	var cls := PackedByteArray()
	for i in World.edge_a.size():
		var c := int(World.edge_cls[i]) if i < World.edge_cls.size() else 3
		if c > 4 and c != 6:
			continue
		if c == 6:
			c = 2
		var a: Vector2 = World.node_pos[World.edge_a[i]]
		var b: Vector2 = World.node_pos[World.edge_b[i]]
		if not _map_rect.has_point(a) and not _map_rect.has_point(b):
			continue
		pts.append(a)
		pts.append(b)
		cls.append(c)
	_map_cache = pts
	_map_cls = cls

func _to_screen(p: Vector2, area: Rect2) -> Vector2:
	return area.position + (p - _map_rect.position) / _map_rect.size * area.size

func _draw_map() -> void:
	if _map_cache.is_empty():
		_build_map_cache()
	var area := Rect2(0, 26, size.x, size.y - 26)
	draw_rect(area, Color(0.1, 0.12, 0.12))
	var by_cls := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	for i in _map_cls.size():
		var c := mini(int(_map_cls[i]), 4)
		by_cls[c].append(_to_screen(_map_cache[i * 2], area))
		by_cls[c].append(_to_screen(_map_cache[i * 2 + 1], area))
	var cols := [Color(0.9, 0.62, 0.3), Color(0.85, 0.62, 0.3), Color(0.9, 0.8, 0.45), Color(0.62, 0.62, 0.6), Color(0.32, 0.34, 0.35)]
	var widths := [3.0, 2.0, 2.2, 1.4, 0.8]
	for c in [4, 3, 2, 1, 0]:
		if by_cls[c].size() >= 2:
			draw_multiline(by_cls[c], cols[c], widths[c])
	for id in State.vehicles:
		var v: Dictionary = State.vehicles[id]
		var p := Vector2(float(v["x"]), float(v["y"]))
		if _map_rect.has_point(p):
			draw_rect(Rect2(_to_screen(p, area) - Vector2(2.5, 2.5), Vector2(5, 5)), STATUS_COL.get(int(v["status"]), DIM))
	for id in State.incidents:
		var inc: Dictionary = State.incidents[id]
		var p := Vector2(float(inc["x"]), float(inc["y"]))
		if _map_rect.has_point(p):
			var sp := _to_screen(p, area)
			draw_circle(sp, 7.0, Color(RED, 0.35))
			draw_circle(sp, 3.5, RED)
	_header("Lagekarte Bavaria", State.time_str().substr(0, 5))

func _draw_list() -> void:
	_header("Einsätze", "%d laufend" % State.incidents.size())
	var ids: Array = State.incidents.keys()
	ids.sort()
	ids.reverse()
	var y := 32.0
	var row_h := 22.0
	var i := 0
	for id in ids:
		if y + row_h > size.y:
			break
		var inc: Dictionary = State.incidents[id]
		if i % 2 == 0:
			draw_rect(Rect2(4, y, size.x - 8, row_h - 2), Color(0.1, 0.12, 0.14))
		var kw := String(inc.get("keyword", ""))
		draw_rect(Rect2(8, y + 4, 6, row_h - 10), RED if kw.begins_with("B") else (YEL if kw.begins_with("TH") else BLU))
		_text(kw, Vector2(20, y + 15), 12, 70, TXT)
		_text(String(inc.get("address", "")), Vector2(94, y + 15), 12, size.x - 104, DIM)
		y += row_h
		i += 1
	if ids.is_empty():
		_text("Keine laufenden Einsätze", Vector2(10, 52), 13, size.x - 20, DIM)
	var ringing := 0
	for cid in State.calls:
		if State.calls[cid]["state"] == "ringing":
			ringing += 1
	if ringing > 0:
		draw_rect(Rect2(0, size.y - 24, size.x, 24), Color(0.45, 0.08, 0.06))
		_text("☎  %d Notruf%s wartend" % [ringing, "e" if ringing != 1 else ""], Vector2(10, size.y - 7), 13, size.x - 20, Color(1, 0.9, 0.88))

func _draw_status() -> void:
	_header("Fahrzeuge", "%d gesamt" % State.vehicles.size())
	var ids: Array = State.vehicles.keys()
	ids.sort()
	var cols := 2
	var cw := (size.x - 12) / cols
	var row_h := 19.0
	var rows := int((size.y - 34) / row_h)
	var n := 0
	for id in ids:
		if n >= rows * cols:
			break
		var v: Dictionary = State.vehicles[id]
		var c := n / rows
		var r := n % rows
		var x := 6.0 + c * cw
		var y := 32.0 + r * row_h
		var st := int(v["status"])
		draw_rect(Rect2(x, y + 2, 16, row_h - 5), STATUS_COL.get(st, DIM))
		_text(str(st), Vector2(x + 4, y + 13), 11, 12, Color(0.05, 0.05, 0.05))
		_text(String(v.get("callsign", id)).replace("Florian Bavaria ", "FL ").replace("Rettung Bavaria ", "RK "), Vector2(x + 22, y + 13), 11, cw - 28, TXT)
		n += 1

func _draw_login() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.13))
	var c := size * 0.5
	draw_rect(Rect2(c.x - 120, c.y - 40, 240, 80), Color(0.1, 0.15, 0.22))
	_text("ELS Bavaria", Vector2(c.x - 110, c.y - 12), 16, 220, TXT, HORIZONTAL_ALIGNMENT_CENTER)
	_text("Arbeitsplatz frei – bitte anmelden", Vector2(c.x - 110, c.y + 16), 11, 220, DIM, HORIZONTAL_ALIGNMENT_CENTER)

## Großbildwand: Einsatzübersicht links, Fahrzeugstatus rechts, Kopfzeile mit Lage.
func _draw_wall() -> void:
	var ringing := 0
	for cid in State.calls:
		if State.calls[cid]["state"] == "ringing":
			ringing += 1
	draw_rect(Rect2(0, 0, size.x, 44), HEAD)
	_text("INTEGRIERTE LEITSTELLE BAVARIA  –  LAGEÜBERSICHT", Vector2(16, 30), 22, size.x * 0.6, TXT)
	_text("%s   %s" % [State.date_str(), State.time_str().substr(0, 5)], Vector2(size.x * 0.6, 30), 22, size.x * 0.4 - 16, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	var lw := size.x * 0.62
	# Kennzahlen
	var tiles := [["Notrufe wartend", str(ringing), RED if ringing > 0 else GRN], ["Laufende Einsätze", str(State.incidents.size()), YEL], ["Fahrzeuge", str(State.vehicles.size()), BLU]]
	for i in tiles.size():
		var r := Rect2(16 + i * (lw - 16) / 3.0, 56, (lw - 16) / 3.0 - 12, 70)
		draw_rect(r, Color(0.1, 0.12, 0.15))
		draw_rect(Rect2(r.position, Vector2(6, r.size.y)), tiles[i][2])
		_text(tiles[i][1], r.position + Vector2(18, 44), 34, r.size.x - 24, TXT)
		_text(tiles[i][0], r.position + Vector2(18, 63), 13, r.size.x - 24, DIM)
	# Einsatzliste
	var ids: Array = State.incidents.keys()
	ids.sort()
	ids.reverse()
	var y := 140.0
	draw_rect(Rect2(16, y, lw - 28, 26), Color(0.12, 0.14, 0.17))
	_text("Stichwort", Vector2(24, y + 18), 14, 110, DIM)
	_text("Einsatzort", Vector2(140, y + 18), 14, lw * 0.45, DIM)
	_text("Nr.", Vector2(lw - 150, y + 18), 14, 130, DIM)
	y += 30
	var row_h := 28.0
	var i := 0
	for id in ids:
		if y + row_h > size.y - 8:
			break
		var inc: Dictionary = State.incidents[id]
		if i % 2 == 0:
			draw_rect(Rect2(16, y, lw - 28, row_h - 2), Color(0.09, 0.11, 0.13))
		var kw := String(inc.get("keyword", ""))
		draw_rect(Rect2(20, y + 6, 6, row_h - 14), RED if kw.begins_with("B") else (YEL if kw.begins_with("TH") else BLU))
		_text(kw, Vector2(34, y + 19), 15, 100, TXT)
		_text(String(inc.get("address", "")), Vector2(140, y + 19), 15, lw - 300, TXT)
		_text(String(inc.get("nr", "")), Vector2(lw - 150, y + 19), 13, 130, DIM)
		y += row_h
		i += 1
	if ids.is_empty():
		_text("Keine laufenden Einsätze", Vector2(24, y + 22), 16, lw - 40, DIM)
	# Fahrzeugstatus
	var rx := lw + 8
	var rw := size.x - rx - 16
	draw_rect(Rect2(rx, 56, rw, size.y - 64), Color(0.09, 0.11, 0.13))
	_text("FAHRZEUGSTATUS (FMS)", Vector2(rx + 12, 82), 16, rw - 24, TXT)
	var counts := {}
	for vid in State.vehicles:
		var st := int(State.vehicles[vid]["status"])
		counts[st] = int(counts.get(st, 0)) + 1
	var names := {1: "Einsatzbereit Funk", 2: "Einsatzbereit Wache", 3: "Einsatz übernommen", 4: "Am Einsatzort", 7: "Patient aufgenommen", 8: "Am Transportziel", 5: "Sprechwunsch", 6: "Nicht einsatzbereit"}
	var yy := 100.0
	var total := maxi(1, State.vehicles.size())
	for st in [1, 2, 3, 4, 7, 8, 5, 6]:
		var cnt := int(counts.get(st, 0))
		draw_rect(Rect2(rx + 12, yy, 24, 24), STATUS_COL[st])
		_text(str(st), Vector2(rx + 19, yy + 18), 15, 14, Color(0.05, 0.05, 0.05))
		_text(names[st], Vector2(rx + 46, yy + 18), 14, rw * 0.55, TXT)
		var bw := (rw - rw * 0.55 - 110) * float(cnt) / total
		draw_rect(Rect2(rx + 50 + rw * 0.55, yy + 6, maxf(bw, 1.0), 12), Color(STATUS_COL[st], 0.7))
		_text(str(cnt), Vector2(rx + rw - 54, yy + 18), 15, 40, TXT, HORIZONTAL_ALIGNMENT_RIGHT)
		yy += 34
