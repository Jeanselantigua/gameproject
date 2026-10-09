class_name FighterCard
extends Control

## One fighter on the battle scene. The portrait is the monk sprite, tinted per character.

signal clicked(battler: Battler)

const PORTRAIT := preload("res://Art/MonkV0-Recovered.png")

@onready var portrait: TextureRect = $Column/Portrait
@onready var name_label: Label = $Column/NameLabel
@onready var hp_bar: ProgressBar = $Column/HpBar
@onready var hp_label: Label = $Column/HpLabel
@onready var affinity_label: Label = $Column/AffinityLabel
@onready var floater: Label = $Floater
@onready var ring: ColorRect = $Ring

var battler: Battler
var _home_modulate := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(210, 156)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.custom_minimum_size = Vector2(88, 56)
	$Panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.layout_mode = 1
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ignore_children(self)
	gui_input.connect(_on_gui_input)


func setup(who: Battler) -> void:
	battler = who
	portrait.texture = PORTRAIT
	portrait.flip_h = who.side != "player"
	_home_modulate = who.color
	portrait.modulate = who.color
	name_label.text = who.display_name
	affinity_label.text = Element.name_of(who.affinity)
	ring.color = Color(who.color.r, who.color.g, who.color.b, 0.0)
	refresh()


func refresh() -> void:
	if battler == null:
		return
	var ratio := float(battler.hp) / float(maxi(1, battler.max_hp))
	hp_bar.max_value = battler.max_hp
	hp_bar.value = battler.hp
	hp_bar.modulate = Color("e07070") if ratio < 0.35 else Color("7dcea0")
	var bits: PackedStringArray = PackedStringArray()
	bits.append("%d/%d" % [battler.hp, battler.max_hp])
	if battler.shield_hp > 0:
		bits.append("shield %d" % battler.shield_hp)
	if battler.stunned:
		bits.append("stun")
	if battler.wound_stacks > 0:
		bits.append("wound %d" % battler.wound_stacks)
	hp_label.text = " ".join(bits)
	if battler.is_fainted():
		modulate = Color(0.45, 0.45, 0.45, 0.7)
	else:
		modulate = Color.WHITE


func set_active(on: bool) -> void:
	ring.color = Color(1.0, 0.86, 0.4, 0.28) if on else Color(0, 0, 0, 0)


func set_targetable(on: bool) -> void:
	if battler != null and battler.is_fainted():
		modulate = Color(0.45, 0.45, 0.45, 0.7)
		return
	modulate = Color.WHITE if on else Color(0.55, 0.55, 0.55, 1)


func popup(text: String, color: Color) -> void:
	floater.text = text
	floater.modulate = Color(color.r, color.g, color.b, 1)
	floater.visible = true
	floater.position = Vector2(8, 18)
	var tw := create_tween()
	tw.tween_property(floater, "position:y", -6.0, 0.45)
	tw.parallel().tween_property(floater, "modulate:a", 0.0, 0.5)


func play_attack() -> void:
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.06, 0.94), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.1)
	await tw.finished


func play_hit(crit: bool) -> void:
	pivot_offset = size * 0.5
	modulate = Color("ffd56a") if crit else Color("ffb0b0")
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.94, 1.06), 0.06)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)
	tw.parallel().tween_property(self, "modulate", Color.WHITE, 0.18)
	await tw.finished


func play_faint() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.35, 0.35, 0.35, 0.65), 0.25)
	await tw.finished


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and battler != null:
			clicked.emit(battler)
			accept_event()


func _ignore_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control and child != self:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_children(child)
