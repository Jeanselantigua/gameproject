class_name BattleScreen
extends Control

## Team fight. Your side picks moves. The other side uses the AI selector.
## Turn order matches the Java scheduler: 10000 / speed, lowest time acts.

signal dismissed(action: String)

const CARD_SCENE := preload("res://Scenes/fighter_card.tscn")
const QUEUE_COUNT := 8

@onready var header: Label = $Header
@onready var log_label: Label = $Log
@onready var player_row: HBoxContainer = $Body/Teams/PlayerTeam
@onready var enemy_row: HBoxContainer = $Body/Teams/EnemyTeam
@onready var queue_box: VBoxContainer = $Body/QueuePanel/QueueBox
@onready var prompt: Label = $Prompt
@onready var move_box: HFlowContainer = $MoveBox
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_label: Label = $ResultPanel/ResultMargin/ResultColumn/ResultLabel

var rules: BattleRules
var views: Dictionary = {}
var session := 0
var choosing := false
var targeting := false
var pending_move: MoveData
var choosing_actor: Battler

signal choice_made(choice: Dictionary)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.visible = false
	_anchor_box($Log, 24, 46, -250, 108)
	_anchor_box($Body, 16, 114, -16, -146)
	_anchor_box($Prompt, 24, -138, -24, -108)
	_anchor_box($MoveBox, 24, -102, -24, -8)
	$Body.clip_contents = true
	player_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	enemy_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER


func _anchor_box(node: Control, left: float, top: float, right: float, bottom: float) -> void:
	node.layout_mode = 1
	node.anchor_left = 0
	node.anchor_top = 0 if top >= 0 else 1
	node.anchor_right = 1
	node.anchor_bottom = 0 if bottom >= 0 else 1
	node.offset_left = left
	node.offset_top = top
	node.offset_right = right
	node.offset_bottom = bottom
	node.grow_horizontal = Control.GROW_DIRECTION_BOTH
	node.grow_vertical = Control.GROW_DIRECTION_BOTH
	$ResultPanel/ResultMargin/ResultColumn/AgainButton.pressed.connect(func() -> void: dismissed.emit("again"))
	$ResultPanel/ResultMargin/ResultColumn/TitleButton.pressed.connect(func() -> void: dismissed.emit("teams"))


func begin(player_ids: Array[String], ai_ids: Array[String]) -> void:
	session += 1
	var token := session
	choosing = false
	targeting = false
	result_panel.visible = false
	header.text = "Your team  vs  AI team"
	log_label.text = ""
	prompt.text = ""
	_clear_moves()
	_clear_row(player_row)
	_clear_row(enemy_row)
	views.clear()
	var allies := _place(player_ids, "player", player_row)
	var foes := _place(ai_ids, "enemy", enemy_row)
	rules = BattleRules.new(allies, foes)
	_refresh_all()
	_run_battle(token)


func abort() -> void:
	session += 1
	choosing = false
	targeting = false
	if choice_made.get_connections().size() > 0:
		choice_made.emit({"cancel": true})


func _run_battle(token: int) -> void:
	while rules != null and rules.ongoing() and token == session:
		var actor := rules.next_actor()
		if actor == null:
			break
		_set_active(actor)
		var ready := rules.begin_turn(actor)
		if not rules.turn_notes.is_empty():
			_append_log(rules.turn_notes)
		var skipped := rules.skip_if_stunned(actor)
		if not skipped.is_empty():
			_append_log(skipped)
			_card(actor).popup("Stunned", Color("f0d060"))
			_card(actor).refresh()
			await get_tree().create_timer(0.4).timeout
		elif ready.is_empty():
			_append_log(["%s has no available actions!" % actor.display_name])
		elif actor.side == "player":
			var choice: Dictionary = await _player_choice(actor, ready)
			if token != session or bool(choice.get("cancel", false)):
				return
			await _perform(actor, choice.move, choice.target)
		else:
			prompt.text = "%s is acting..." % actor.display_name
			await get_tree().create_timer(0.35).timeout
			var ai: Dictionary = rules.ai_choice(actor, ready)
			if ai.is_empty():
				_append_log(["%s has no available actions!" % actor.display_name])
			else:
				await _perform(actor, ai.move, ai.target)
		if token != session:
			return
		if not rules.ongoing():
			break
		rules.advance(actor)
		_refresh_all()
	if token != session:
		return
	_set_active(null)
	_clear_moves()
	var summary := rules.winner_text()
	_append_log([summary])
	prompt.text = ""
	result_label.text = summary
	result_panel.visible = true


func _perform(actor: Battler, move: MoveData, target: Battler) -> void:
	var result := rules.resolve(actor, move, target)
	_append_log(result.lines)
	await _animate(result)
	_refresh_all()


func _animate(result: Dictionary) -> void:
	var actor_card := _card(result.actor)
	var move: MoveData = result.move
	if actor_card != null and move.targets == "enemy":
		await actor_card.play_attack()
	for event in result.events:
		var card := _card(event.target)
		if card == null:
			continue
		if event.kind == "heal" or event.kind == "shield":
			var label := "+%d" % int(event.damage) if event.kind == "heal" else "Shield"
			var pop_color := Color("8ee0a8") if event.kind == "heal" else Color("9fd4ff")
			card.popup(label, pop_color)
		elif event.kind == "miss":
			card.popup("Miss", Color("d9d3c5"))
		elif event.kind == "hit":
			await card.play_hit(bool(event.crit))
			var number := "0" if int(event.damage) <= 0 else str(int(event.damage))
			var color := Color("ffd56a") if bool(event.crit) else Color("f2efe6")
			card.popup(number, color)
			if bool(event.stunned):
				card.popup("Stun", Color("f0d060"))
			if bool(event.fainted):
				await card.play_faint()
		card.refresh()
		if move.anim == "bolt" and event.kind == "hit":
			await _bolt(actor_card, card)
		await get_tree().create_timer(0.12).timeout


func _bolt(from: Control, to: Control) -> void:
	if from == null or to == null:
		return
	var bolt := ColorRect.new()
	bolt.color = Color("9fd4ff")
	bolt.custom_minimum_size = Vector2(18, 6)
	bolt.size = Vector2(18, 6)
	bolt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bolt)
	bolt.global_position = from.global_position + from.size * 0.5
	var tw := create_tween()
	tw.tween_property(bolt, "global_position", to.global_position + to.size * 0.4, 0.16)
	await tw.finished
	bolt.queue_free()


func _player_choice(actor: Battler, ready: Array[MoveData]) -> Dictionary:
	choosing = true
	choosing_actor = actor
	targeting = false
	pending_move = null
	prompt.text = "%s — choose a move" % actor.display_name
	_show_moves(ready)
	var choice: Dictionary = await choice_made
	choosing = false
	targeting = false
	_clear_target_marks()
	_clear_moves()
	prompt.text = ""
	return choice


func _show_moves(ready: Array[MoveData]) -> void:
	_clear_moves()
	for move in choosing_actor.moves:
		var button := Button.new()
		var cooling := int(choosing_actor.cooldowns.get(move.move_name, 0))
		var detail := move.move_name
		if move.power > 0:
			detail += "  %d" % move.power
		if cooling > 0:
			detail += "  (%d)" % cooling
		button.text = detail
		button.custom_minimum_size = Vector2(200, 42)
		button.disabled = cooling > 0 or not ready.has(move)
		if not button.disabled:
			button.pressed.connect(_on_move_pressed.bind(move))
		move_box.add_child(button)


func _clear_moves() -> void:
	for child in move_box.get_children():
		move_box.remove_child(child)
		child.free()


func _on_move_pressed(move: MoveData) -> void:
	if not choosing or choosing_actor == null:
		return
	pending_move = move
	if move.targets == "self" or move.hits_all:
		var target := choosing_actor if move.targets == "self" else _first_foe(choosing_actor)
		if target == null:
			return
		targeting = false
		choice_made.emit({"move": move, "target": target})
		return
	targeting = true
	prompt.text = "Choose a target for %s" % move.move_name
	_mark_targets(true)


func _on_card_clicked(battler: Battler) -> void:
	if not targeting or pending_move == null or choosing_actor == null:
		return
	if pending_move.targets == "ally":
		if battler.side != choosing_actor.side or battler.is_fainted():
			return
	elif battler.side == choosing_actor.side or battler.is_fainted():
		return
	var forced := rules.aggro_target(choosing_actor)
	if forced != null and not pending_move.hits_all and battler != forced:
		return
	targeting = false
	_mark_targets(false)
	choice_made.emit({"move": pending_move, "target": battler})


func _mark_targets(on: bool) -> void:
	for key in views:
		var battler: Battler = key
		var card: FighterCard = views[battler]
		var mark := false
		if on and pending_move != null and choosing_actor != null:
			if pending_move.targets == "ally":
				mark = battler.side == choosing_actor.side and not battler.is_fainted()
			elif pending_move.targets == "enemy":
				var forced := rules.aggro_target(choosing_actor)
				var is_foe := battler.side != choosing_actor.side and not battler.is_fainted()
				if forced != null and not pending_move.hits_all:
					mark = battler == forced
				else:
					mark = is_foe
		card.set_targetable(mark or not on)


func _clear_target_marks() -> void:
	_mark_targets(false)


func _set_active(actor: Battler) -> void:
	for key in views:
		views[key].set_active(key == actor)


func _refresh_all() -> void:
	for key in views:
		views[key].refresh()
	_refresh_queue()


func _refresh_queue() -> void:
	for child in queue_box.get_children():
		queue_box.remove_child(child)
		child.free()
	if rules == null:
		return
	var upcoming: Array = rules.preview(QUEUE_COUNT)
	var now: float = float(upcoming[0].time) if not upcoming.is_empty() else 0.0
	for entry in upcoming:
		var battler: Battler = entry.battler
		var line := Label.new()
		line.text = "%s   %s" % [battler.display_name, "you" if battler.side == "player" else "ai"]
		line.add_theme_font_size_override("font_size", 14)
		line.add_theme_color_override("font_color", Color("b7a7e6") if battler.side == "player" else Color("e0a27a"))
		var wait := roundi(float(entry.time) - now)
		line.tooltip_text = "Acts in %d" % wait
		queue_box.add_child(line)


func _append_log(lines: Array) -> void:
	var current := log_label.text.split("\n", false)
	for line in lines:
		current.append(str(line))
	if current.size() > 6:
		current = current.slice(current.size() - 6)
	log_label.text = "\n".join(current)


func _place(ids: Array[String], side: String, row: HBoxContainer) -> Party:
	var party := Party.new(side)
	for id in ids:
		var battler := Roster.spawn(id, true)
		party.add(battler)
		var card := CARD_SCENE.instantiate() as FighterCard
		row.add_child(card)
		card.setup(battler)
		card.clicked.connect(_on_card_clicked)
		views[battler] = card
	return party


func _clear_row(row: HBoxContainer) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.free()


func _card(battler: Battler) -> FighterCard:
	return views.get(battler) as FighterCard


func _first_foe(actor: Battler) -> Battler:
	var foes := rules.foes_of(actor)
	if foes.is_empty():
		return null
	var forced := rules.aggro_target(actor)
	return forced if forced != null else foes[0]
