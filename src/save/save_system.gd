extends RefCounted
## Spielstände: Binärdatei (Godot-Variant, ohne Objekte) je Spielstand unter
## user://saves, Index mit Metadaten in der lokalen Datenbank (Tabelle savegames).

const DIR := "user://saves"

static func slug(name: String) -> String:
	var s := ""
	for ch in name.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			s += ch
		elif ch in [" ", "-", "_", "."]:
			s += "_"
	if s == "":
		s = "spielstand"
	return s.substr(0, 48)

static func save(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var id := slug(name)
	State.meta["name"] = name
	var path := "%s/%s.sav" % [DIR, id]
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return "Spielstand konnte nicht geschrieben werden."
	f.store_var(State.to_dict(true), false)
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)
	LocalDB.put("savegames", id, {
		"name": name, "mode": State.meta["mode"], "difficulty": State.meta["difficulty"], "scenario": State.meta.get("scenario", ""),
		"saved_unix": int(Time.get_unix_time_from_system()), "game_time": State.date_str() + " " + State.time_str(),
		"clock": State.clock, "incidents_done": State.meta["stats"]["done"], "level": State.meta["level"], "version": State.VERSION,
	})
	return ""

static func load_game(id: String) -> String:
	var path := "%s/%s.sav" % [DIR, id]
	if not FileAccess.file_exists(path):
		return "Spielstand nicht gefunden."
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Spielstand konnte nicht geöffnet werden."
	var d = f.get_var(false)
	f.close()
	if typeof(d) != TYPE_DICTIONARY or not d.has("meta"):
		return "Spielstand ist beschädigt."
	if int(d.get("version", 0)) > State.VERSION:
		return "Spielstand stammt aus einer neueren Programmversion."
	World.ensure_built()
	State.from_dict(d)
	return ""

static func delete(id: String) -> void:
	DirAccess.remove_absolute("%s/%s.sav" % [DIR, id])
	LocalDB.remove("savegames", id)

static func list() -> Array:
	var out: Array = []
	var t: Dictionary = LocalDB.table("savegames")
	for id in t:
		if FileAccess.file_exists("%s/%s.sav" % [DIR, id]):
			var e: Dictionary = t[id].duplicate()
			e["id"] = id
			out.append(e)
	out.sort_custom(func(a, b): return a.get("saved_unix", 0) > b.get("saved_unix", 0))
	return out
