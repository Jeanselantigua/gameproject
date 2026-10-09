@tool
extends Panel

## One gear slot on the fighter doll. The name is the slot.
## Gear screen fills in the piece; level-up leaves it empty until something is worn.

signal slot_pressed(slot_id: String)

@export var slot_name := "Helm":
	set(value):
		slot_name = value
		if is_node_ready():
			_paint()


func _ready() -> void:
	_paint()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		slot_pressed.emit(slot_name)
		accept_event()


func show_piece(caption: String, selected: bool, color: Color = Color(0.78, 0.7, 0.52)) -> void:
	$Label.text = caption
	$Label.add_theme_color_override("font_color", color)
	modulate = Color(1.2, 1.08, 0.75) if selected else Color.WHITE


func _paint() -> void:
	$Label.text = "%s\nEmpty" % slot_name
