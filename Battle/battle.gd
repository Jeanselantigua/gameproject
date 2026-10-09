extends Control

## Arena is a team fight. Dungeon is a forest march with the same battlefield.
## The left window is the scrolling log. The right edge lists turn order.
## The command menu is Do Combat, Item, Question, and Pass.

signal choice_made

const COMMANDS: Array[String] = ["Do Combat", "Item", "Question", "Pass"]
const QUEUE_COUNT := 8
const PLAYER_SPOTS: Array[Vector2] = [Vector2(420, 345), Vector2(180, 318), Vector2(290, 378)]
const ENEMY_SPOTS: Array[Vector2] = [Vector2(640, 345), Vector2(860, 318), Vector2(750, 378)]
## On-screen body size. Players stay at their original 64.
## Small enemies are 80, medium enemies are 128, and large enemies are 256.
const PLAYER_BODY := Vector2(64, 64)
const SMALL_BODY := Vector2(80, 80)
const MEDIUM_BODY := Vector2(128, 128)
const LARGE_BODY := Vector2(256, 256)
const SMALL_SPRITES: Array[String] = ["slime", "bat", "thornling"]
const LARGE_SPRITES: Array[String] = ["dragon", "hulk", "orc", "goblin_king", "warden"]
const _OLD_BODY := 96.0
## Where a summon's feet go, keyed by its summoner's slot: front, back, lower.
## Each spot is open ground that keeps the summon's name and HP bar clear of every fighter on the field.
const PLAYER_SUMMON_SPOTS: Array[Vector2] = [Vector2(350, 375), Vector2(200, 478), Vector2(240, 486)]
const ENEMY_SUMMON_SPOTS: Array[Vector2] = [Vector2(580, 470), Vector2(968, 478), Vector2(928, 486)]
const MONK_TEX := preload("res://Art/MonkV0-Recovered.png")
const ROAD_TEX := preload("res://Art/forest_road.jpg")
const HP_BAR_SCENE := preload("res://Scenes/hp_bar.tscn")

@onready var background: TextureRect = $Background
@onready var log_label: RichTextLabel = $HBoxContainer/Actions/Log
@onready var roster_grid: GridContainer = $HBoxContainer/Actions/Roster
@onready var menu: Menu = $Options/Options
@onready var turn_window: NinePatchRect = $TurnOrder
@onready var player_sprites: Array[TextureButton] = [
	$Players/BattlePlayer3,
	$Players/BattlePlayerUpper,
	$Players/BattlePlayerLower,
]
@onready var enemy_sprites: Array[TextureButton] = [
	$RightSide/BattleEnemy,
	$RightSide/BattleEnemy2,
	$RightSide/BattleEnemy3,
]

var rules: BattleRules
var sprite_owner: Dictionary = {}
var tag_of: Dictionary = {}
var mode := "pick_mode"
var run_kind := ""
var player_ids: Array[String] = []
var ai_ids: Array[String] = []
var dungeon_party: Party
var dungeon_heroes: Array[Battler] = []
var dungeon_room := 0
var actor: Battler
var pending_move: MoveData
var pending_target: Battler
var ready_moves: Array[MoveData] = []
var session := 0
var _lines: Array[String] = []
var _art_bounds: Dictionary = {}
var _portraits: Dictionary = {}
var _status_textures: Dictionary = {}
var _status_sig: Dictionary = {}
var status_rows: Dictionary = {}
var turn_list: VBoxContainer
var tip: PanelContainer
var tip_label: Label
var _frames: Dictionary = {}
var _bodies: Dictionary = {}
var title_root: Control
var title_tex: Texture2D
@onready var level_up_panel: LevelUp = $LevelUp
@onready var gear_screen: GearScreen = $GearScreen
@onready var loot_notice: LootNotice = $LootNotice
var hp_bars: Dictionary = {}


func _ready() -> void:
	$Players.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$RightSide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.mouse_filter = Control.MOUSE_FILTER_STOP
	log_label.scroll_active = true
	log_label.scroll_following = true
	log_label.add_theme_color_override("default_color", Color(0.92, 0.92, 0.86))
	log_label.add_theme_font_size_override("normal_font_size", 16)
	_setup_turn_window()
	_setup_status_icons()
	_setup_tip()
	menu.connect_to_buttons(self)
	GearBook.load_book()
	for sprite in _sprites():
		_ensure_hp_bar(sprite)
	for sprite in _sprites():
		sprite.pressed.connect(_on_sprite_pressed.bind(sprite))
		var tag := Label.new()
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", Color.WHITE)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		tag.add_theme_constant_override("outline_size", 5)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tag)
		tag_of[sprite] = tag
	_build_roster()
	_build_title_mark()
	title_tex = load("res://Art/title_field.jpg")
	_show_mode()


func _process(_delta: float) -> void:
	for sprite in tag_of:
		var tag: Label = tag_of[sprite]
		var button := sprite as TextureButton
		if button == null or not button.visible:
			tag.visible = false
			var hidden: HBoxContainer = status_rows.get(sprite)
			if hidden != null:
				hidden.visible = false
			var hidden_bar: Control = hp_bars.get(sprite)
			if hidden_bar != null:
				hidden_bar.visible = false
			continue
		tag.visible = true
		var battler: Battler = sprite_owner.get(button)
		tag.text = "" if battler == null else battler.display_name
		var shown_rect := _shown_rect(button)
		var center_x := shown_rect.get_center().x
		tag.size = Vector2(220, 20)
		tag.global_position = Vector2(center_x - tag.size.x * 0.5, shown_rect.end.y + 1)
		var bar: Control = hp_bars.get(button)
		if bar != null:
			bar.visible = battler != null
			if battler != null:
				bar.set_hp(battler.hp, battler.max_hp)
				bar.global_position = Vector2(center_x - bar.size.x * 0.5, shown_rect.end.y + 18)
		var row: HBoxContainer = status_rows.get(button)
		if row != null:
			var shown := button.visible and battler != null and row.get_child_count() > 0
			row.visible = shown
			if shown:
				var width := row.get_combined_minimum_size().x
				row.size = Vector2(maxf(width, 20.0), 20)
				row.z_index = 20
				row.global_position = Vector2(center_x - row.size.x * 0.5, shown_rect.position.y - 22)


func _build_roster() -> void:
	for id in Roster.ids():
		var button := Button.new()
		button.text = id
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(160, 28)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_on_roster_pressed.bind(id))
		roster_grid.add_child(button)


func _show_mode() -> void:
	session += 1
	choice_made.emit()
	run_kind = ""
	mode = "pick_mode"
	rules = null
	actor = null
	dungeon_party = null
	dungeon_heroes.clear()
	dungeon_room = 0
	player_ids.clear()
	ai_ids.clear()
	roster_grid.visible = false
	log_label.visible = true
	log_label.clear()
	log_label.scroll_following = true
	_lines.clear()
	if turn_window != null:
		turn_window.visible = false
	_clear_status_rows()
	_show_ids(player_sprites, player_ids, "player")
	_show_ids(enemy_sprites, ai_ids, "enemy")
	_add_log("Arena is a team fight with full kits.")
	_add_log("Dungeon is 100 floors. Enemies grow stronger each floor. Gear and gold stay with you.")
	_set_menu(["Arena", "Dungeon"])
	_show_title(true)


func _show_dungeon_pick() -> void:
	session += 1
	choice_made.emit()
	run_kind = "dungeon"
	mode = "pick_dungeon"
	rules = null
	actor = null
	dungeon_party = null
	dungeon_heroes.clear()
	dungeon_room = 0
	player_ids.clear()
	ai_ids.clear()
	roster_grid.visible = true
	log_label.visible = false
	if turn_window != null:
		turn_window.visible = false
	_clear_status_rows()
	_refresh_roster()
	_show_ids(player_sprites, player_ids, "player", false)
	_show_ids(enemy_sprites, ai_ids, "enemy")
	_set_menu(["Start", "Back"])
	_set_start_enabled()
	_show_title(false)


func _show_pick(picking_ai: bool) -> void:
	session += 1
	choice_made.emit()
	mode = "pick_ai" if picking_ai else "pick_player"
	rules = null
	actor = null
	roster_grid.visible = true
	log_label.visible = false
	if turn_window != null:
		turn_window.visible = false
	_clear_status_rows()
	if not picking_ai:
		ai_ids.clear()
	_refresh_roster()
	_show_ids(player_sprites, player_ids, "player")
	_show_ids(enemy_sprites, ai_ids, "enemy")
	_set_menu(["Start", "Back"])
	_set_start_enabled()
	_show_title(false)


func _on_roster_pressed(id: String) -> void:
	if mode != "pick_player" and mode != "pick_ai" and mode != "pick_dungeon":
		return
	var ids: Array[String] = ai_ids if mode == "pick_ai" else player_ids
	if ids.has(id):
		ids.erase(id)
	elif ids.size() < 3:
		ids.append(id)
	_refresh_roster()
	_show_ids(player_sprites, player_ids, "player", mode != "pick_dungeon")
	_show_ids(enemy_sprites, ai_ids, "enemy")
	_set_start_enabled()


func _refresh_roster() -> void:
	var ids := ai_ids if mode == "pick_ai" else player_ids
	var roster := Roster.ids()
	for i in roster_grid.get_child_count():
		var button := roster_grid.get_child(i) as Button
		var id := roster[i]
		button.text = ("● " + id) if ids.has(id) else id
		button.disabled = ids.size() >= 3 and not ids.has(id)


func _set_start_enabled() -> void:
	var ids := ai_ids if mode == "pick_ai" else player_ids
	var start := menu.get_buttons()[0] as Button
	start.disabled = ids.is_empty()


func _begin_fight() -> void:
	run_kind = "arena"
	var allies := Party.new("player")
	for id in player_ids:
		var hero := Roster.spawn(id, true)
		allies.add(hero)
		GearBook.apply(hero)
	var foes := Party.new("enemy")
	for id in ai_ids:
		foes.add(Roster.spawn(id, true))
	rules = BattleRules.new(allies, foes)
	_open_battle("The fight begins.")


func _begin_dungeon() -> void:
	dungeon_heroes.clear()
	dungeon_party = Party.new("player")
	for id in player_ids:
		var hero := Roster.spawn(id, false)
		dungeon_party.add(hero)
		GearBook.apply(hero)
		dungeon_heroes.append(hero)
	dungeon_room = 0
	_begin_dungeon_room()


func _begin_dungeon_room() -> void:
	var foes := Party.new("enemy")
	for enemy in Enemies.for_room(dungeon_room, dungeon_heroes.size()):
		foes.add(enemy)
	rules = BattleRules.new(dungeon_party, foes)
	_open_battle("Floor %d of %d. %s" % [dungeon_room + 1, Enemies.FLOORS, Enemies.room_blurb(dungeon_room)])
	background.texture = Enemies.background_for(dungeon_room)


func _open_battle(intro: String) -> void:
	session += 1
	choice_made.emit()
	var token := session
	roster_grid.visible = false
	log_label.visible = true
	log_label.clear()
	log_label.scroll_following = true
	_lines.clear()
	_sync_field()
	_paint()
	_show_title(false)
	_add_log(intro)
	_run(token)


func _build_title_mark() -> void:
	var regular: Font = load("res://Art/fonts/Cinzel-Regular.ttf")
	var bold: Font = load("res://Art/fonts/Cinzel-Bold.ttf")
	title_root = Control.new()
	title_root.name = "TitleMenu"
	title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.z_index = 5
	add_child(title_root)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 96.0
	column.offset_top = -168.0
	column.offset_right = 520.0
	column.offset_bottom = 168.0
	title_root.add_child(column)
	var title := Label.new()
	title.text = "Turnbased"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_paint_fantasy_label(title, bold, 60)
	column.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	var arena := _title_choice("Arena", regular)
	arena.pressed.connect(_on_title_arena)
	column.add_child(arena)
	var dungeon := _title_choice("Dungeon", regular)
	dungeon.pressed.connect(_on_title_dungeon)
	column.add_child(dungeon)
	var gear := _title_choice("Gear", regular)
	gear.pressed.connect(_on_title_gear)
	column.add_child(gear)


func _title_choice(label: String, font: Font) -> Button:
	var button := Button.new()
	button.text = label
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(280, 46)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var empty := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(style_name, empty)
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 32)
	button.add_theme_color_override("font_color", Color(0.95, 0.91, 0.8))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.58))
	button.add_theme_color_override("font_pressed_color", Color(0.86, 0.72, 0.36))
	button.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.05))
	button.add_theme_constant_override("outline_size", 8)
	return button


func _paint_fantasy_label(label: Label, font: Font, size: int) -> void:
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.84))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.05))
	label.add_theme_constant_override("outline_size", 10)


func _on_title_arena() -> void:
	if mode != "pick_mode":
		return
	run_kind = "arena"
	_show_pick(false)


func _on_title_dungeon() -> void:
	if mode != "pick_mode":
		return
	_show_dungeon_pick()


func _on_title_gear() -> void:
	if mode != "pick_mode":
		return
	_open_gear()


func _show_title(showing: bool) -> void:
	if showing and title_tex != null:
		background.texture = title_tex
	elif run_kind == "dungeon" and mode != "pick_dungeon":
		background.texture = Enemies.background_for(dungeon_room)
	else:
		background.texture = ROAD_TEX
	if title_root != null:
		title_root.visible = showing
	$HBoxContainer.visible = not showing
	$Options.visible = not showing


func _finish_dungeon_fight() -> void:
	var heroes_alive := false
	for hero in dungeon_heroes:
		if not hero.is_fainted():
			heroes_alive = true
	var won := heroes_alive and not rules.enemy.any_alive()
	_add_log(rules.winner_text())
	if not won:
		_add_log("The dungeon keeps the party.")
		_set_menu(["Leave"])
		return
	await _award_loot()
	_award_dungeon_xp()
	if _needs_level_up():
		_set_menu([])
		await _open_level_up(dungeon_room + 1)
	_settle_dungeon_party()
	dungeon_room += 1
	if dungeon_room >= Enemies.FLOORS:
		_add_log("Floor 100 falls. The dungeon is cleared.")
		_set_menu(["Leave"])
		return
	_add_log(Enemies.room_blurb(dungeon_room))
	_set_menu(["Next floor", "Leave"])


func _needs_level_up() -> bool:
	for hero in dungeon_heroes:
		if hero.unspent_stat_points > 0:
			return true
	return false


func _open_level_up(floor_cleared: int) -> void:
	$Options.visible = false
	level_up_panel.open(dungeon_heroes, floor_cleared)
	await level_up_panel.closed
	if mode == "result":
		$Options.visible = true


func _award_loot() -> void:
	var loot := GearBook.roll_wave(rules.enemy.members, Enemies.scale_for(dungeon_room, dungeon_heroes.size()))
	var gained := int(loot.gold)
	if gained > 0:
		_add_log("The party finds %d gold." % gained)
	var pieces: Array = loot.pieces
	for piece in pieces:
		var gear := piece as Gear
		if gear != null:
			_add_log("Dropped %s." % gear.summary())
	if pieces.is_empty():
		return
	$Options.visible = false
	loot_notice.open(gained, pieces)
	await loot_notice.closed
	if mode == "result":
		$Options.visible = true


func _open_gear() -> void:
	var live: Array = []
	if rules != null and rules.player != null:
		live.assign(rules.player.members)
	$Options.visible = false
	if title_root != null and mode == "pick_mode":
		title_root.visible = false
	gear_screen.open(live)
	await gear_screen.closed
	if mode == "pick_mode":
		_show_title(true)
		return
	if mode == "command" or mode == "result":
		$Options.visible = true
		_paint()


func _award_dungeon_xp() -> void:
	var bounty := 0
	for foe in rules.enemy.members:
		if foe.is_fainted():
			bounty += foe.bounty
	if bounty <= 0:
		return
	_add_log("The party gains %d XP." % bounty)
	for hero in dungeon_heroes:
		if hero.is_fainted():
			continue
		_add_lines(hero.grant_xp(bounty))


func _settle_dungeon_party() -> void:
	for member in dungeon_party.members:
		if not dungeon_heroes.has(member):
			member.hp = 0
	var kept: Array[Battler] = []
	kept.assign(dungeon_heroes)
	dungeon_party.members = kept
	_add_log("The party catches its breath.")
	for hero in dungeon_heroes:
		hero.clear_battle_state()
		if hero.is_fainted():
			_add_log("%s is down.  Lv %d" % [hero.display_name, hero.level])
			continue
		var breath := maxi(1, int(float(hero.max_hp) * 0.2))
		hero.hp = mini(hero.max_hp, hero.hp + breath)
		_add_log("%s  %d/%d  Lv %d" % [hero.display_name, hero.hp, hero.max_hp, hero.level])


func _run(token: int) -> void:
	while rules != null and rules.ongoing() and token == session:
		actor = rules.next_actor()
		if actor == null:
			break
		_set_menu([])
		_paint()
		var ready := rules.begin_turn(actor)
		if not rules.turn_notes.is_empty():
			_add_lines(rules.turn_notes)
			_sync_field()
		if actor.is_fainted() or not rules.ongoing():
			if rules.ongoing():
				rules.advance(actor)
			continue
		if rules.skips_own_action(actor):
			_add_lines(rules.note_skipped_action(actor))
			var queued: Dictionary = rules.take_queued_action(actor)
			if not queued.is_empty():
				var blocked := rules.skip_if_stunned(actor)
				if not blocked.is_empty():
					_add_lines(blocked)
				else:
					await _perform(actor, queued.move, queued.target)
			_paint()
			await get_tree().create_timer(0.45).timeout
		else:
			var skipped := rules.skip_if_stunned(actor)
			if not skipped.is_empty():
				_add_lines(skipped)
				_paint()
				await get_tree().create_timer(0.45).timeout
			elif ready.is_empty():
				_add_log("%s has no available actions." % actor.display_name)
			elif actor.side == "player":
				ready_moves = ready
				pending_move = null
				pending_target = null
				mode = "command"
				_set_menu(COMMANDS)
				_add_log("%s's turn." % actor.display_name)
				await choice_made
				if token != session:
					return
				if pending_move != null:
					await _perform(actor, pending_move, pending_target)
			else:
				mode = "busy"
				_set_menu([])
				_add_log("%s is acting..." % actor.display_name)
				await get_tree().create_timer(0.35).timeout
				var ai: Dictionary = rules.ai_choice(actor, ready)
				if ai.is_empty():
					_add_log("%s has nothing to do." % actor.display_name)
				else:
					await _perform(actor, ai.move, ai.target)
		if token != session:
			return
		if rules == null or not rules.ongoing():
			break
		var field_notes := rules.notify_field()
		if not field_notes.is_empty():
			_add_lines(field_notes)
			_sync_field()
		rules.advance(actor)
		_paint()
	if token != session or rules == null:
		return
	mode = "result"
	if run_kind == "dungeon":
		await _finish_dungeon_fight()
	else:
		_set_menu(["Fight again", "Change teams"])
		_add_log(rules.winner_text())
	_paint()


func _perform(battler: Battler, move: MoveData, target: Battler) -> void:
	mode = "busy"
	var result := rules.resolve(battler, move, target)
	_add_lines(result.lines)
	_sync_field()
	for event in result.events:
		var sprite := _sprite_for(event.target)
		if sprite == null:
			continue
		if event.kind == "miss":
			_float(sprite, "Miss", Color.WHITE)
		elif event.kind == "heal":
			_float(sprite, "+%d" % int(event.damage), Color(0.65, 1, 0.75))
		elif event.kind == "shield":
			_float(sprite, "Shield", Color(0.7, 0.9, 1))
		else:
			sprite.modulate = Color(1, 0.45, 0.4)
			var amount := int(event.damage)
			_float(sprite, str(amount), Color(1, 0.92, 0.45) if bool(event.crit) else Color.WHITE)
		_paint_tags()
		await get_tree().create_timer(0.16).timeout
	_paint()


func _on_Options_focused(_button: BaseButton) -> void:
	pass


func _on_Options_pressed(button: BaseButton) -> void:
	var label: String = button.text
	if mode == "pick_mode":
		if label == "Arena":
			run_kind = "arena"
			_show_pick(false)
		elif label == "Dungeon":
			_show_dungeon_pick()
		return
	if mode == "pick_player" or mode == "pick_ai" or mode == "pick_dungeon":
		if label == "Start":
			if mode == "pick_player" and not player_ids.is_empty():
				_show_pick(true)
			elif mode == "pick_ai" and not ai_ids.is_empty():
				_begin_fight()
			elif mode == "pick_dungeon" and not player_ids.is_empty():
				_begin_dungeon()
		elif label == "Back":
			if mode == "pick_ai":
				_show_pick(false)
			else:
				_show_mode()
		return
	if mode == "result":
		if run_kind == "dungeon":
			if label == "Next floor":
				_begin_dungeon_room()
			elif label == "Leave":
				_show_mode()
			return
		if label == "Fight again":
			_begin_fight()
		elif label == "Change teams":
			_show_pick(false)
		return
	if mode == "command":
		if label == "Do Combat":
			_open_moves()
		elif label == "Item":
			_open_gear()
		elif label == "Question":
			_add_log(_question_text(actor))
		elif label == "Pass":
			pending_move = null
			mode = "busy"
			_add_log("%s passes." % actor.display_name)
			choice_made.emit()
		return
	if mode == "moves":
		if label == "Back":
			mode = "command"
			_set_menu(COMMANDS)
			return
		for move in ready_moves:
			if label.begins_with(move.move_name):
				_choose_move(move)
				return
	if mode == "target" and label == "Back":
		_open_moves()


func _open_moves() -> void:
	mode = "moves"
	var labels: Array[String] = []
	for move in ready_moves:
		var text := move.move_name
		if move.power > 0:
			text += "  %d" % move.power
		labels.append(text)
	if labels.size() < 4:
		labels.append("Back")
	_set_menu(labels)
	_add_log("Choose a move.")


func _choose_move(move: MoveData) -> void:
	pending_move = move
	if move.targets == "self" or move.hits_all:
		pending_target = actor if move.targets == "self" else _first_foe()
		if pending_target == null:
			return
		mode = "busy"
		choice_made.emit()
		return
	mode = "target"
	_set_menu(["Back"])
	var who := "an ally" if move.targets == "ally" else "an enemy"
	_add_log("Choose %s for %s." % [who, move.move_name])
	_paint()


func _on_sprite_pressed(sprite: TextureButton) -> void:
	var battler: Battler = sprite_owner.get(sprite)
	if battler == null:
		return
	if mode == "moves" and battler == actor:
		mode = "command"
		_set_menu(COMMANDS)
		_paint()
		return
	if mode != "target" or pending_move == null:
		return
	if battler == actor and pending_move.targets != "ally":
		_open_moves()
		return
	if not _is_legal(battler):
		return
	pending_target = battler
	mode = "busy"
	choice_made.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if mode == "target" or mode == "moves":
			mode = "command"
			_set_menu(COMMANDS)
			_paint()


func _is_legal(battler: Battler) -> bool:
	if pending_move == null or battler.is_fainted():
		return false
	if pending_move.targets == "ally":
		return battler.side == actor.side
	if battler.side == actor.side:
		return false
	var forced := rules.aggro_target(actor)
	if forced != null and not pending_move.hits_all:
		return battler == forced
	return true


func _first_foe() -> Battler:
	var forced := rules.aggro_target(actor)
	if forced != null:
		return forced
	var foes := rules.foes_of(actor)
	return null if foes.is_empty() else foes[0]


func _show_ids(sprites: Array[TextureButton], ids: Array[String], side: String, for_pvp: bool = true) -> void:
	for i in sprites.size():
		var sprite := sprites[i]
		if i < ids.size():
			var battler := Roster.spawn(ids[i], for_pvp)
			battler.side = side
			sprite.visible = true
			sprite_owner[sprite] = battler
		else:
			sprite.visible = false
			sprite_owner.erase(sprite)
	_paint()


func _sync_field() -> void:
	if rules == null:
		return
	var allies := _present_members(rules.player)
	var foes := _present_members(rules.enemy)
	_ensure_slot(player_sprites, allies.size(), $Players, PLAYER_SPOTS[0])
	_ensure_slot(enemy_sprites, foes.size(), $RightSide, ENEMY_SPOTS[0])
	_bind(player_sprites, rules.player)
	_bind(enemy_sprites, rules.enemy)


func _ensure_slot(slots: Array[TextureButton], count: int, parent: Node, extra_at: Vector2) -> void:
	while slots.size() < count:
		var button := TextureButton.new()
		button.position = extra_at + Vector2(0, 90 * (slots.size() - 3))
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		parent.add_child(button)
		button.pressed.connect(_on_sprite_pressed.bind(button))
		var tag := Label.new()
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", Color.WHITE)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		tag.add_theme_constant_override("outline_size", 5)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tag)
		tag_of[button] = tag
		_ensure_hp_bar(button)
		slots.append(button)


func _body_size(battler: Battler) -> Vector2:
	if battler.side != "enemy" or battler.summoner != null:
		return PLAYER_BODY
	if SMALL_SPRITES.has(battler.sprite_id):
		return SMALL_BODY
	if LARGE_SPRITES.has(battler.sprite_id):
		return LARGE_BODY
	return MEDIUM_BODY


func _apply_art(button: TextureButton, battler: Battler) -> void:
	var body := _body_size(battler)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.ignore_texture_size = true
	button.custom_minimum_size = body
	button.size = body
	button.scale = Vector2.ONE
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.flip_h = battler.side == "enemy"
	button.texture_normal = _frame_for(battler)
	_attach_body(button, battler, body)
	_stand_on_road(button)


## Fighters with a scene in Scenes/characters play their idle there.
## The button keeps its still texture for sizing and clicks but stops drawing it.
func _attach_body(button: TextureButton, battler: Battler, body: Vector2) -> void:
	var art_id := _art_id(battler)
	var current := button.get_node_or_null("Body") as AnimatedSprite2D
	if current != null and str(current.get_meta("art_id", "")) != art_id:
		button.remove_child(current)
		current.queue_free()
		current = null
	var scene := _body_scene(art_id)
	button.self_modulate.a = 1.0 if scene == null else 0.0
	if scene == null:
		return
	if current == null:
		current = scene.instantiate() as AnimatedSprite2D
		current.name = "Body"
		current.set_meta("art_id", art_id)
		button.add_child(current)
		current.frame = randi() % current.sprite_frames.get_frame_count(current.animation)
	var art_size := current.sprite_frames.get_frame_texture(current.animation, 0).get_size()
	current.position = body * 0.5
	current.scale = body / art_size
	current.flip_h = button.flip_h


func _body_scene(art_id: String) -> PackedScene:
	if not _bodies.has(art_id):
		var path := "res://Scenes/characters/%s.tscn" % art_id
		_bodies[art_id] = load(path) if ResourceLoader.exists(path) else null
	return _bodies[art_id]


func _art_id(battler: Battler) -> String:
	return battler.sprite_id if battler.sprite_id != "" else "roeseph"


func _frame_for(battler: Battler) -> Texture2D:
	var art_id := _art_id(battler)
	if _frames.has(art_id):
		return _frames[art_id]
	var loaded := _load_art(art_id)
	if loaded == null:
		loaded = MONK_TEX
	_frames[art_id] = loaded
	return loaded


func _load_art(art_id: String) -> Texture2D:
	for folder in ["res://Art/fighters/crisp/", "res://Art/enemies/", "res://Art/fighters/"]:
		var path := "%s%s.png" % [folder, art_id]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _present_members(party: Party) -> Array[Battler]:
	var undead: Battler = null
	for member in party.members:
		if member.display_name == "Undead Sion":
			undead = member
	var shown: Array[Battler] = []
	for member in party.members:
		if member.display_name == "Undead Sion":
			continue
		if undead != null and member.display_name == "Sion" and member.is_fainted():
			shown.append(undead)
			continue
		shown.append(member)
	return shown


func _stand_on_road(button: TextureButton) -> void:
	var index := player_sprites.find(button)
	var spots: Array[Vector2] = PLAYER_SPOTS
	if index < 0:
		index = enemy_sprites.find(button)
		spots = ENEMY_SPOTS
	if index < 0:
		return
	var spot := spots[mini(index, spots.size() - 1)]
	if index >= spots.size():
		spot += Vector2(36 * (index - spots.size() + 1), 0)
	button.layout_mode = 0
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var foot_y := spot.y + _OLD_BODY
	var center_x := spot.x + _OLD_BODY * 0.5
	var beside := _summon_spot(button)
	if beside != Vector2.INF:
		center_x = beside.x
		foot_y = beside.y
	button.position = Vector2(center_x - button.size.x * 0.5, foot_y - button.size.y)


## Foot position next to the summoner, or Vector2.INF when the button does not hold a summon on the field.
func _summon_spot(button: TextureButton) -> Vector2:
	var battler: Battler = sprite_owner.get(button)
	if battler == null or battler.summoner == null:
		return Vector2.INF
	var host := _sprite_for(battler.summoner)
	if host == null or host == button or not host.visible:
		return Vector2.INF
	var enemy_side := battler.side == "enemy"
	var slot := (enemy_sprites if enemy_side else player_sprites).find(host)
	if slot < 0 or slot > 2:
		return Vector2.INF
	return ENEMY_SUMMON_SPOTS[slot] if enemy_side else PLAYER_SUMMON_SPOTS[slot]


func _bind(sprites: Array[TextureButton], party: Party) -> void:
	var members := _present_members(party)
	for i in sprites.size():
		var sprite := sprites[i]
		if i < members.size():
			sprite.visible = true
			sprite_owner[sprite] = members[i]
		else:
			sprite.visible = false
			sprite_owner.erase(sprite)


func _paint() -> void:
	for sprite in _sprites():
		var battler: Battler = sprite_owner.get(sprite)
		if battler == null:
			continue
		_apply_art(sprite, battler)
		var tint := battler.sprite_tint
		if battler.display_name == "Undead Sion" and not battler.is_fainted():
			sprite.modulate = tint * Color(0.62, 0.95, 0.68)
		elif battler.is_fainted():
			sprite.modulate = tint * Color(0.35, 0.35, 0.35)
		elif mode == "target" and _is_legal(battler):
			sprite.modulate = tint * Color(1.25, 1.25, 1.1)
		elif battler == actor:
			sprite.modulate = tint * Color(1.12, 1.12, 1.05)
		else:
			sprite.modulate = tint
	_paint_tags()
	_sync_statuses()
	_refresh_turn_order()


func _paint_tags() -> void:
	for sprite in tag_of:
		var battler: Battler = sprite_owner.get(sprite)
		var tag: Label = tag_of[sprite]
		if battler == null:
			tag.text = ""
		else:
			tag.text = "%s  %d/%d" % [battler.display_name, battler.hp, battler.max_hp]


func _shown_rect(button: TextureButton) -> Rect2:
	return Rect2(button.global_position, button.size * button.scale)


func _ensure_hp_bar(button: TextureButton) -> void:
	if hp_bars.has(button):
		return
	var bar := HP_BAR_SCENE.instantiate() as Control
	bar.z_index = 12
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	hp_bars[button] = bar


func _art_rect(button: TextureButton) -> Rect2:
	var local := Rect2(Vector2.ZERO, button.size)
	var texture := button.texture_normal
	if texture != null:
		local = _opaque_rect(texture)
	var origin := button.get_global_transform() * local.position
	var extent := button.get_global_transform() * (local.position + local.size)
	return Rect2(origin, extent - origin)


func _opaque_rect(texture: Texture2D) -> Rect2:
	var key := texture.resource_path
	if _art_bounds.has(key):
		return _art_bounds[key]
	var bounds := Rect2(Vector2.ZERO, texture.get_size())
	var image := texture.get_image()
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		if used.size.x > 1.0 and used.size.y > 1.0:
			bounds = used
	_art_bounds[key] = bounds
	return bounds


func _sprite_for(battler: Battler) -> TextureButton:
	for sprite in sprite_owner:
		if sprite_owner[sprite] == battler:
			return sprite
	if battler != null and battler.display_name == "Sion":
		for sprite in sprite_owner:
			var shown: Battler = sprite_owner[sprite]
			if shown != null and shown.display_name == "Undead Sion":
				return sprite
	return null


func _sprites() -> Array[TextureButton]:
	var all: Array[TextureButton] = []
	all.append_array(player_sprites)
	all.append_array(enemy_sprites)
	return all


func _question_text(battler: Battler) -> String:
	if battler == null:
		return ""
	var text := "%s   HP %d/%d   Atk %d   Def %d   Spd %d" % [
		battler.display_name, battler.hp, battler.max_hp, battler.attack, battler.defense, battler.speed
	]
	if battler.shield_hp > 0:
		text += "   Shield %d" % battler.shield_hp
	if battler.stunned:
		text += "   Stunned"
	if battler.wound_stacks > 0:
		text += "   Wound %d" % battler.wound_stacks
	return text


func _set_menu(labels: Array) -> void:
	var buttons := menu.get_buttons()
	var focus := -1
	for i in buttons.size():
		var button := buttons[i] as Button
		button.clip_text = true
		if i < labels.size() and str(labels[i]) != "":
			button.visible = true
			button.disabled = false
			button.text = str(labels[i])
			if focus < 0:
				focus = i
		else:
			button.visible = false
	if focus >= 0:
		menu.button_focus(focus)


func _add_log(line: String) -> void:
	var rows: Array[String] = [line]
	_add_lines(rows)


func _add_lines(lines: Array) -> void:
	for line in lines:
		var text := str(line)
		_lines.append(text)
		if log_label.get_total_character_count() == 0:
			log_label.append_text(text)
		else:
			log_label.append_text("\n" + text)


func _float(sprite: TextureButton, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.global_position = sprite.global_position + Vector2(8, 0)
	var tw := create_tween()
	tw.tween_property(label, "position:y", label.position.y - 36, 0.45)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tw.finished.connect(label.queue_free)


func _setup_turn_window() -> void:
	var margin := MarginContainer.new()
	margin.layout_mode = 1
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 10
	margin.offset_top = 8
	margin.offset_right = -8
	margin.offset_bottom = -8
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_window.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Turn order"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	turn_list = VBoxContainer.new()
	turn_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_list.add_theme_constant_override("separation", 2)
	scroll.add_child(turn_list)


func _setup_tip() -> void:
	tip = PanelContainer.new()
	tip.visible = false
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.z_index = 40
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.02, 0.94)
	style.border_color = Color(0.82, 0.82, 0.78)
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	tip.add_theme_stylebox_override("panel", style)
	tip_label = Label.new()
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(210, 0)
	tip_label.add_theme_font_size_override("font_size", 13)
	tip_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	tip.add_child(tip_label)
	add_child(tip)


func _setup_status_icons() -> void:
	_status_textures = {
		"stun": _glyph([
			"      +##+      ",
			"     +####+     ",
			"    +# ++ #+    ",
			"   +#  ##  #+   ",
			"   +#  ##  #+   ",
			"    +# ++ #+    ",
			"     +####+     ",
			"      +##+      ",
		], Color(1, 0.9, 0.35)),
		"wound": _glyph([
			"++            ++",
			" ++          ++ ",
			"  ++   ##   ++  ",
			"   ++ #### ++   ",
			"    +######+    ",
			"     ######     ",
			"    +######+    ",
			"   ++ #### ++   ",
			"  ++   ##   ++  ",
			" ++          ++ ",
		], Color(0.9, 0.18, 0.22)),
		"shield": _glyph([
			"    +######+    ",
			"   +########+   ",
			"  +##########+  ",
			"  +##########+  ",
			"  +##########+  ",
			"   +########+   ",
			"    +######+    ",
			"     +####+     ",
			"      +##+      ",
		], Color(0.45, 0.75, 1)),
		"stealth": _glyph([
			"   ++      ++   ",
			"  +##+    +##+  ",
			" +#  #+  +#  #+ ",
			"+#    +#+#    #+",
			"+#     ##     #+",
			" +#    ##    #+ ",
			"  +#  ####  #+  ",
			"   ++######++   ",
		], Color(0.62, 0.42, 0.9)),
		"momentum": _glyph([
			"      ####      ",
			"     ######     ",
			"    ## ++ ##    ",
			"   ##  ++  ##   ",
			"      ####      ",
			"     ######     ",
			"    ## ++ ##    ",
			"   ##  ++  ##   ",
		], Color(0.4, 0.9, 0.48)),
		"taunt": _glyph([
			"      +##+      ",
			"      +##+      ",
			"      +##+      ",
			"      +##+      ",
			"      +##+      ",
			"                ",
			"      +##+      ",
			"      +##+      ",
		], Color(1, 0.55, 0.2)),
		"guard": _glyph([
			"    +######+    ",
			"   +## ++ ##+   ",
			"  +### ++ ###+  ",
			"  +### ++ ###+  ",
			"  +##########+  ",
			"   +########+   ",
			"    +######+    ",
			"     +####+     ",
		], Color(0.9, 0.9, 0.95)),
		"frenzy": _glyph([
			"++      ++    ++",
			" ++    ++    ++ ",
			"  ++  ++    ++  ",
			"   ++++    ++   ",
			"    ++    ++    ",
			"   ++    ++++   ",
			"  ++    ++  ++  ",
			" ++    ++    ++ ",
		], Color(0.95, 0.28, 0.18)),
		"blessing": _glyph([
			"      +##+      ",
			"      +##+      ",
			"  ++++####++++  ",
			"  +###########+ ",
			"  ++++####++++  ",
			"      +##+      ",
			"      +##+      ",
		], Color(1, 0.88, 0.45)),
		"rage": _glyph([
			"      +##+      ",
			"     +####+     ",
			"    +##++##+    ",
			"   +###++###+   ",
			"   +########+   ",
			"    +######+    ",
			"     +####+     ",
			"      +##+      ",
		], Color(0.85, 0.12, 0.16)),
		"art": _glyph([
			"   +########+   ",
			"  +##  ##  ##+  ",
			"  +##  ##  ##+  ",
			"  +##  ##  ##+  ",
			"  +##########+  ",
			"  +##  ##  ##+  ",
			"   +########+   ",
		], Color(0.4, 0.85, 0.92)),
		"paralysis": _glyph([
			"   ++      ++   ",
			"  +##+    +##+  ",
			"   ++ #### ++   ",
			"     +####+     ",
			"     +####+     ",
			"   ++ #### ++   ",
			"  +##+    +##+  ",
			"   ++      ++   ",
		], Color(0.95, 0.85, 0.25)),
		"bleed": _glyph([
			"      +##+      ",
			"     +####+     ",
			"     +####+     ",
			"      +##+      ",
			"     +####+     ",
			"    +##++##+    ",
			"   +##    ##+   ",
			"   +#      #+   ",
		], Color(0.75, 0.05, 0.08)),
		"poison": _glyph([
			"     +####+     ",
			"    +##++##+    ",
			"   +## ++ ##+   ",
			"   +## ++ ##+   ",
			"    +##++##+    ",
			"     +####+     ",
			"      +##+      ",
			"       ++       ",
		], Color(0.45, 0.75, 0.2)),
		"curse": _glyph([
			"    +######+    ",
			"   +## ++ ##+   ",
			"   +#  ++  #+   ",
			"   +#  ++  #+   ",
			"   +## ++ ##+   ",
			"    +######+    ",
			"     +#  #+     ",
			"     +#  #+     ",
		], Color(0.55, 0.25, 0.7)),
		"siphon": _glyph([
			"     +####+     ",
			"    +##  ##+    ",
			"   +##    ##+   ",
			"  +##  ++  ##+  ",
			"  +##  ++  ##+  ",
			"   +##    ##+   ",
			"    +##  ##+    ",
			"     +####+     ",
		], Color(0.35, 0.85, 0.55)),
		"burn": _glyph([
			"      +##+      ",
			"     +####+     ",
			"    +##++##+    ",
			"   +###++###+   ",
			"   +########+   ",
			"    +##++##+    ",
			"     +####+     ",
			"      +##+      ",
		], Color(0.95, 0.42, 0.12)),
		"slow": _glyph([
			"    +######+    ",
			"   +##    ##+   ",
			"   +#  ##  #+   ",
			"   +#  ##  #+   ",
			"   +#      #+   ",
			"   +##    ##+   ",
			"    +######+    ",
		], Color(0.55, 0.7, 0.85)),
		"blessed": _glyph([
			"      +##+      ",
			"     +####+     ",
			"  ++++####++++  ",
			"  +###########+ ",
			"  ++++####++++  ",
			"     +####+     ",
			"      +##+      ",
		], Color(1, 0.95, 0.55)),
	}


func _glyph(rows: Array, color: Color) -> Texture2D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in mini(rows.size(), 16):
		var row := str(rows[y])
		for x in mini(row.length(), 16):
			var mark := row[x]
			if mark == "#":
				image.set_pixel(x, y, color)
			elif mark == "+":
				image.set_pixel(x, y, Color(0, 0, 0, 0.85))
	return ImageTexture.create_from_image(image)


func _refresh_turn_order() -> void:
	if turn_list == null:
		return
	for child in turn_list.get_children():
		child.free()
	if rules == null or mode == "result":
		turn_window.visible = false
		return
	turn_window.visible = true
	var upcoming: Array = rules.preview(QUEUE_COUNT)
	for index in upcoming.size():
		var battler: Battler = upcoming[index].battler
		turn_list.add_child(_turn_row(battler, index == 0))


func _turn_row(battler: Battler, acting: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _portrait(_frame_for(battler))
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.modulate = Color.WHITE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var name_label := Label.new()
	name_label.text = battler.display_name
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	var tint := Color(1, 0.86, 0.45) if acting else Color(0.92, 0.92, 0.88)
	name_label.add_theme_color_override("font_color", tint)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	return row


func _portrait(texture: Texture2D) -> Texture2D:
	if _portraits.has(texture):
		return _portraits[texture]
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = _opaque_rect(texture)
	_portraits[texture] = atlas
	return atlas


func _sync_statuses() -> void:
	for sprite in _sprites():
		var button := sprite as TextureButton
		var battler: Battler = sprite_owner.get(button)
		var statuses: Array = []
		var sig := ""
		if battler != null and button.visible and not battler.is_fainted():
			statuses = _statuses_of(battler)
			for status in statuses:
				sig += "%s:%s:%s|" % [status.id, status.badge, status.turns]
		if str(_status_sig.get(button, "")) == sig:
			continue
		_status_sig[button] = sig
		_hide_status_tip()
		_rebuild_status_row(button, statuses)


func _clear_status_rows() -> void:
	_status_sig.clear()
	_hide_status_tip()
	for sprite in status_rows:
		var row: HBoxContainer = status_rows[sprite]
		for child in row.get_children():
			child.free()
		row.visible = false


func _rebuild_status_row(sprite: TextureButton, statuses: Array) -> void:
	var row: HBoxContainer = status_rows.get(sprite)
	if row == null:
		row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 2)
		add_child(row)
		status_rows[sprite] = row
	for child in row.get_children():
		row.remove_child(child)
		child.free()
	for status in statuses:
		row.add_child(_make_status_icon(status))
	row.visible = not statuses.is_empty()


func _make_status_icon(status: Dictionary) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(20, 20)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_HELP
	var plate := ColorRect.new()
	plate.color = Color(0, 0, 0, 0.72)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(plate)
	var icon := TextureRect.new()
	icon.texture = _status_textures.get(status.id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(icon)
	var badge_value := int(status.badge)
	if badge_value > 0:
		var badge := Label.new()
		badge.text = str(badge_value)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		badge.add_theme_constant_override("outline_size", 4)
		badge.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.offset_right = 1
		badge.offset_bottom = 1
		box.add_child(badge)
	box.mouse_entered.connect(_show_status_tip.bind(box, status))
	box.mouse_exited.connect(_hide_status_tip)
	return box


func _append_effect(found: Array, battler: Battler, status_id: String, title: String, detail: String, stacks: int) -> void:
	if not battler.has_effect(status_id):
		return
	var turns := battler.effect_turns(status_id)
	var badge := stacks if stacks > 1 else turns
	found.append(_status(status_id, title, detail, stacks, turns, badge, ""))


func _statuses_of(battler: Battler) -> Array:
	var found: Array = []
	if battler.stunned:
		found.append(_status("stun", "Stun", "Skips the next turn.", 0, 1, 1, ""))
	if battler.wound_stacks > 0:
		found.append(_status(
			"wound", "Wound",
			"Assassinate detonates these stacks for extra damage. Each new stack refreshes a 2-turn window.",
			battler.wound_stacks, battler.wound_turns, battler.wound_stacks, ""
		))
	_append_effect(found, battler, "paralysis", "Paralysis", "25% chance to skip the next action.", 0)
	_append_effect(found, battler, "bleed", "Bleed", "Deals a portion of the attack that caused it.", battler.effect_stacks("bleed"))
	_append_effect(found, battler, "burn", "Burn", "Deals damage each turn. Extra stacks make it stronger.", battler.effect_stacks("burn"))
	_append_effect(found, battler, "poison", "Poison", "Deals 8% of max HP each turn.", battler.effect_stacks("poison"))
	_append_effect(found, battler, "curse", "Curse", "Deals 15% of magic attack each turn.", 0)
	_append_effect(found, battler, "slow", "Slow", "Speed is halved. Extra stacks make it stronger.", battler.effect_stacks("slow"))
	if battler.is_siphoned():
		found.append(_status(
			"siphon", "Siphon",
			"Loses 8% max HP each turn. The source heals for half of that.",
			0, battler.siphon_turns, battler.siphon_turns, ""
		))
	if battler.blessed_stacks > 0:
		found.append(_status(
			"blessed", "Blessed",
			"Roeseph's staff builds these. Three stacks arm Divine Blessing.",
			battler.blessed_stacks, -1, battler.blessed_stacks, "until consumed"
		))
	if battler.shield_hp > 0:
		found.append(_status(
			"shield", "Shield",
			"Absorbs damage before HP is lost.",
			battler.shield_hp, -1, battler.shield_hp, "until broken"
		))
	for entry in battler.passives:
		var passive: KitPassive = entry
		if passive.kind == "rogue_stealth" and passive.stealthed:
			found.append(_status(
				"stealth", "Stealth",
				"The next strike deals more damage, and attacks are harder to land.",
				0, -1, 0, "until you attack or take damage"
			))
		elif passive.kind == "rogue_momentum" and passive.momentum > 0:
			var left := maxi(0, KitPassive.MOMENTUM_TURNS - passive.quiet_turns)
			found.append(_status(
				"momentum", "Momentum",
				"Each stack adds speed and attack, up to %d. It fades after %d turns without a kill." % [KitPassive.MOMENTUM_CAP, KitPassive.MOMENTUM_TURNS],
				passive.momentum, left, passive.momentum, ""
			))
		elif passive.kind == "taunt" and passive.taunt_turns > 0:
			found.append(_status(
				"taunt", "Taunt",
				"Enemies must aim at this fighter, and killing blows are softened.",
				0, passive.taunt_turns, passive.taunt_turns, ""
			))
		elif passive.kind == "will" and passive.guard_turns > 0:
			found.append(_status(
				"guard", "Second Wind",
				"Damage taken is sharply reduced.",
				0, passive.guard_turns, passive.guard_turns, ""
			))
		elif passive.kind == "frenzy" and passive.frenzy > 0:
			found.append(_status(
				"frenzy", "Frenzy",
				"Attack, defense, and speed rose each time damage was taken.",
				passive.frenzy, -1, passive.frenzy, "the rest of the fight"
			))
		elif passive.kind == "rage" and passive._raging(battler):
			found.append(_status(
				"rage", "Rage",
				"Attacks hit harder and can catch allies while below half HP.",
				0, -1, 0, "while below half HP"
			))
		elif passive.kind == "master" and passive.art_uses > 0 and passive.copied_art != null:
			found.append(_status(
				"art", "Mastered Art",
				"The copied art is %s." % passive.copied_art.move_name,
				passive.art_uses, passive.art_uses, passive.art_uses, ""
			))
	for other in sprite_owner.values():
		var source: Battler = other
		if source == null:
			continue
		for entry in source.passives:
			var passive: KitPassive = entry
			if passive.kind == "blessing" and passive.blessed == battler:
				found.append(_status(
					"blessing", "Blessing",
					"The next hit is softened.",
					0, 1, 1, ""
				))
	var seen := {}
	for entry in found:
		seen[str(entry.get("id", ""))] = true
	for raw_id in battler.effects.keys():
		var status_id := str(raw_id)
		if seen.has(status_id):
			continue
		_append_effect(
			found, battler, status_id, status_id.capitalize(),
			"A lingering effect.", battler.effect_stacks(status_id)
		)
	return found


func _status(id: String, title: String, detail: String, stacks: int, turns: int, badge: int, turns_text: String) -> Dictionary:
	return {
		"id": id,
		"name": title,
		"detail": detail,
		"stacks": stacks,
		"turns": turns,
		"badge": badge,
		"turns_text": turns_text,
		"count_name": "Shield" if id == "shield" else "Stacks",
	}


func _show_status_tip(icon: Control, status: Dictionary) -> void:
	tip_label.text = _tip_text(status)
	tip.visible = true
	tip.reset_size()
	var place := icon.global_position + Vector2(icon.size.x + 8, -4)
	if place.x + tip.size.x > get_viewport_rect().size.x - 8:
		place.x = icon.global_position.x - tip.size.x - 8
	var limit := get_viewport_rect().size.y - tip.size.y - 8
	place.y = clampf(place.y, 8, maxf(8, limit))
	tip.global_position = place


func _hide_status_tip() -> void:
	if tip != null:
		tip.visible = false


func _tip_text(status: Dictionary) -> String:
	var lines: PackedStringArray = [str(status.name), "", str(status.detail), ""]
	if int(status.stacks) > 0:
		lines.append("%s: %d" % [status.count_name, int(status.stacks)])
	if str(status.turns_text) != "":
		lines.append("Turns left: %s" % status.turns_text)
	elif int(status.turns) >= 0:
		lines.append("Turns left: %d" % int(status.turns))
	else:
		lines.append("Turns left: until it ends")
	return "\n".join(lines)
