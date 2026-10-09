@tool
extends Panel

## One gear slot on the fighter doll. The name is the slot.
## Gear screen fills in the piece; level-up leaves it empty until something is worn.

signal slot_pressed(slot_id: String)

const EMPTY_BORDER := Color(0.62, 0.48, 0.26)
const EMPTY_TEXT := Color(0.78, 0.7, 0.52)
const WORN_TEXT := Color(0.95, 0.92, 0.84)
const EMPTY_FILL := Color(0.08, 0.07, 0.06, 0.85)
const SELECTED_FILL := Color(0.26, 0.19, 0.09, 0.95)

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


## An empty slot keeps the scene's thin bronze border. A worn piece gets a thicker border in its rarity color.
func show_piece(caption: String, selected: bool, rarity_color: Variant = null) -> void:
	$Label.text = caption
	var frame := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if rarity_color == null:
		frame.border_color = EMPTY_BORDER
		frame.set_border_width_all(1)
		$Label.add_theme_color_override("font_color", EMPTY_TEXT)
	else:
		frame.border_color = rarity_color
		frame.set_border_width_all(2)
		$Label.add_theme_color_override("font_color", WORN_TEXT)
	frame.bg_color = SELECTED_FILL if selected else EMPTY_FILL
	add_theme_stylebox_override("panel", frame)


func _paint() -> void:
	$Label.text = "%s\nEmpty" % slot_name
