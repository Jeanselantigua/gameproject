class_name LevelUp
extends Control

## Layout lives in level_up.tscn, armor_slot.tscn, and party_member.tscn.
## This script only fills in the party, the portrait, and the stat numbers.

signal closed

const MEMBER_SCENE := preload("res://Scenes/party_member.tscn")
const STAT_ROWS: Array[Dictionary] = [
	{"node": "Hp", "kind": "hp", "label": "HP"},
	{"node": "Attack", "kind": "attack", "label": "Attack"},
	{"node": "Defense", "kind": "defense", "label": "Defense"},
	{"node": "MagicAttack", "kind": "magic_attack", "label": "Magic Attack"},
	{"node": "MagicDefense", "kind": "magic_defense", "label": "Magic Defense"},
	{"node": "Speed", "kind": "speed", "label": "Speed"},
]

@onready var title: Label = $Panel/Column/Title
@onready var members: VBoxContainer = $Panel/Column/Body/PartyColumn/Members
@onready var portrait: TextureRect = $Panel/Column/Body/Doll/Portrait
@onready var name_label: Label = $Panel/Column/Body/Stats/NameLabel
@onready var points_label: Label = $Panel/Column/Body/Stats/PointsLabel
@onready var stat_list: VBoxContainer = $Panel/Column/Body/Stats/StatList

var _party: Array[Battler] = []
var _selected: Battler
var _group := ButtonGroup.new()


func open(party: Array[Battler], cleared_floor: int) -> void:
	_party = party
	_selected = _first_with_points()
	title.text = "Level Up  —  floor %d cleared" % cleared_floor
	visible = true
	_refresh_party()
	_refresh_sheet()


func _on_continue_pressed() -> void:
	visible = false
	closed.emit()


func _on_hp_pressed() -> void:
	_spend("hp")


func _on_attack_pressed() -> void:
	_spend("attack")


func _on_defense_pressed() -> void:
	_spend("defense")


func _on_magic_attack_pressed() -> void:
	_spend("magic_attack")


func _on_magic_defense_pressed() -> void:
	_spend("magic_defense")


func _on_speed_pressed() -> void:
	_spend("speed")


func _spend(kind: String) -> void:
	if _selected == null:
		return
	_selected.spend_stat_point(kind)
	_refresh_marks()
	_refresh_sheet()


func _first_with_points() -> Battler:
	for hero in _party:
		if hero.unspent_stat_points > 0:
			return hero
	return _party[0] if not _party.is_empty() else null


func _refresh_party() -> void:
	for child in members.get_children():
		members.remove_child(child)
		child.free()
	for hero in _party:
		var button := MEMBER_SCENE.instantiate() as Button
		button.text = _member_text(hero)
		button.button_group = _group
		button.set_pressed_no_signal(hero == _selected)
		button.toggled.connect(_on_member_toggled.bind(hero))
		members.add_child(button)


func _refresh_marks() -> void:
	var buttons := members.get_children()
	for i in mini(_party.size(), buttons.size()):
		buttons[i].text = _member_text(_party[i])


func _member_text(hero: Battler) -> String:
	if hero.unspent_stat_points > 0:
		return "%s  +%d" % [hero.display_name, hero.unspent_stat_points]
	return hero.display_name


func _on_member_toggled(pressed: bool, hero: Battler) -> void:
	if not pressed:
		return
	_selected = hero
	_refresh_sheet()


func _refresh_sheet() -> void:
	var hero := _selected
	if hero == null:
		name_label.text = ""
		points_label.text = ""
		portrait.texture = null
		return
	portrait.texture = _portrait(hero)
	portrait.modulate = hero.sprite_tint
	_paint_gear(hero)
	var xp_next := hero.xp_to_next()
	var xp_text := "XP %d" % hero.xp if xp_next <= 0 else "XP %d / %d" % [hero.xp, xp_next]
	name_label.text = "%s   Lv %d   %s" % [hero.display_name, hero.level, xp_text]
	points_label.text = "Stat points  %d" % hero.unspent_stat_points
	for row in STAT_ROWS:
		var box: HBoxContainer = stat_list.get_node(row["node"])
		var label: Label = box.get_node("Label")
		var button: Button = box.get_node("Plus")
		var kind: String = row["kind"]
		var specialty := hero.specialties.has(kind)
		label.text = "%s%s    %s" % [row["label"], " *" if specialty else "", _stat_text(hero, kind)]
		label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.86, 0.48) if specialty else Color(0.9, 0.86, 0.76)
		)
		button.text = "+%d" % hero.point_gain(kind)
		button.disabled = hero.unspent_stat_points <= 0


func _stat_text(hero: Battler, kind: String) -> String:
	match kind:
		"hp":
			return "%d / %d" % [hero.hp, hero.max_hp]
		"attack":
			return str(hero.attack)
		"defense":
			return str(hero.defense)
		"magic_attack":
			return str(hero.magic_attack)
		"magic_defense":
			return str(hero.magic_defense)
		_:
			return str(hero.speed)


func _paint_gear(hero: Battler) -> void:
	var doll := $Panel/Column/Body/Doll
	for slot_name in ["Helm", "Gloves", "Chest", "Boots", "Amulet", "Ring"]:
		var label: Label = doll.get_node("%s/Label" % slot_name)
		var piece := GearBook.piece_on(hero.display_name, slot_name.to_lower())
		if piece == null:
			label.text = "%s\nEmpty" % slot_name
		else:
			label.text = "%s\n+%d" % [slot_name, piece.level]


func _portrait(battler: Battler) -> Texture2D:
	var art_id := battler.sprite_id if battler.sprite_id != "" else "roeseph"
	for folder in ["res://Art/fighters/crisp/", "res://Art/fighters/", "res://Art/enemies/"]:
		var path := "%s%s.png" % [folder, art_id]
		if ResourceLoader.exists(path):
			return load(path)
	return load("res://Art/fighters/roeseph.png")
