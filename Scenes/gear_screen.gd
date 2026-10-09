class_name GearScreen
extends Control

## Same layout as the level-up sheet: party, fighter, gear around them, stats on the right.
## There is no stat spending here. The numbers are the fighter plus whatever is equipped.

signal closed

const MEMBER_SCENE := preload("res://Scenes/party_member.tscn")
const ROW_SCENE := preload("res://Scenes/gear_row.tscn")
const STAT_ROWS: Array[Dictionary] = [
	{"node": "Hp", "kind": "hp", "label": "HP"},
	{"node": "Attack", "kind": "attack", "label": "Attack"},
	{"node": "Defense", "kind": "defense", "label": "Defense"},
	{"node": "MagicAttack", "kind": "magic_attack", "label": "Magic Attack"},
	{"node": "MagicDefense", "kind": "magic_defense", "label": "Magic Defense"},
	{"node": "Speed", "kind": "speed", "label": "Speed"},
	{"node": "CritRate", "kind": "crit_rate", "label": "Crit Rate"},
	{"node": "CritDamage", "kind": "crit_damage", "label": "Crit DMG"},
]

@onready var gold_label: Label = $Panel/Column/Body/Stats/GoldLabel
@onready var members: VBoxContainer = $Panel/Column/Body/PartyColumn/MemberScroll/Members
@onready var portrait: TextureRect = $Panel/Column/Body/Doll/Portrait
@onready var name_label: Label = $Panel/Column/Body/Stats/NameLabel
@onready var stat_list: VBoxContainer = $Panel/Column/Body/Stats/StatList
@onready var set_label: Label = $Panel/Column/Body/Stats/SetLabel
@onready var detail: Label = $Panel/Column/Body/Stats/Detail
@onready var bag_list: VBoxContainer = $Panel/Column/Body/Stats/BagScroll/BagList
@onready var equip_button: Button = $Panel/Column/Body/Stats/Actions/Equip
@onready var upgrade_button: Button = $Panel/Column/Body/Stats/Actions/Upgrade
@onready var sell_button: Button = $Panel/Column/Body/Stats/Actions/Sell

var _hero := ""
var _slot := "helm"
var _bag_uid := -1
var _live: Dictionary = {}
var _hero_group := ButtonGroup.new()
var _bag_group := ButtonGroup.new()
var _notice := ""


func open(live: Array = []) -> void:
	GearBook.load_book()
	_live.clear()
	for hero in live:
		var battler := hero as Battler
		if battler != null and battler.side == "player":
			_live[battler.display_name] = battler
	if _hero == "" or not Roster.ids().has(_hero):
		_hero = Roster.ids()[0]
	_bag_uid = -1
	detail.text = "Pick a slot, then a piece from the bag."
	visible = true
	_refresh()


func _on_close_pressed() -> void:
	visible = false
	closed.emit()


func _on_slot_pressed(slot_id: String) -> void:
	_slot = slot_id.to_lower()
	_bag_uid = -1
	_refresh()


func _on_equip_pressed() -> void:
	var bag_piece := GearBook.piece_by_uid(_bag_uid)
	if bag_piece != null:
		if GearBook.equip(_hero, bag_piece):
			_notice = "Equipped %s." % bag_piece.summary()
			_bag_uid = -1
			_touch_live()
		_refresh()
		return
	var worn := GearBook.piece_on(_hero, _slot)
	if worn != null:
		GearBook.unequip(_hero, _slot)
		_notice = "Unequipped %s." % worn.summary()
		_touch_live()
	_refresh()


func _on_upgrade_pressed() -> void:
	var gear := _focus_piece()
	if gear == null:
		return
	_notice = GearBook.try_upgrade(gear)
	_touch_live()
	_refresh()


func _on_sell_pressed() -> void:
	var gear := GearBook.piece_by_uid(_bag_uid)
	if gear == null:
		return
	_notice = GearBook.try_sell(gear)
	_bag_uid = -1
	_refresh()


func _focus_piece() -> Gear:
	var bag_piece := GearBook.piece_by_uid(_bag_uid)
	if bag_piece != null:
		return bag_piece
	return GearBook.piece_on(_hero, _slot)


func _touch_live() -> void:
	var battler: Battler = _live.get(_hero)
	if battler != null:
		GearBook.apply(battler)


func _refresh() -> void:
	gold_label.text = "Gold  %d" % GearBook.gold
	_refresh_party()
	_refresh_doll()
	_refresh_stats()
	_refresh_bag()
	_refresh_actions()


func _refresh_party() -> void:
	for child in members.get_children():
		child.free()
	for id in Roster.ids():
		var button := MEMBER_SCENE.instantiate() as Button
		button.text = id
		button.button_group = _hero_group
		button.set_pressed_no_signal(id == _hero)
		button.toggled.connect(_on_hero_toggled.bind(id))
		members.add_child(button)


func _on_hero_toggled(pressed: bool, id: String) -> void:
	if not pressed:
		return
	_hero = id
	_bag_uid = -1
	call_deferred("_refresh")


func _refresh_doll() -> void:
	var battler := _view_battler()
	portrait.texture = _portrait(battler)
	portrait.modulate = battler.sprite_tint
	var doll := $Panel/Column/Body/Doll
	for slot_name in ["Helm", "Gloves", "Chest", "Boots", "Amulet", "Ring"]:
		var slot_id := str(slot_name).to_lower()
		var slot: Node = doll.get_node(str(slot_name))
		var worn := GearBook.piece_on(_hero, slot_id)
		var caption := "%s\nEmpty" % slot_name
		var color := Color(0.78, 0.7, 0.52)
		if worn != null:
			caption = "%s\n+%d" % [GearBook.rarity_label(worn.rarity), worn.level]
			color = GearBook.rarity_color(worn.rarity)
		slot.show_piece(caption, slot_id == _slot, color)


func _refresh_stats() -> void:
	var battler := _view_battler()
	name_label.text = battler.display_name
	set_label.text = GearBook.set_summary(_hero)
	if _notice != "":
		detail.text = _notice
		_notice = ""
	else:
		var focus := _focus_piece()
		detail.text = "Pick a slot, then a piece from the bag." if focus == null else focus.describe()
	for row in STAT_ROWS:
		var label: Label = stat_list.get_node("%s/Label" % row["node"])
		var kind: String = row["kind"]
		var specialty := battler.specialties.has(kind)
		label.text = "%s%s    %s" % [row["label"], " *" if specialty else "", _stat_text(battler, kind)]
		label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.86, 0.48) if specialty else Color(0.9, 0.86, 0.76)
		)


func _view_battler() -> Battler:
	var live: Battler = _live.get(_hero)
	if live != null:
		return live
	var preview := Roster.spawn(_hero, false)
	preview.side = "player"
	GearBook.apply(preview)
	return preview


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
		"speed":
			return str(hero.speed)
		"crit_rate":
			return "%d%%" % hero.crit_rate
		"crit_damage":
			return "%d%%" % hero.crit_damage
	return "0"


func _refresh_bag() -> void:
	for child in bag_list.get_children():
		child.free()
	var rows := GearBook.bag(_slot)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No spare %s." % GearBook.slot_label(_slot).to_lower()
		empty.add_theme_color_override("font_color", Color(0.7, 0.64, 0.52))
		bag_list.add_child(empty)
	else:
		for gear in rows:
			var button := ROW_SCENE.instantiate() as Button
			button.text = gear.describe()
			button.button_group = _bag_group
			button.set_pressed_no_signal(gear.uid == _bag_uid)
			button.add_theme_color_override("font_color", GearBook.rarity_color(gear.rarity))
			button.toggled.connect(_on_bag_toggled.bind(gear.uid))
			bag_list.add_child(button)


func _on_bag_toggled(pressed: bool, uid: int) -> void:
	if not pressed:
		return
	_bag_uid = uid
	var gear := GearBook.piece_by_uid(uid)
	if gear != null:
		_slot = gear.slot
		_notice = gear.describe()
	call_deferred("_refresh")


func _refresh_actions() -> void:
	var bag_piece := GearBook.piece_by_uid(_bag_uid)
	var worn := GearBook.piece_on(_hero, _slot)
	if bag_piece != null:
		equip_button.text = "Equip"
		equip_button.disabled = false
	elif worn != null:
		equip_button.text = "Unequip"
		equip_button.disabled = false
	else:
		equip_button.text = "Equip"
		equip_button.disabled = true
	var focus := _focus_piece()
	var cost := 0 if focus == null else Gear.upgrade_cost(focus.level)
	upgrade_button.text = "Upgrade" if cost <= 0 else "Upgrade  %dg" % cost
	upgrade_button.disabled = focus == null or cost <= 0 or GearBook.gold < cost
	sell_button.text = "Sell" if bag_piece == null else "Sell  %dg" % bag_piece.sell_value()
	sell_button.disabled = bag_piece == null


func _portrait(battler: Battler) -> Texture2D:
	var art_id := battler.sprite_id if battler.sprite_id != "" else "roeseph"
	for folder in ["res://Art/fighters/crisp/", "res://Art/fighters/", "res://Art/enemies/"]:
		var path := "%s%s.png" % [folder, art_id]
		if ResourceLoader.exists(path):
			return load(path)
	return load("res://Art/fighters/roeseph.png")
