extends Node
const MODE_NONE := 0
const MODE_HOST := 1
const MODE_CLIENT := 2
var mode := MODE_NONE
func shutdown() -> void:
	mode = MODE_NONE
func send_action(_a: Dictionary, _cb: Callable) -> void:
	pass
