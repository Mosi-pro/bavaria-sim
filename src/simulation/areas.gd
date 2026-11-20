extends RefCounted
## Mehrspieler: Aufteilung der Stadt in Zuständigkeitsgebiete (data/game_modes.json → "areas").
## Ein Spieler mit leerer Gebietsliste ist für die ganze Stadt zuständig.

static func list() -> Dictionary:
	return Data.modes.get("areas", {}).get("list", {})

static func overflow() -> float:
	return float(Data.modes.get("areas", {}).get("overflow", 20))

static func name(a: String) -> String:
	return String(list().get(a, {}).get("name", a))

static func color(a: String) -> Color:
	return Color(String(list().get(a, {}).get("color", "#a4adb5")))

## Gebiet an einer Position ("" wenn keines passt).
static func of_pos(p: Vector2) -> String:
	if World.districts.is_empty():
		return ""
	var did: String = String(World.districts[World.district_at(p)]["id"])
	var l := list()
	for a in l:
		if l[a].get("districts", []).has(did):
			return a
	return ""

static func names(areas: Array) -> String:
	if areas.is_empty():
		return "ganze Stadt"
	return ", ".join(areas.map(func(a): return name(a)))

## Wer ist (laut Lobby) für dieses Gebiet zuständig? Namen der Spieler.
static func owners(a: String) -> Array:
	var out: Array = []
	for pid in State.players:
		var ar: Array = State.players[pid].get("area", [])
		if ar.has(a):
			out.append(String(State.players[pid]["name"]))
	return out

## Darf ein Spieler etwas in Gebiet a bearbeiten?
## Ja, wenn er die ganze Stadt hat, das Gebiet zu seinen gehört, Schichtführung ist
## oder niemand sonst für das Gebiet eingeteilt ist.
static func may(player: Dictionary, a: String) -> bool:
	var mine: Array = player.get("area", [])
	if mine.is_empty() or a == "" or mine.has(a) or player.get("role", "") == "leitung":
		return true
	return owners(a).is_empty()

static func mine(player: Dictionary, a: String) -> bool:
	var ar: Array = player.get("area", [])
	return ar.is_empty() or a == "" or ar.has(a)

## Gebiete gleichmäßig auf n Spieler verteilen (Rückgabe: Liste von Gebietslisten).
static func distribute(n: int) -> Array:
	var keys: Array = list().keys()
	var out: Array = []
	for i in n:
		out.append([])
	if n <= 1:
		return out
	for i in keys.size():
		out[i % n].append(keys[i])
	return out
