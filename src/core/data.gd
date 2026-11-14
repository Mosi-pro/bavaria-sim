extends Node
## Lädt alle Spielparameter aus JSON-Konfigurationsdateien (res://data).
## Dateien können überschrieben werden, indem eine gleichnamige Datei unter
## user://config/ oder im Ordner "config" neben der EXE abgelegt wird.

var world: Dictionary = {}
var vehicle_types: Dictionary = {}
var organisations: Dictionary = {}
var stations: Array = []
var hospitals: Array = []
var incident_types: Dictionary = {}
var keywords: Dictionary = {}
var categories: Dictionary = {}
var call_scripts: Dictionary = {}
var fms: Dictionary = {}
var scenarios: Array = []
var modes: Dictionary = {}
var names: Dictionary = {}
var capabilities: Dictionary = {}
var qualifications: Dictionary = {}
var roles: Dictionary = {}
var network: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	world = load_json("world/bavaria.json")
	var v: Dictionary = load_json("vehicle_types.json")
	vehicle_types = v.get("types", {})
	capabilities = v.get("capabilities", {})
	qualifications = v.get("qualifications", {})
	organisations = load_json("organisations.json")
	var st: Dictionary = load_json("stations.json")
	stations = st.get("stations", [])
	hospitals = st.get("hospitals", [])
	var it: Dictionary = load_json("incident_types.json")
	incident_types = it.get("types", {})
	keywords = it.get("keywords", {})
	categories = it.get("categories", {})
	call_scripts = load_json("call_scripts.json")
	fms = load_json("fms_status.json")
	scenarios = load_json("scenarios.json").get("scenarios", [])
	modes = load_json("game_modes.json")
	names = load_json("names.json")
	roles = modes.get("roles", {})
	network = load_json("network.json")

func load_json(rel: String) -> Dictionary:
	var candidates := [
		OS.get_executable_path().get_base_dir().path_join("config").path_join(rel),
		"user://config/" + rel,
		"res://data/" + rel,
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			var txt := FileAccess.get_file_as_string(path)
			var parsed = JSON.parse_string(txt)
			if typeof(parsed) == TYPE_DICTIONARY:
				return parsed
			push_error("Konfigurationsdatei fehlerhaft: %s" % path)
	return {}

func fms_text(status: int) -> String:
	var e: Dictionary = fms.get("status", {}).get(str(status), {})
	return e.get("text", "Status %d" % status)

func fms_short(status: int) -> String:
	var e: Dictionary = fms.get("status", {}).get(str(status), {})
	return e.get("short", str(status))

func fms_color(status: int) -> Color:
	var e: Dictionary = fms.get("status", {}).get(str(status), {})
	return Color(e.get("color", "#A4ADB5"))

func org_of_type(type_id: String) -> String:
	return vehicle_types.get(type_id, {}).get("org", "sonst")

func org_color(org: String) -> Color:
	return Color(organisations.get(org, {}).get("color", "#A4ADB5"))

func org_name(org: String) -> String:
	return organisations.get(org, {}).get("name", org)

func keyword_list() -> Array:
	var ks := keywords.keys()
	ks.sort()
	return ks

## Stichwörter einer Kategorie (brand, thl, rd, abc, pol, sonst), sortiert.
func keywords_in(cat: String) -> Array:
	var out: Array = []
	for k in keyword_list():
		if keywords[k].get("cat", "") == cat:
			out.append(k)
	return out

func category_name(cat: String) -> String:
	return categories.get(cat, {}).get("name", cat)

func relay_url() -> String:
	var u := String(Settings.get_v("net", "relay_url"))
	if u.strip_edges() == "":
		u = String(network.get("relay_url", ""))
	return u.strip_edges()
