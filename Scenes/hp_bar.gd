extends Control

## Always-on health bar for a fighter on the field.

@onready var fill: ColorRect = $Fill
@onready var amount: Label = $Amount


func _ready() -> void:
	size = custom_minimum_size
	set_hp(0, 1)


func set_hp(current: int, maximum: int) -> void:
	var safe_max := maxi(1, maximum)
	var ratio := clampf(float(clampi(current, 0, safe_max)) / float(safe_max), 0.0, 1.0)
	var inner := Vector2(maxi(size.x, custom_minimum_size.x) - 4.0, maxi(size.y, custom_minimum_size.y) - 4.0)
	fill.position = Vector2(2, 2)
	fill.size = Vector2(inner.x * ratio, inner.y)
	amount.text = "%d/%d" % [maxi(0, current), maximum]
	if ratio > 0.5:
		fill.color = Color(0.36, 0.72, 0.38)
	elif ratio > 0.25:
		fill.color = Color(0.78, 0.62, 0.28)
	else:
		fill.color = Color(0.72, 0.22, 0.2)
