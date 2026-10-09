class_name Battler
extends RefCounted

## Java Character. Gear bonuses live in gear_bonus so they can be swapped without touching level growth.

var display_name: String
var max_hp: int
var hp: int
var attack: int
var defense: int
var magic_attack: int
var magic_defense: int
var speed: int
var crit_rate: int
var crit_damage: int
var affinity: int
var color: Color
var moves: Array[MoveData] = []
var side: String = ""
var stunned: bool = false
var shield_hp: int = 0
var cooldowns: Dictionary = {}
var level: int = 1
var xp: int = 0
var kit_moves: Array[MoveData] = []
var passives: Array = []
var wound_stacks: int = 0
var wound_turns: int = 0
var rank_xp: int = 0
var effects: Dictionary = {}
var siphon_source: Battler
var siphon_turns: int = 0
var queued_skips: int = 0
var blessed_stacks: int = 0
var summoner: Battler
var sprite_id: String = ""
var sprite_tint: Color = Color.WHITE
var bounty: int = 0
var rank: String = "normal"
var gear_bonus: Dictionary = {}
var set_two: Dictionary = {}
var unspent_stat_points: int = 0
var specialties: Array[String] = []
var immunities: Array[String] = []
var queued_move: MoveData
var queued_target: Battler

const WOUND_CAP := 6
const MAX_LEVEL := 30
const UNLOCK_LEVELS: Array[int] = [1, 6, 12, 18]


func is_fainted() -> bool:
	return hp <= 0


func effective_power(move: MoveData) -> int:
	if move == null or move.power <= 0:
		return 0
	return move.power


func move_scaling(_move: MoveData) -> float:
	return 1.0


func crit_multiplier() -> float:
	return 1.0 + crit_damage / 100.0


func tick_cooldowns() -> void:
	var names: Array = cooldowns.keys()
	for move_name in names:
		var left: int = int(cooldowns[move_name]) - 1
		if left <= 0:
			cooldowns.erase(move_name)
		else:
			cooldowns[move_name] = left


func available_moves() -> Array[MoveData]:
	var ready: Array[MoveData] = []
	for move in moves:
		if int(cooldowns.get(move.move_name, 0)) <= 0:
			ready.append(move)
	return ready


func start_cooldown(move: MoveData) -> void:
	if move != null and move.cooldown_turns > 0:
		cooldowns[move.move_name] = move.cooldown_turns


func knows(move_name: String) -> bool:
	for move in moves:
		if move.move_name == move_name:
			return true
	return false


func forces_aggro() -> bool:
	if is_fainted():
		return false
	for passive in passives:
		if passive.forces_aggro(self):
			return true
	return false


## Awards dungeon XP. Unlocks the 6 / 12 / 18 moves and applies the automatic +4 HP / +1 Speed.
func grant_xp(amount: int) -> Array[String]:
	var notes: Array[String] = []
	if amount <= 0 or level >= MAX_LEVEL:
		return notes
	xp += amount
	var gained := 0
	while level < MAX_LEVEL and xp >= 100 * level:
		xp -= 100 * level
		level += 1
		gained += 1
		max_hp += 4
		if hp > 0:
			hp += 4
		speed += 1
	if gained > 0:
		unspent_stat_points += gained
		notes.append("%s reached level %d." % [display_name, level])
	for index in kit_moves.size():
		var unlock: int = UNLOCK_LEVELS[index] if index < UNLOCK_LEVELS.size() else 18
		var move: MoveData = kit_moves[index]
		if level < unlock or knows(move.move_name):
			continue
		moves.append(move)
		notes.append("%s learned %s!" % [display_name, move.move_name])
	if level >= MAX_LEVEL:
		xp = 0
	return notes


func xp_to_next() -> int:
	if level >= MAX_LEVEL:
		return 0
	return 100 * level


func is_immune(status_id: String) -> bool:
	return immunities.has(status_id)


func point_gain(kind: String) -> int:
	var specialty := specialties.has(kind)
	if kind == "hp":
		return 4 if specialty else 3
	if kind == "speed":
		return 3 if specialty else 2
	return 4 if specialty else 3


## Spends one level-up point. Specialty stats grow further. Returns the amount added.
func spend_stat_point(kind: String) -> int:
	if unspent_stat_points <= 0:
		return 0
	var gain := point_gain(kind)
	match kind:
		"hp":
			max_hp += gain
			if hp > 0:
				hp += gain
		"attack":
			attack += gain
		"defense":
			defense += gain
		"magic_attack":
			magic_attack += gain
		"magic_defense":
			magic_defense += gain
		"speed":
			speed += gain
		_:
			return 0
	unspent_stat_points -= 1
	return gain


func is_summon() -> bool:
	return summoner != null


func effective_speed() -> int:
	var pace := speed
	if not has_effect("slow"):
		return maxi(1, pace)
	var strength := 0.5 * effect_effectiveness("slow")
	return maxi(1, roundi(float(pace) * (1.0 - strength)))


func has_effect(status_id: String) -> bool:
	return effects.has(status_id)


func effect_magnitude(status_id: String) -> int:
	if not effects.has(status_id):
		return 0
	return int(effects[status_id].magnitude)


func effect_turns(status_id: String) -> int:
	if not effects.has(status_id):
		return 0
	return int(effects[status_id].turns)


func effect_stacks(status_id: String) -> int:
	if not effects.has(status_id):
		return 0
	return int(effects[status_id].stacks)


func effect_effectiveness(status_id: String) -> float:
	if not effects.has(status_id):
		return 1.0
	return float(effects[status_id].effectiveness)


func has_ordinary_status() -> bool:
	return not effects.is_empty() or stunned


func is_siphoned() -> bool:
	return siphon_turns > 0 and siphon_source != null


## stacked, refreshed, or applied. Stacking statuses do not refresh duration.
func apply_effect(status_id: String, magnitude: int, duration: int) -> String:
	if effects.has(status_id):
		var current: Dictionary = effects[status_id]
		if status_id in ["bleed", "poison", "burn", "slow"]:
			var stacks: int = int(current.stacks) + 1
			current.stacks = stacks
			current.effectiveness = 1.0 + 0.15 * float(stacks - 1)
			effects[status_id] = current
			return "stacked"
		if status_id == "paralysis":
			queued_skips = 0
		current.magnitude = maxi(0, magnitude)
		current.turns = maxi(0, duration)
		current.stacks = 1
		current.effectiveness = 1.0
		effects[status_id] = current
		return "refreshed"
	effects[status_id] = {
		"magnitude": maxi(0, magnitude),
		"turns": maxi(0, duration),
		"stacks": 1,
		"effectiveness": 1.0,
	}
	return "applied"


func clear_effect(status_id: String) -> void:
	effects.erase(status_id)
	if status_id == "paralysis":
		queued_skips = 0


func clear_debuffs() -> void:
	var ids: Array = effects.keys()
	for status_id in ids:
		clear_effect(str(status_id))
	stunned = false
	siphon_source = null
	siphon_turns = 0
	wound_stacks = 0
	wound_turns = 0


func apply_siphon(source: Battler, turns: int) -> void:
	siphon_source = source
	siphon_turns = turns


func tick_siphon() -> bool:
	if siphon_turns <= 0:
		return false
	siphon_turns -= 1
	if siphon_turns == 0:
		siphon_source = null
		return true
	return false


func consume_queued_skip() -> bool:
	if queued_skips <= 0:
		return false
	queued_skips -= 1
	return true


func add_wound() -> void:
	wound_stacks = mini(WOUND_CAP, wound_stacks + 1)
	wound_turns = 2


func tick_wounds() -> bool:
	if wound_turns <= 0:
		return false
	wound_turns -= 1
	if wound_turns == 0:
		wound_stacks = 0
		return true
	return false


func add_blessed(amount: int, cap: int) -> int:
	var before := blessed_stacks
	blessed_stacks = mini(cap, blessed_stacks + amount)
	return blessed_stacks - before


func grow_max_hp(amount: int) -> void:
	if amount <= 0 or max_hp <= 0:
		return
	var ratio := float(hp) / float(max_hp)
	max_hp += amount
	hp = clampi(roundi(ratio * float(max_hp)), 0, max_hp)


func take_direct(amount: int) -> int:
	var loss := mini(hp, maxi(0, amount))
	hp -= loss
	return loss


## Drops battle-only statuses between dungeon rooms. HP, level, and learned moves stay.
func clear_battle_state() -> void:
	stunned = false
	shield_hp = 0
	wound_stacks = 0
	wound_turns = 0
	effects.clear()
	siphon_source = null
	siphon_turns = 0
	queued_skips = 0
	blessed_stacks = 0
	queued_move = null
	queued_target = null
	cooldowns.clear()
	for passive in passives:
		if str(passive.kind).begins_with("set_"):
			passive.reset_set(self)


func restore() -> void:
	hp = max_hp
	stunned = false
	shield_hp = 0
	wound_stacks = 0
	wound_turns = 0
	effects.clear()
	siphon_source = null
	siphon_turns = 0
	queued_skips = 0
	blessed_stacks = 0
	queued_move = null
	queued_target = null


func scaled(mult: float) -> Battler:
	var copied: Array[MoveData] = []
	copied.assign(moves)
	var copy := Battler.create(
		display_name,
		maxi(1, roundi(float(max_hp) * mult)),
		maxi(0, roundi(float(attack) * mult)),
		maxi(0, roundi(float(defense) * mult)),
		maxi(0, roundi(float(magic_attack) * mult)),
		roundi(float(magic_defense) * mult),
		maxi(1, roundi(float(speed) * mult)),
		affinity,
		color,
		copied
	)
	copy.rank_xp = rank_xp
	return copy


static func create(
	display_name: String,
	max_hp: int,
	attack: int,
	defense: int,
	magic_attack: int,
	magic_defense: int,
	speed: int,
	affinity: int,
	color: Color,
	moves: Array[MoveData]
) -> Battler:
	var battler := Battler.new()
	battler.display_name = display_name
	battler.max_hp = max_hp
	battler.hp = max_hp
	battler.attack = attack
	battler.defense = defense
	battler.magic_attack = magic_attack
	battler.magic_defense = magic_defense
	battler.speed = speed
	battler.affinity = affinity
	battler.color = color
	battler.moves = moves
	return battler
