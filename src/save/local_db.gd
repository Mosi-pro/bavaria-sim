extends Node
## Kleine lokale Dokumentendatenbank (Tabellen als JSON-Dateien unter user://db).
## Bewusst ohne native Erweiterung (z. B. SQLite-GDExtension) umgesetzt, damit die
## EXE ohne zusätzliche DLLs auskommt. Tabellen: savegames, profile, servers, protokoll.

const DIR := "user://db"
var _tables: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)

func table(name: String) -> Dictionary:
	if not _tables.has(name):
		var path := "%s/%s.json" % [DIR, name]
		var data := {}
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				data = parsed
		_tables[name] = data
	return _tables[name]

func put(name: String, key: String, value) -> void:
	table(name)[key] = value
	flush(name)

func fetch(name: String, key: String, default = null):
	return table(name).get(key, default)

func remove(name: String, key: String) -> void:
	table(name).erase(key)
	flush(name)

func flush(name: String) -> void:
	var path := "%s/%s.json" % [DIR, name]
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Datenbank kann nicht geschrieben werden: %s" % path)
		return
	f.store_string(JSON.stringify(table(name), "  "))
	f.close()
	DirAccess.rename_absolute(tmp, path)
