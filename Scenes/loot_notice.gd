class_name LootNotice
extends Control

signal closed

@onready var gold_label: Label = $Panel/Column/Gold
@onready var list: VBoxContainer = $Panel/Column/List


func open(gold: int, pieces: Array) -> void:
	gold_label.text = "%d gold" % gold
	for child in list.get_children():
		child.free()
	for piece in pieces:
		var gear := piece as Gear
		if gear == null:
			continue
		var label := Label.new()
		label.text = gear.describe()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", GearBook.rarity_color(gear.rarity))
		label.add_theme_font_size_override("font_size", 16)
		list.add_child(label)
	visible = true


func _on_continue_pressed() -> void:
	visible = false
	closed.emit()
