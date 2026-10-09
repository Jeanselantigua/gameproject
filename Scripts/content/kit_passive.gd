class_name KitPassive
extends RefCounted

## One fresh passive per battler. kind selects the Java hook this object stands in for.

const MOMENTUM_CAP := 30
const MOMENTUM_TURNS := 2

var kind: String = ""
var stealthed: bool = false
var momentum: int = 0
var quiet_turns: int = 0
var bonus_crit: int = 0
var accuracy_bonus: int = 0
var taunt_turns: int = 0
var frenzy: int = 0
var blessed: Battler
var splash: Array = []
var rage_announced: bool = false
var blade_spent: bool = false
var guard_turns: int = 0
var copied_art: MoveData
var art_uses: int = 0
var suppressed: bool = false
var charged: bool = false
var chicken: Battler
var revives: int = 0
var explode_pending: bool = false
var winding: bool = false
var releasing: bool = false
var stored_slam: MoveData
var stored_target: Battler
var phase: String = "idle"
var team_channel: bool = false
var channel_left: int = 0
var enlightened_left: int = 0
var idle_hits: int = 0
var dodge_active: bool = false
var dodge_stacks: int = 0
var hit_stacks: int = 0
var dodge_idle: int = 0
var splashing: bool = false
var dragon_phase: int = 1
var set_applied: int = 0
var set_buffed: Array = []
var set_armed: bool = true


func forces_aggro(owner: Battler) -> bool:
	return kind == "taunt" and taunt_turns > 0 and owner != null and not owner.is_fainted()


func filter_moves(owner: Battler, ready: Array, rules = null) -> Array:
	if kind != "rogue_stealth" and kind != "will" and kind != "enlightenment":
		return ready
	var kept: Array = []
	for move in ready:
		var data: MoveData = move
		if kind == "rogue_stealth" and not stealthed and data.move_name == "Ambush":
			continue
		if kind == "will" and data.move_name == "The Will of Humanity":
			continue
		if kind == "enlightenment" and not _keep_monk_move(owner, data, rules):
			continue
		kept.append(data)
	return kept


func restrict_opponent(owner: Battler, _actor: Battler, ready: Array) -> Array:
	if kind != "enlightenment" or phase != "channeling" or team_channel:
		return ready
	var kept: Array = []
	for move in ready:
		var data: MoveData = move
		if _is_debuff(data):
			kept.append(data)
	return kept


func skips_own_action(_owner: Battler) -> bool:
	if kind == "enlightenment" and phase == "channeling":
		return true
	return kind == "slam" and winding


func on_action_skipped(owner: Battler, rules, lines: Array[String]) -> void:
	if kind == "enlightenment":
		_skip_channel(owner, rules, lines)
	elif kind == "slam":
		_release_slam(owner, rules, lines)


func on_field_changed(owner: Battler, rules, lines: Array[String]) -> void:
	if kind == "enlightenment":
		_fail_channel(owner, rules, lines)
	elif kind == "explode" and explode_pending and rules != null:
		_explode_shield(owner, rules, lines)


func on_shield_broken(owner: Battler, _attacker: Battler, _rules, _lines: Array[String]) -> void:
	if kind == "explode":
		explode_pending = true


func on_status_received(owner: Battler, status_id: String, _source: Battler, lines: Array[String]) -> void:
	if kind == "enlightenment" and phase == "channeling" and status_id == "stun":
		lines.append("%s's Meditate is interrupted!" % owner.display_name)
		_become_angered(owner, lines)


func roll_dodge(_owner: Battler, _attacker: Battler, _move: MoveData) -> bool:
	return kind == "enlightenment" and dodge_active and randf() < _dodge_chance()


func on_dodged(owner: Battler, attacker: Battler, move: MoveData, rules, lines: Array[String]) -> void:
	if kind != "enlightenment" or attacker == null:
		return
	dodge_idle = 0
	dodge_stacks += 1
	var percent := roundi(_dodge_chance() * 100.0)
	lines.append("%s perfectly dodges! Dodge chance is now %d%%." % [owner.display_name, percent])
	var ratio := 0.35 if team_channel else 0.25
	var counter: int = maxi(1, roundi(float(owner.attack) * ratio))
	var actual: int = attacker.take_direct(counter)
	lines.append("%s counters for %d damage!" % [owner.display_name, actual])
	_apply_blessed(attacker, 1, lines)
	if attacker.is_fainted():
		lines.append("%s has fainted!" % attacker.display_name)
		if rules != null:
			rules._notify_faint(attacker, owner, move, lines)


func should_reroll_status(owner: Battler, _target: Battler, move: MoveData, lines: Array[String]) -> bool:
	if kind != "status_reroll" or move == null or move.status_id == "" or randf() >= 0.10:
		return false
	lines.append("%s presses the status from %s!" % [owner.display_name, move.move_name])
	return true


func modify_status_magnitude(owner: Battler, _target: Battler, status_id: String, magnitude: int, lines: Array[String]) -> int:
	if kind == "status_reroll" and status_id == "bleed":
		lines.append("%s makes bleed deeper!" % owner.display_name)
		return roundi(float(magnitude) * 1.5)
	return magnitude


func on_ally_healed(_owner: Battler, target: Battler, amount: int, lines: Array[String]) -> void:
	if kind != "blessing" or target == null:
		return
	var had := target.has_ordinary_status() or target.is_siphoned() or target.wound_stacks > 0
	target.clear_debuffs()
	if had:
		lines.append("%s is cleansed of harmful statuses!" % target.display_name)
	if amount <= 0:
		return
	blessed = target
	lines.append("%s is blessed and will take less damage from the next hit!" % target.display_name)


func rewrite_move(owner: Battler, move: MoveData, target: Battler, lines: Array[String]) -> MoveData:
	if kind == "slam":
		return _rewrite_slam(owner, move, target, lines)
	if kind != "master" or move == null or move.move_name != "Master of Any Art" or target == null:
		return null
	if art_uses <= 0 or copied_art == null:
		copied_art = _best_art(target)
		if copied_art == null:
			lines.append("%s finds no art to master." % owner.display_name)
			return null
		art_uses = 1 if copied_art.cooldown_turns > 0 else 3
		lines.append("%s masters %s! (%d use%s)" % [
			owner.display_name, copied_art.move_name, art_uses, "" if art_uses == 1 else "s"
		])
	art_uses -= 1
	return _holy_copy(copied_art)


func defer_cooldown(move: MoveData) -> bool:
	return kind == "master" and move != null and move.move_name == "Master of Any Art" and art_uses > 0


func modify_accuracy(_owner: Battler, _move: MoveData, accuracy: int, target: Battler = null) -> int:
	if kind == "hunt" and _is_stealthed(target):
		return accuracy + 40
	if kind == "accuracy":
		return accuracy + accuracy_bonus
	return accuracy


func modify_incoming_accuracy(_owner: Battler, accuracy: int, move: MoveData = null) -> int:
	if kind == "rogue_stealth" and stealthed:
		return accuracy - 35
	if kind == "enlightenment" and phase == "channeling" and _is_debuff(move):
		var factor := 0.60 if team_channel else 0.75
		return roundi(float(accuracy) * factor)
	return accuracy


func modify_crit_rate(_owner: Battler, move: MoveData, rate: int) -> int:
	if kind == "rogue_stealth":
		var bonus: int = 45 if move != null and move.move_name == "Ambush" else 15
		return rate + bonus
	if kind == "champion_strength" and move != null and move.targets != "ally" and move.targets != "self":
		return rate + bonus_crit
	if kind == "enlightenment" and phase == "angered" and (move == null or move.move_name == "Heavy Staff Swing"):
		return rate + 60
	return rate


func crit_damage_bonus(move: MoveData, owner: Battler = null) -> int:
	if kind == "rogue_stealth":
		return 100
	if kind == "champion_strength" and move != null and move.targets != "ally" and move.targets != "self":
		return 100
	if kind == "set_swift" and owner != null and owner.speed > 80:
		return 40
	if kind == "set_swift" and owner != null and owner.speed > 60:
		return 20
	return 0


func modify_outgoing(owner: Battler, target: Battler, move: MoveData, amount: float, is_crit: bool, crit_mult: float, lines: Array[String]) -> float:
	if kind == "champion_strength":
		var flat := _champion_flat(move)
		if flat >= 0:
			var dealt := float(flat)
			if is_crit:
				dealt *= crit_mult
			return dealt
	if kind == "holy_split" and not suppressed and move != null and move.power > 0:
		var bonus := float(owner.magic_attack) * 0.60
		lines.append("%s's holy power adds %d bonus damage!" % [owner.display_name, roundi(bonus)])
		return amount + bonus
	if kind == "slow_cook" and target != null and (target.is_siphoned() or target.has_ordinary_status()):
		lines.append("%s's slow cook extra-tenderizes %s!" % [owner.display_name, target.display_name])
		return amount * 1.20
	if kind == "enlightenment" and phase == "enlightened" and _is_staff(move):
		return amount * 0.25
	if kind == "enlightenment" and phase == "angered" and move != null and move.move_name == "Heavy Staff Swing" and randf() < 0.25:
		lines.append("%s easily holds against the wild swing!" % target.display_name)
		return 0.0
	if kind == "rage" and _raging(owner) and move != null and move.targets == "enemy" and not splash.has(target):
		return amount * 1.35
	if kind == "rogue_stealth" and stealthed:
		lines.append("%s strikes from the shadows!" % owner.display_name)
		return amount * 1.5
	if kind == "will" and blade_spent:
		return amount * 0.68
	return amount


func modify_incoming(owner: Battler, attacker: Battler, move: MoveData, amount: float, lines: Array[String]) -> float:
	if kind == "parry" and not suppressed and move != null and move.element == Element.Id.PHYSICAL and amount > 0.0 and randf() < 0.20:
		var reflected: int = roundi(amount * 0.75)
		var loss: int = attacker.take_direct(reflected)
		lines.append("%s parries and reflects %d damage back at %s!" % [owner.display_name, loss, attacker.display_name])
		return 0.0
	if kind == "enlightenment" and phase == "channeling" and team_channel:
		return amount * 0.40
	if kind == "taunt" and taunt_turns > 0 and amount > 0.0:
		var reduced := amount / 1.20
		var pool := owner.hp + owner.shield_hp
		if pool > 0 and reduced >= float(pool):
			lines.append("%s's pride turns the killing blow aside!" % owner.display_name)
			reduced *= 0.40
		return reduced
	if kind == "will" and guard_turns > 0:
		return amount * 0.30
	return amount


func modify_incoming_to_ally(_owner: Battler, ally: Battler, amount: float, lines: Array[String]) -> float:
	if kind != "blessing" or blessed == null or ally != blessed or amount <= 0.0:
		return amount
	blessed = null
	lines.append("%s's blessing softens the blow!" % ally.display_name)
	return amount * 0.60


func expand_targets(owner: Battler, move: MoveData, chosen: Array, rules, lines: Array[String]) -> Array:
	if kind == "storm" and move != null and move.move_name == "Chain Lightning" and rules != null and not chosen.is_empty():
		return _chain(chosen[0], rules.opponents(owner), rules, lines)
	if kind != "rage" or move == null or move.targets != "enemy":
		return chosen
	splash.clear()
	if not _raging(owner):
		rage_announced = false
		return chosen
	var targets: Array = []
	for foe in rules.foes_of(owner):
		targets.append(foe)
	var allies_hit: Array = []
	for ally in rules.allies_of(owner):
		var friend: Battler = ally
		if friend != owner and not friend.is_fainted():
			targets.append(friend)
			allies_hit.append(friend)
			splash.append(friend)
	if targets.is_empty():
		return chosen
	if not rage_announced:
		rage_announced = true
		lines.append("%s enters a blind fury!" % owner.display_name)
	if not allies_hit.is_empty():
		lines.append("Well Oiled Rage catches allies in the crossfire!")
	return targets


func follow_up(owner: Battler, move: MoveData, lines: Array[String]) -> MoveData:
	if kind != "whirlwind" or move == null or move.move_name != "Electric Whirlwind":
		return null
	if move.element != Element.Id.LIGHTNING:
		return null
	lines.append("%s's Electric Whirlwind also rips with steel!" % owner.display_name)
	return MoveData.make("Electric Whirlwind", Element.Id.PHYSICAL, 40, 100, false, "bleed", 100)


func should_repeat(owner: Battler, move: MoveData, lines: Array[String]) -> bool:
	if kind != "dual_repeat" or move == null or move.targets != "enemy":
		return false
	if move.move_name == "Electric Whirlwind":
		return false
	if randf() >= 0.15:
		return false
	lines.append("%s strikes again with %s!" % [owner.display_name, move.move_name])
	return true


func skips_status(target: Battler) -> bool:
	return kind == "rage" and splash.has(target)


func on_turn_start(owner: Battler, lines: Array[String], rules = null) -> void:
	if kind == "rogue_momentum" and momentum > 0 and not owner.is_fainted():
		quiet_turns += 1
		if quiet_turns >= MOMENTUM_TURNS:
			owner.speed -= momentum * 5
			owner.attack -= momentum * 3
			momentum = 0
			quiet_turns = 0
			lines.append("%s's Momentum fades." % owner.display_name)
	if kind == "taunt" and taunt_turns > 0:
		taunt_turns -= 1
		if taunt_turns == 0:
			lines.append("%s's taunt fades." % owner.display_name)
	if kind == "will" and guard_turns > 0:
		guard_turns -= 1
		if guard_turns == 0:
			lines.append("%s's second wind fades." % owner.display_name)
	if kind == "enlightenment":
		_tick_enlightenment(owner, lines)
		_tick_dodge(owner, lines)
	if kind == "set_bulwark":
		_bulwark(owner, lines)
	if kind == "set_warlord" and rules != null:
		_warlord(owner, rules, lines)
	if kind == "set_sage" and rules != null:
		_sage(owner, rules, lines)


func on_action_resolved(owner: Battler, move: MoveData, lines: Array[String], target: Battler = null, rules = null) -> void:
	if kind == "taunt" and move != null and move.move_name == "Prideful Taunt":
		taunt_turns = 2
		lines.append("%s boasts without fear. All eyes turn to them!" % owner.display_name)
	if kind == "slam":
		releasing = false
	if kind == "enlightenment":
		_resolve_monk_action(owner, move, target, rules, lines)


func on_hit_landed(owner: Battler, target: Battler, move: MoveData, damage_dealt: int, is_crit: bool, lines: Array[String], rules = null) -> void:
	if kind == "accuracy":
		accuracy_bonus = 0
	if kind == "chicken":
		_try_chicken(owner, move, damage_dealt, rules, lines)
	if kind == "spark_mercy":
		_spark_mercy(owner, move, damage_dealt, rules, lines)
	if kind == "divine_palm":
		_palm_splash(owner, target, move, damage_dealt, rules, lines)
	if kind == "set_vampire" and damage_dealt > 0 and move != null and move.element == Element.Id.PHYSICAL and not owner.is_fainted():
		var siphon: int = int(round(float(damage_dealt) * 0.25))
		if siphon > 0:
			var before: int = owner.hp
			owner.hp = mini(owner.max_hp, owner.hp + siphon)
			var gained: int = owner.hp - before
			if gained > 0:
				lines.append("%s's Vampire set siphons %d HP!" % [owner.display_name, gained])
	if kind != "rogue_stealth" or damage_dealt <= 0:
		return
	if stealthed:
		stealthed = false
	if is_crit:
		stealthed = true
		lines.append("%s vanishes into the shadows!" % owner.display_name)


func on_attack_missed(owner: Battler, _move: MoveData, lines: Array[String]) -> void:
	if kind != "accuracy":
		return
	accuracy_bonus += 5
	lines.append("%s grows more determined! (+5 accuracy)" % owner.display_name)


func on_attack_connected(owner: Battler, target: Battler, move: MoveData, is_crit: bool, lines: Array[String], blocked: bool = false) -> void:
	if kind == "enlightenment":
		_monk_connected(owner, target, move, blocked, lines)
	if kind == "champion_strength" and move != null and move.targets == "enemy":
		if is_crit:
			if bonus_crit > 0:
				lines.append("%s's Champion's Strength resets." % owner.display_name)
			bonus_crit = 0
		else:
			bonus_crit = mini(100, bonus_crit + 12)
			lines.append("%s's Champion's Strength builds (+12%% crit)." % owner.display_name)
	if kind == "rogue_wound" and move != null and move.move_name == "Assassinate" and target != null and target.wound_stacks > 0:
		var stacks: int = target.wound_stacks
		target.wound_stacks = 0
		var per: int = 15 + roundi(float(target.max_hp) * 0.025)
		var boom: int = stacks * per
		var absorbed: int = mini(target.shield_hp, boom)
		target.shield_hp -= absorbed
		if absorbed > 0 and target.shield_hp <= 0:
			for passive in target.passives:
				passive.on_shield_broken(target, owner, null, lines)
		var loss: int = boom - absorbed
		if loss > 0:
			target.hp = maxi(0, target.hp - loss)
		lines.append("%s triggers %d wound stack%s for %d damage!" % [
			owner.display_name, stacks, "" if stacks == 1 else "s", loss
		])


func on_damage_taken(owner: Battler, damage_taken: int, lines: Array[String]) -> void:
	if kind == "dragon_phase":
		_dragon_phase(owner, damage_taken, lines)
		return
	if kind == "rogue_stealth" and stealthed and damage_taken > 0:
		stealthed = false
		lines.append("%s is forced out of the shadows!" % owner.display_name)
	if kind == "frenzy" and damage_taken > 0 and frenzy < 4:
		owner.attack += 10
		owner.defense += 20
		owner.magic_defense += 20
		owner.speed += 5
		frenzy += 1
		lines.append("%s flies into a frenzy, he's growing stronger!" % owner.display_name)
	if kind == "charged":
		_refresh_charge(owner, lines)
	if kind == "enlightenment" and dodge_active and _dodge_chance() > 0.0:
		hit_stacks += 1
		lines.append("%s is hit! Dodge chance is now %d%%." % [owner.display_name, roundi(_dodge_chance() * 100.0)])
	if kind == "set_bulwark":
		_bulwark(owner, lines)


func _dragon_phase(owner: Battler, damage_taken: int, lines: Array[String]) -> void:
	if damage_taken <= 0 or owner.max_hp <= 0:
		return
	var ratio := float(owner.hp) / float(owner.max_hp)
	if dragon_phase == 1 and ratio <= 0.50:
		dragon_phase = 2
		if not owner.knows("Inferno"):
			owner.moves.append(MoveData.make(
				"Inferno", Element.Id.FIRE, 80, 90, true, "burn", 100, "bolt"
			))
		owner.speed += 10
		lines.append("%s enrages! Inferno joins the kit." % owner.display_name)
	if dragon_phase == 2 and ratio <= 0.25:
		dragon_phase = 3
		owner.attack += 10
		owner.defense += 10
		owner.magic_attack += 10
		owner.magic_defense += 10
		owner.speed += 10
		lines.append("%s screeches. The last stand begins." % owner.display_name)


func on_kill(owner: Battler, victim: Battler, rules, lines: Array[String]) -> void:
	if owner.is_fainted() or victim == null or victim == owner:
		return
	if kind == "rogue_momentum":
		quiet_turns = 0
		if momentum >= MOMENTUM_CAP:
			lines.append("%s's Momentum holds at %d stacks." % [owner.display_name, momentum])
		else:
			momentum += 1
			owner.speed += 5
			owner.attack += 3
			lines.append("%s gains Momentum! (%d stack%s: +%d speed, +%d attack)" % [
				owner.display_name, momentum, "" if momentum == 1 else "s", momentum * 5, momentum * 3
			])
	if kind == "champion_strength":
		var amount: int = roundi(float(victim.max_hp) * 0.25)
		var party: Array = rules.allies_of(owner)
		for ally in party:
			var friend: Battler = ally
			if friend.is_fainted() or amount <= 0:
				continue
			var before: int = friend.hp
			friend.hp = mini(friend.max_hp, friend.hp + amount)
			var healed: int = friend.hp - before
			if healed > 0:
				lines.append("%s recovers %d HP from Champion's Strength!" % [friend.display_name, healed])
	if kind == "kill_hp":
		owner.grow_max_hp(40)
		lines.append("%s grows stronger, max HP is now %d!" % [owner.display_name, owner.max_hp])
	if kind == "set_vampire4" and not owner.is_fainted():
		var gain: int = maxi(1, int(round(float(owner.max_hp) * 0.045)))
		owner.max_hp += gain
		owner.hp = mini(owner.max_hp, owner.hp + gain)
		lines.append("%s's Vampire set grows (+%d max HP)!" % [owner.display_name, gain])


func on_faint(owner: Battler, lines: Array[String], rules = null) -> void:
	if kind == "set_sage":
		_clear_sage()
	if kind == "set_warlord" and owner != null and set_applied != 0:
		owner.attack -= set_applied
		set_applied = 0
	if kind == "will" and not blade_spent and owner != null and owner.knows("The Will of Humanity"):
		owner.hp = owner.max_hp
		blade_spent = true
		guard_turns = 4
		lines.append("%s answers with The Will of Humanity!" % owner.display_name)
		lines.append("The blade is spent. Full health, 70% less damage taken for 4 turns, and 32% weaker strikes for the rest of the run.")
	if kind == "revive" and rules != null and owner.is_fainted() and revives < 1:
		rules.add_ally(owner, _undead_sion(owner), lines)
		revives += 1


func on_healed(target: Battler, amount: int, lines: Array[String]) -> void:
	if kind == "set_bulwark":
		_bulwark(target, lines)
	if kind != "charged" or amount <= 0:
		return
	_refresh_charge(target, lines)


func _raging(owner: Battler) -> bool:
	return owner != null and not owner.is_fainted() and owner.hp * 2 < owner.max_hp


func _champion_flat(move: MoveData) -> int:
	if move == null:
		return -1
	if move.move_name == "Uplifting Slash":
		return 35
	if move.move_name == "Visceral Wound":
		return 60
	return -1


func _best_art(target: Battler) -> MoveData:
	if target.kit_moves.size() >= 4 and target.knows(target.kit_moves[3].move_name):
		return target.kit_moves[3]
	var best: MoveData = null
	var best_power := -1
	var pool: Array = target.kit_moves if not target.kit_moves.is_empty() else target.moves
	for move in pool:
		var data: MoveData = move
		if data.targets != "enemy" or data.power <= best_power:
			continue
		best = data
		best_power = data.power
	return best


func _holy_copy(source: MoveData) -> MoveData:
	var chance := 100 if source.status_id != "" else 0
	var copy := MoveData.make(
		source.move_name, Element.Id.HOLY, source.power, 100, source.is_magic,
		source.status_id, chance, source.anim, "enemy", 0, source.hits_all
	)
	copy.min_hits = source.min_hits
	copy.max_hits = source.max_hits
	copy.cooldown_turns = 0
	copy.priority = source.priority
	return copy


func _is_debuff(move: MoveData) -> bool:
	if move == null:
		return false
	return move.status_id in ["burn", "poison", "bleed", "wound", "curse", "paralysis", "stun", "slow", "siphon"]


func _is_staff(move: MoveData) -> bool:
	return move != null and (move.move_name == "Oochie" or move.move_name == "Divine Palm")


func _is_stealthed(target: Battler) -> bool:
	if target == null:
		return false
	for passive in target.passives:
		if str(passive.kind) == "rogue_stealth" and bool(passive.stealthed):
			return true
	return false


func _is_real_slam(move: MoveData) -> bool:
	return move != null and move.move_name == "Decamating Slam" and move.status_id != "utility"


func _rewrite_slam(owner: Battler, move: MoveData, target: Battler, lines: Array[String]) -> MoveData:
	if releasing or not _is_real_slam(move):
		return null
	stored_slam = move
	stored_target = target
	winding = true
	lines.append("%s begins charging Decamating Slam!" % owner.display_name)
	return MoveData.make("Decamating Slam", Element.Id.PHYSICAL, 0, 100, false, "utility", 100, "cast", "self")


func _release_slam(owner: Battler, rules, lines: Array[String]) -> void:
	if not winding:
		return
	winding = false
	if owner.is_fainted() or owner.stunned:
		releasing = false
		lines.append("%s's Decamating Slam is interrupted!" % owner.display_name)
		return
	var victim: Battler = stored_target
	if victim == null or victim.is_fainted():
		victim = _first_living(rules.foes_of(owner) if rules != null else [])
	if victim == null or stored_slam == null:
		lines.append("%s's Decamating Slam has no target!" % owner.display_name)
		return
	releasing = true
	lines.append("%s unleashes Decamating Slam!" % owner.display_name)
	owner.queued_move = stored_slam
	owner.queued_target = victim


func _keep_monk_move(owner: Battler, move: MoveData, rules) -> bool:
	if phase == "angered":
		return move.move_name == "Heavy Staff Swing" or move.move_name == "Recover"
	if move.move_name == "Heavy Staff Swing" or move.move_name == "Recover":
		return false
	if move.move_name == "Meditate":
		return phase == "idle" or (phase == "enlightened" and _enemy_capped(owner, rules))
	return phase != "channeling"


func _enemy_capped(owner: Battler, rules) -> bool:
	if rules == null:
		return false
	for foe in rules.foes_of(owner):
		if int(foe.blessed_stacks) >= 3:
			return true
	return false


func _has_living_ally(owner: Battler, rules) -> bool:
	if rules == null:
		return false
	for ally in rules.allies_of(owner):
		var friend: Battler = ally
		if friend != owner and not friend.is_fainted() and not friend.is_summon():
			return true
	return false


func _skip_channel(owner: Battler, rules, lines: Array[String]) -> void:
	if phase != "channeling":
		return
	if _fail_channel(owner, rules, lines):
		return
	lines.append("%s continues meditating..." % owner.display_name)
	channel_left -= 1
	if channel_left <= 0:
		_become_enlightened(owner, lines)


func _fail_channel(owner: Battler, rules, lines: Array[String]) -> bool:
	if phase != "channeling" or not team_channel or rules == null:
		return false
	for ally in rules.allies_of(owner):
		var friend: Battler = ally
		if friend != owner and not friend.is_summon() and friend.is_fainted():
			lines.append("%s's Meditate fails as their ally falls!" % owner.display_name)
			_become_angered(owner, lines)
			return true
	return false


func _resolve_monk_action(owner: Battler, move: MoveData, target: Battler, rules, lines: Array[String]) -> void:
	if move == null:
		return
	if move.move_name == "Recover" and phase == "angered":
		_recover_anger(owner, lines)
		return
	if move.move_name != "Meditate":
		return
	if phase == "idle":
		_start_channel(owner, rules, lines)
	elif phase == "enlightened":
		_divine_blessing(owner, target, rules, lines)
	else:
		lines.append("%s's Meditate has no effect." % owner.display_name)


func _start_channel(owner: Battler, rules, lines: Array[String]) -> void:
	team_channel = _has_living_ally(owner, rules)
	phase = "channeling"
	channel_left = 2
	idle_hits = 0
	if team_channel:
		lines.append("%s begins Meditate and resists incoming damage!" % owner.display_name)
	else:
		lines.append("%s begins Meditate! Opponents are limited to disrupting moves." % owner.display_name)


func _become_enlightened(owner: Battler, lines: Array[String]) -> void:
	phase = "enlightened"
	channel_left = 0
	enlightened_left = 6
	_set_kind_suppressed(owner, "parry", true)
	dodge_active = true
	dodge_stacks = 0
	hit_stacks = 0
	dodge_idle = 0
	lines.append("%s reaches Perfect Enlightenment! Parry becomes Perfect Dodge." % owner.display_name)


func _end_enlightenment(owner: Battler, lines: Array[String]) -> void:
	phase = "idle"
	enlightened_left = 0
	dodge_active = false
	_set_kind_suppressed(owner, "parry", false)
	owner.cooldowns["Meditate"] = 1
	lines.append("%s's Perfect Enlightenment fades." % owner.display_name)


func _become_angered(owner: Battler, lines: Array[String]) -> void:
	phase = "angered"
	channel_left = 0
	enlightened_left = 0
	dodge_active = false
	_set_kind_suppressed(owner, "parry", true)
	_set_kind_suppressed(owner, "holy_split", true)
	_ensure_move(owner, MoveData.make("Heavy Staff Swing", Element.Id.PHYSICAL, 90, 70, false))
	_ensure_move(owner, MoveData.make("Recover", Element.Id.HOLY, 0, 100, true, "utility", 100, "cast", "self"))
	lines.append("%s is ANGERED! The monk kit is lost — only a heavy swing remains." % owner.display_name)


func _recover_anger(owner: Battler, lines: Array[String]) -> void:
	phase = "idle"
	idle_hits = 0
	_set_kind_suppressed(owner, "parry", false)
	_set_kind_suppressed(owner, "holy_split", false)
	_drop_move(owner, "Heavy Staff Swing")
	_drop_move(owner, "Recover")
	owner.cooldowns["Meditate"] = 1
	lines.append("%s steadies their breath and recovers their kit." % owner.display_name)


func _tick_enlightenment(owner: Battler, lines: Array[String]) -> void:
	if phase != "enlightened":
		return
	if enlightened_left <= 0:
		_end_enlightenment(owner, lines)
		return
	enlightened_left -= 1


func _tick_dodge(owner: Battler, lines: Array[String]) -> void:
	if not dodge_active or owner.is_fainted():
		return
	if dodge_stacks == 0 and hit_stacks == 0:
		dodge_idle = 0
		return
	dodge_idle += 1
	if dodge_idle >= 5:
		dodge_stacks = 0
		hit_stacks = 0
		dodge_idle = 0
		lines.append("%s's dodge chance resets to %d%%." % [owner.display_name, roundi(_dodge_chance() * 100.0)])


func _dodge_chance() -> float:
	var base := 0.20 if team_channel else 0.15
	var bonus := 0.10 if team_channel else 0.08
	var cap := 0.70 if team_channel else 0.50
	return clampf(base + float(dodge_stacks) * bonus - float(hit_stacks) * 0.05, 0.0, cap)


func _monk_connected(owner: Battler, target: Battler, move: MoveData, blocked: bool, lines: Array[String]) -> void:
	if phase == "idle" and _is_staff(move):
		idle_hits += 1
	if phase != "enlightened" or target == null or move == null:
		return
	if move.move_name == "Meditate" or move.move_name == "Heavy Staff Swing" or move.move_name == "Recover":
		return
	var amount := 2 if _is_staff(move) else 1
	if blocked:
		amount = int(amount / 2)
	_apply_blessed(target, amount, lines)


func _apply_blessed(target: Battler, amount: int, lines: Array[String]) -> void:
	if target == null or target.is_fainted() or amount <= 0:
		return
	var gained: int = target.add_blessed(amount, 3)
	if gained > 0:
		lines.append("%s gains Blessed (%d/3)!" % [target.display_name, target.blessed_stacks])


func _divine_blessing(owner: Battler, target: Battler, rules, lines: Array[String]) -> void:
	if target == null or target.blessed_stacks < 3:
		lines.append("%s's Divine Blessing has no effect." % owner.display_name)
		return
	var stacks: int = target.blessed_stacks
	target.blessed_stacks = 0
	var damage: int = maxi(1, 100 + roundi(float(target.max_hp) * 0.08))
	var actual: int = target.take_direct(damage)
	lines.append("%s unleashes Divine Blessing on %s, consuming %d Blessed for %d damage!" % [
		owner.display_name, target.display_name, stacks, actual
	])
	if not target.is_fainted():
		var threshold := 0.15 if team_channel else 0.10
		if float(target.hp) / float(maxi(1, target.max_hp)) < threshold:
			target.hp = 0
			lines.append("Divine Blessing executes %s!" % target.display_name)
	if target.is_fainted():
		lines.append("%s has fainted!" % target.display_name)
		if rules != null:
			rules._notify_faint(target, owner, null, lines)
	if phase == "enlightened":
		enlightened_left += 2
		lines.append("Enlightenment is extended! (%d turns remaining)" % enlightened_left)
	owner.cooldowns["Meditate"] = 1


func _set_kind_suppressed(owner: Battler, kind_name: String, value: bool) -> void:
	for passive in owner.passives:
		if str(passive.kind) == kind_name:
			passive.suppressed = value


func _ensure_move(owner: Battler, move: MoveData) -> void:
	if not owner.knows(move.move_name):
		owner.moves.append(move)


func _drop_move(owner: Battler, move_name: String) -> void:
	var kept: Array[MoveData] = []
	for move in owner.moves:
		if move.move_name != move_name:
			kept.append(move)
	owner.moves = kept


func _chain(first: Battler, enemies: Array, rules, lines: Array[String]) -> Array:
	var hits: Array = [first]
	var seen: Dictionary = {first: true}
	var current: Battler = first
	for _bounce in 5:
		if rules.rng.rand_int(1, 100) > 70:
			break
		var fresh: Array = []
		for neighbor in rules.adjacent_living(current, enemies):
			if not seen.has(neighbor):
				fresh.append(neighbor)
		if fresh.is_empty():
			break
		current = fresh[rules.rng.rand_int(0, fresh.size() - 1)]
		hits.append(current)
		seen[current] = true
		lines.append("Chain Lightning arcs to %s!" % current.display_name)
	return hits


func _try_chicken(owner: Battler, move: MoveData, damage_dealt: int, rules, lines: Array[String]) -> void:
	if rules == null or move == null or move.element != Element.Id.UNDEAD or damage_dealt <= 0:
		return
	if chicken != null and not chicken.is_fainted():
		return
	if randf() >= 0.30:
		return
	var peck := MoveData.make("Peck", Element.Id.UNDEAD, 25, 100, false)
	var kit: Array[MoveData] = [peck]
	chicken = Battler.create("Chicken Spirit", 40, 15, 8, 5, 8, 38, Element.Id.UNDEAD, owner.color, kit)
	chicken.sprite_id = "chicken"
	rules.summon_ally(owner, chicken, lines)


func _spark_mercy(owner: Battler, move: MoveData, damage_dealt: int, rules, lines: Array[String]) -> void:
	if rules == null or damage_dealt <= 0 or move == null or move.element != Element.Id.HOLY or move.targets != "enemy":
		return
	var lowest: Battler = null
	for ally in rules.allies_of(owner):
		var friend: Battler = ally
		if friend.is_fainted() or friend.is_summon():
			continue
		if lowest == null or friend.hp < lowest.hp:
			lowest = friend
	if lowest == null:
		return
	var amount: int = roundi(float(damage_dealt) * 0.30)
	var before: int = lowest.hp
	lowest.hp = mini(lowest.max_hp, lowest.hp + amount)
	var healed: int = lowest.hp - before
	if healed <= 0:
		return
	lines.append("%s's holy spark restores %d HP to %s!" % [owner.display_name, healed, lowest.display_name])
	for passive in lowest.passives:
		passive.on_healed(lowest, healed, lines)


func _palm_splash(owner: Battler, target: Battler, move: MoveData, damage_dealt: int, rules, lines: Array[String]) -> void:
	if splashing or rules == null or damage_dealt <= 0 or move == null or move.move_name != "Divine Palm":
		return
	var splash: int = roundi(float(damage_dealt) * 0.40)
	if splash <= 0:
		return
	splashing = true
	for neighbor in rules.adjacent_living(target, rules.opponents(owner)):
		var struck: Battler = neighbor
		var absorbed: int = mini(struck.shield_hp, splash)
		struck.shield_hp -= absorbed
		var leftover: int = splash - absorbed
		var actual := 0
		if leftover > 0:
			actual = struck.take_direct(leftover)
		if absorbed + actual > 0:
			lines.append("%s is clipped by Divine Palm for %d damage!" % [struck.display_name, absorbed + actual])
		if struck.is_fainted():
			lines.append("%s has fainted!" % struck.display_name)
			rules._notify_faint(struck, owner, move, lines)
	splashing = false


func _refresh_charge(owner: Battler, lines: Array[String]) -> void:
	var should := owner != null and not owner.is_fainted() and owner.hp * 2 < owner.max_hp
	if should and not charged:
		charged = true
		owner.speed += 15
		owner.magic_attack += 10
		lines.append("%s becomes charged! (+15 speed, +10 magic attack)" % owner.display_name)
	elif not should and charged:
		charged = false
		owner.speed -= 15
		owner.magic_attack -= 10
		lines.append("%s is no longer charged." % owner.display_name)


func _explode_shield(owner: Battler, rules, lines: Array[String]) -> void:
	explode_pending = false
	var damage: int = 50 + roundi(float(owner.max_hp) * 0.20)
	lines.append("%s's shattered shield explodes (%d damage)!" % [owner.display_name, damage])
	var boom := MoveData.make("Roar of the slayer", Element.Id.UNDEAD, 0, 100, true)
	for foe in rules.foes_of(owner):
		var enemy: Battler = foe
		if enemy.is_fainted():
			continue
		var actual: int = enemy.take_direct(damage)
		lines.append("%s took %d damage from the explosion!" % [enemy.display_name, actual])
		if enemy.is_fainted():
			lines.append("%s has fainted!" % enemy.display_name)
			rules._notify_faint(enemy, owner, boom, lines)


func _undead_sion(owner: Battler) -> Battler:
	var punch := MoveData.make("Punch", Element.Id.UNDEAD, 25, 100, false)
	var kit: Array[MoveData] = [punch]
	var risen := Battler.create("Undead Sion", 200, 30, 30, 0, 30, 45, Element.Id.UNDEAD, owner.color, kit)
	risen.sprite_id = "sion"
	return risen


func reset_set(owner: Battler) -> void:
	if kind == "set_warlord" and owner != null and set_applied != 0:
		owner.attack -= set_applied
		set_applied = 0
	elif kind == "set_sage":
		_clear_sage()
	elif kind == "set_bulwark":
		set_armed = true


func _bulwark(owner: Battler, lines: Array[String]) -> void:
	if owner == null or owner.is_fainted() or owner.max_hp <= 0:
		return
	var low := float(owner.hp) < float(owner.max_hp) * 0.5
	if not low:
		set_armed = true
		return
	if not set_armed:
		return
	var amount: int = int(round(float(owner.max_hp) * 0.40))
	if amount <= 0:
		return
	owner.shield_hp = amount
	set_armed = false
	lines.append("%s's Bulwark set raises a %d HP shield!" % [owner.display_name, amount])


func _warlord(owner: Battler, rules, lines: Array[String]) -> void:
	if owner == null:
		return
	if owner.is_fainted():
		if set_applied != 0:
			owner.attack -= set_applied
			set_applied = 0
		return
	var dead := 0
	for ally in rules.allies_of(owner):
		var friend: Battler = ally
		if friend == owner or friend.is_summon():
			continue
		if friend.is_fainted():
			dead += 1
	var percent := 0.0
	if dead >= 2:
		percent = 0.40
	elif dead >= 1:
		percent = 0.20
	var two := int(owner.set_two.get("attack", 0))
	var base := owner.attack - set_applied - two
	var wanted: int = int(round(float(maxi(0, base)) * percent))
	if wanted == set_applied:
		return
	owner.attack += wanted - set_applied
	set_applied = wanted
	if wanted > 0:
		lines.append("%s's Warlord set surges (+%d Attack)!" % [owner.display_name, wanted])


func _sage(owner: Battler, rules, lines: Array[String]) -> void:
	if owner == null or rules == null:
		_clear_sage()
		return
	var wanted := 0
	if not owner.is_fainted() and owner.max_hp > 0:
		var ratio := float(owner.hp) / float(owner.max_hp)
		if ratio < 0.50:
			wanted = 20
		elif ratio < 0.75:
			wanted = 10
	if wanted == set_applied and (wanted == 0 or not set_buffed.is_empty()):
		return
	_clear_sage()
	if wanted <= 0:
		return
	for ally in rules.allies_of(owner):
		var friend: Battler = ally
		if friend == owner or friend.is_fainted() or friend.is_summon():
			continue
		friend.speed += wanted
		set_buffed.append(friend)
	set_applied = wanted
	if not set_buffed.is_empty():
		lines.append("%s's Sage set quickens allies (+%d Speed)!" % [owner.display_name, wanted])


func _clear_sage() -> void:
	for ally in set_buffed:
		var friend: Battler = ally
		if friend != null:
			friend.speed = maxi(1, friend.speed - set_applied)
	set_buffed.clear()
	set_applied = 0


func _first_living(group: Array) -> Battler:
	for battler in group:
		var foe: Battler = battler
		if not foe.is_fainted():
			return foe
	return null
