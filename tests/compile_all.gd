extends Node
func _ready():
	var bad = 0
	var stack = ["res://src", "res://tests"]
	while stack.size() > 0:
		var d = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd") and f != "compile_all.gd":
				var s = load(d + "/" + f)
				if s == null or not s.can_instantiate():
					bad += 1; print("FEHLER: ", d + "/" + f)
		for sub in DirAccess.get_directories_at(d): stack.append(d + "/" + sub)
	print("compile check done, bad=", bad)
	get_tree().quit(1 if bad > 0 else 0)
