extends RefCounted
## Beta-Tester-Version: Nur die Beta-EXE (Exportvorlage »Windows Beta«, Feature-Tag "beta")
## verlangt beim Start einen Tester-Zugangscode. Im Spiel liegen ausschließlich gesalzene
## SHA-256-Prüfwerte der Codes (res://data/beta/zugang.json), nie die Codes selbst.
## Die Liste wird nur aus dem Spielpaket gelesen (nicht aus dem config-Ordner überschreibbar).

const LIST := "res://data/beta/zugang.json"

static func is_beta() -> bool:
	return OS.has_feature("beta")

static func _list() -> Dictionary:
	if not FileAccess.file_exists(LIST):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(LIST))
	return d if typeof(d) == TYPE_DICTIONARY else {}

## Großbuchstaben, nur Buchstaben/Ziffern, Präfix »LB« entfernen.
static func normalize(code: String) -> String:
	var out := ""
	for ch in code.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	if out.begins_with("LB") and out.length() == 14:
		out = out.substr(2)
	return out

static func code_hash(code: String, salt: String) -> String:
	return ("%s:%s" % [salt, normalize(code)]).sha256_text()

## Rückgabe: Testernummer oder -1, wenn der Code ungültig ist.
static func check(code: String, l: Dictionary = {}) -> int:
	if l.is_empty():
		l = _list()
	var n := normalize(code)
	if n.length() != 12:
		return -1
	var h := code_hash(n, String(l.get("salt", "")))
	var codes: Dictionary = l.get("codes", {})
	for nr in codes:
		if String(codes[nr]) == h:
			return int(nr)
	return -1

## Gespeicherte Freischaltung noch gültig? (Gesperrte Codes fallen mit dem nächsten Update heraus.)
static func unlocked_nr() -> int:
	var h: String = String(LocalDB.fetch("beta", "hash", ""))
	if h == "":
		return -1
	var codes: Dictionary = _list().get("codes", {})
	for nr in codes:
		if String(codes[nr]) == h:
			return int(nr)
	return -1

static func unlock(code: String) -> int:
	var nr := check(code)
	if nr >= 0:
		LocalDB.put("beta", "hash", code_hash(code, String(_list().get("salt", ""))))
	return nr
