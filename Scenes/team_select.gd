class_name TeamSelect
extends Control

## Pick 1 to 3 roster characters. Used once for your team and once for the AI team.

signal confirmed(ids: Array[String])
signal backed

const MAX_PICKS := 3

@onready var title_label: Label = $Margin/Column/Title
@onready var hint_label: Label = $Margin/Column/Hint
@onready var roster: GridContainer = $Margin/Column/Roster
@onready var continue_button: Button = $Margin/Column/Footer/ContinueButton
@onready var back_button: Button = $Margin/Column/Footer/BackButton

var picking_ai := false
var selected: Array[String] = []
var _ids: Array[String] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_ids = Roster.ids()
	var buttons := roster.get_children()
	for i in mini(buttons.size(), _ids.size()):
		var button := buttons[i] as Button
		button.pressed.connect(_on_fighter_pressed.bind(button, _ids[i]))
	continue_button.pressed.connect(_on_continue)
	back_button.pressed.connect(func() -> void: backed.emit())
	begin("Pick your team", "Choose 1 to 3 fighters. You control this team.", false)


func begin(heading: String, hint_text: String, ai_pick: bool) -> void:
	picking_ai = ai_pick
	selected.clear()
	title_label.text = heading
	hint_label.text = hint_text
	back_button.visible = ai_pick
	_refresh_buttons()
	continue_button.disabled = true


func _on_fighter_pressed(button: Button, id: String) -> void:
	if selected.has(id):
		selected.erase(id)
	elif selected.size() < MAX_PICKS:
		selected.append(id)
	else:
		return
	hint_label.text = "%d / %d selected" % [selected.size(), MAX_PICKS]
	continue_button.disabled = selected.is_empty()
	_refresh_buttons()
	button.grab_focus()


func _refresh_buttons() -> void:
	var buttons := roster.get_children()
	for i in mini(buttons.size(), _ids.size()):
		var button := buttons[i] as Button
		var id := _ids[i]
		var marked := selected.has(id)
		button.text = ("●  " + id) if marked else id
		button.disabled = selected.size() >= MAX_PICKS and not marked


func _on_continue() -> void:
	if selected.is_empty():
		return
	var picks: Array[String] = []
	picks.assign(selected)
	confirmed.emit(picks)
