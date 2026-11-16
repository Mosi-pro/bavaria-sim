extends Control
## Startbildschirm der Beta-Version: Freischaltung mit Tester-Zugangscode.

const UI = preload("res://src/ui/kit.gd")
const Beta = preload("res://src/core/beta.gd")

signal unlocked

var _input: LineEdit
var _err: Label
var _tries := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.MAIN, UI.BORDER, 1, 0))
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v := UI.vbox([], 10)
	panel.add_child(UI.margin(v, 28))
	var stripe := ColorRect.new()
	stripe.color = UI.YELLOW
	stripe.custom_minimum_size = Vector2(0, 4)
	v.add_child(stripe)
	var title := UI.label("LEITSTELLE 112 – BETA", UI.TEXT, 26)
	title.add_theme_font_override("font", UI.bold())
	v.add_child(title)
	var info := UI.label("Diese Version ist nur für eingeladene Beta-Tester.\nBitte gib deinen persönlichen Zugangscode ein (Format LB-XXXX-XXXX-XXXX).\nDu bekommst ihn vom Entwicklerteam – bitte nicht weitergeben.", UI.TEXT2, 13)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 460
	v.add_child(info)
	_input = UI.line_edit("LB-XXXX-XXXX-XXXX")
	_input.custom_minimum_size.y = 34
	_input.text_submitted.connect(func(_t): _try())
	v.add_child(_input)
	_err = UI.label("", UI.RED, 12)
	v.add_child(_err)
	var ok := UI.accent(UI.button("Freischalten", _try), UI.GREEN)
	v.add_child(UI.hbox([UI.button("Beenden", func(): get_tree().quit()), UI.spacer(), ok]))
	_input.grab_focus.call_deferred()

func _try() -> void:
	if _tries >= 5:
		_err.text = "Zu viele Fehlversuche – bitte das Spiel neu starten."
		return
	var nr := Beta.unlock(_input.text)
	if nr < 0:
		_tries += 1
		_err.text = "Code ungültig. Bitte prüfen (Groß-/Kleinschreibung egal)."
		return
	unlocked.emit()
