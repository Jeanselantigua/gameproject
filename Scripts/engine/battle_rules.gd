class_name BattleRules
extends RefCounted

## Turn loop shared with the Java Battle / TurnResolver hit path.
## Status ticks follow StatusEffectResolver: siphon, wounds, then poison, bleed, curse, and slow.

const MAX_ACTIONS := 200

var player: Party
var enemy: Party
var rng: BattleRng
var order: TurnOrder
var damage: DamageCalculator
var actions := 0
var turn_notes: Array[String] = []


func _init(player_party: Party, enemy_party: Party, battle_rng: BattleRng = null) -> void:
	player = player_party
	enemy = enemy_party
	rng = battle_rng if battle_rng != null else BattleRng.new()
	var chart := TypeChart.new()
	damage = DamageCalculator.new(chart, rng)
	var everyone: Array[Battler] = []
	everyone.append_array(player.members)
	everyone.append_array(enemy.members)
	order = TurnOrder.new(everyone, rng)


func ongoing() -> bool:
	return player.any_alive() and enemy.any_alive() and actions < MAX_ACTIONS


func next_actor() -> Battler:
	return order.next_actor()


func advance(battler: Battler) -> void:
	order.advance_actor(battler)
	actions += 1


func foes_of(battler: Battler) -> Array[Battler]:
	var party := enemy if battler.side == "player" else player
	return party.living()


func team_of(battler: Battler) -> Array[Battler]:
	var party := player if battler.side == "player" else enemy
	var members: Array[Battler] = []
	members.assign(party.members)
	return members


func opponents(battler: Battler) -> Array[Battler]:
	var party := enemy if battler.side == "player" else player
	var members: Array[Battler] = []
	members.assign(party.members)
	return members


func adjacent_living(target: Battler, team: Array) -> Array:
	var adjacent: Array = []
	var index := team.find(target)
	if index < 0:
		return adjacent
	for slot in [index - 1, index + 1]:
		if slot < 0 or slot >= team.size():
			continue
		var neighbor: Battler = team[slot]
		if neighbor != null and neighbor != target and not neighbor.is_fainted():
			adjacent.append(neighbor)
	return adjacent


func summon_ally(summoner: Battler, summon: Battler, lines: Array[String]) -> void:
	summon.summoner = summoner
	_join(summoner, summon)
	lines.append("%s summons %s!" % [summoner.display_name, summon.display_name])


func add_ally(ally_of: Battler, member: Battler, lines: Array[String]) -> void:
	_join(ally_of, member)
	lines.append("%s rises to fight for %s's team!" % [member.display_name, ally_of.display_name])


func _join(ally_of: Battler, member: Battler) -> void:
	var party := player if ally_of.side == "player" else enemy
	party.add(member)
	order.add_combatant(member)


func allies_of(battler: Battler) -> Array[Battler]:
	var party := player if battler.side == "player" else enemy
	var allies: Array[Battler] = []
	allies.assign(party.members)
	return allies


func preview(count: int) -> Array:
	return order.preview(count)


func skip_if_stunned(actor: Battler) -> Array[String]:
	if actor.consume_queued_skip():
		return ["%s is paralyzed and can't move!" % actor.display_name]
	if actor.stunned:
		actor.stunned = false
		return ["%s is stunned and can't move!" % actor.display_name]
	if actor.has_effect("paralysis") and rng.rand_float() < 0.25:
		var extra: int = maxi(1, actor.effect_magnitude("paralysis"))
		if extra > 1:
			actor.queued_skips += extra - 1
		return ["%s is paralyzed and can't move!" % actor.display_name]
	return []


func skips_own_action(actor: Battler) -> bool:
	for passive in actor.passives:
		if passive.skips_own_action(actor):
			return true
	return false


func note_skipped_action(actor: Battler) -> Array[String]:
	var lines: Array[String] = []
	for passive in actor.passives:
		passive.on_action_skipped(actor, self, lines)
	return lines


func take_queued_action(actor: Battler) -> Dictionary:
	if actor.queued_move == null:
		return {}
	var move: MoveData = actor.queued_move
	var target: Battler = actor.queued_target
	actor.queued_move = null
	actor.queued_target = null
	return {"move": move, "target": target}


func notify_field() -> Array[String]:
	var lines: Array[String] = []
	_faint_orphans(player, lines)
	_faint_orphans(enemy, lines)
	var everyone: Array[Battler] = []
	everyone.append_array(player.members)
	everyone.append_array(enemy.members)
	for battler in everyone:
		for passive in battler.passives:
			passive.on_field_changed(battler, self, lines)
	return lines


func begin_turn(actor: Battler) -> Array[MoveData]:
	turn_notes = []
	_tick_statuses(actor, turn_notes)
	if actor.is_fainted():
		return []
	actor.tick_cooldowns()
	for passive in actor.passives:
		passive.on_turn_start(actor, turn_notes, self)
	var ready: Array = actor.available_moves()
	for passive in actor.passives:
		ready = passive.filter_moves(actor, ready, self)
	for foe in foes_of(actor):
		for passive in foe.passives:
			ready = passive.restrict_opponent(foe, actor, ready)
	var offered: Array[MoveData] = []
	for move in ready:
		offered.append(move)
	return offered


func aggro_target(actor: Battler) -> Battler:
	for foe in foes_of(actor):
		if foe.forces_aggro():
			return foe
	return null


func ai_choice(actor: Battler, ready: Array[MoveData]) -> Dictionary:
	if ready.is_empty():
		return {}
	var allies := _living(allies_of(actor))
	var heal := _move_with_status(ready, "heal")
	if heal != null:
		var patient := _lowest_ratio(allies)
		if patient != null and float(patient.hp) / float(maxi(1, patient.max_hp)) < 0.45:
			return {"move": heal, "target": patient}
	var taunt := _move_named(ready, "Prideful Taunt")
	if taunt != null and not _is_taunting(actor) and _has_other_ally(actor, allies):
		return {"move": taunt, "target": actor}
	var shield := _move_with_status(ready, "shield")
	if shield != null:
		if shield.targets == "self" and actor.shield_hp <= 0:
			return {"move": shield, "target": actor}
		if shield.targets == "ally":
			var bare := _lowest_without_shield(allies)
			if bare != null:
				return {"move": shield, "target": bare}
	var offense: Array[MoveData] = []
	for move in ready:
		if move.targets == "enemy":
			offense.append(move)
	var foes := foes_of(actor)
	if foes.is_empty():
		return {}
	var forced := aggro_target(actor)
	if offense.is_empty():
		return {"move": ready[0], "target": actor}
	var chosen: MoveData = offense[0]
	var best := -1.0
	for move in offense:
		var score: float = float(move.power * move.accuracy) / 100.0
		if move.hits_all:
			score *= float(foes.size())
		if move.move_name == "Meditate":
			for passive in actor.passives:
				if str(passive.kind) != "enlightenment":
					continue
				if str(passive.phase) == "enlightened":
					score = 100000.0
				elif str(passive.phase) == "idle" and (int(passive.idle_hits) >= 2 or allies.size() > 1):
					score = 8000.0
		if score > best:
			best = score
			chosen = move
	var target: Battler = forced if forced != null and not chosen.hits_all else _lowest_ratio(foes)
	return {"move": chosen, "target": target}


func resolve(actor: Battler, move: MoveData, target: Battler) -> Dictionary:
	var lines: Array[String] = []
	var events: Array = []
	var chosen := move
	var acting := move
	for passive in actor.passives:
		var rewritten: MoveData = passive.rewrite_move(actor, chosen, target, lines)
		if rewritten != null:
			acting = rewritten
	lines.append("%s uses %s!" % [actor.display_name, acting.move_name])
	if acting.targets != "enemy":
		_resolve_support(actor, acting, target, lines, events)
	else:
		var chosen_targets: Array = foes_of(actor) if acting.hits_all else _one(target)
		for passive in actor.passives:
			chosen_targets = passive.expand_targets(actor, acting, chosen_targets, self, lines)
		var victims := _as_battlers(chosen_targets)
		_resolve_attack(actor, acting, victims, lines, events)
		var follow: MoveData = null
		for passive in actor.passives:
			var extra: MoveData = passive.follow_up(actor, acting, lines)
			if extra != null:
				follow = extra
		if follow != null:
			_resolve_attack(actor, follow, victims, lines, events)
		var repeat := false
		if not actor.is_fainted():
			for passive in actor.passives:
				if passive.should_repeat(actor, acting, lines):
					repeat = true
		if repeat:
			_resolve_attack(actor, acting, victims, lines, events)
			if follow != null:
				_resolve_attack(actor, follow, victims, lines, events)
	var cooling := true
	for passive in actor.passives:
		if passive.defer_cooldown(chosen):
			cooling = false
	if cooling:
		actor.start_cooldown(chosen)
	for passive in actor.passives:
		passive.on_action_resolved(actor, chosen, lines, target, self)
	return {"actor": actor, "move": acting, "lines": lines, "events": events}


func _one(target: Battler) -> Array:
	var victims: Array = []
	if target != null:
		victims.append(target)
	return victims


func _as_battlers(group: Array) -> Array[Battler]:
	var victims: Array[Battler] = []
	for item in group:
		victims.append(item)
	return victims


func _resolve_attack(actor: Battler, move: MoveData, victims: Array[Battler], lines: Array[String], events: Array) -> void:
	var hits := move.min_hits
	if move.max_hits > move.min_hits:
		hits = rng.rand_int(move.min_hits, move.max_hits)
	if hits > 1:
		lines.append("%s strikes %d times!" % [move.move_name, hits])
	for _hit_index in hits:
		for victim in victims:
			if actor.is_fainted() or victim == null or victim.is_fainted():
				continue
			_resolve_hit(actor, move, victim, lines, events)


func _resolve_support(actor: Battler, move: MoveData, target: Battler, lines: Array[String], events: Array) -> void:
	var recipient: Battler = actor if move.targets == "self" or target == null else target
	if move.status_id == "self_shield":
		recipient = actor
	if move.status_id == "heal":
		var scaling := actor.move_scaling(move)
		if scaling <= 0.0:
			scaling = 1.0
		var amount: int = roundi(float(recipient.max_hp) * 0.25 * scaling)
		var healed := _heal(recipient, amount)
		lines.append("%s recovers %d HP!" % [recipient.display_name, healed])
		_notify_healed(actor, recipient, healed, lines)
		events.append({"kind": "heal", "target": recipient, "damage": healed, "crit": false, "fainted": false, "stunned": false})
		return
	if move.status_id == "shield" or move.status_id == "self_shield":
		var shield: int = actor.effective_power(move)
		if move.status_chance > 0 and shield > 0:
			recipient.shield_hp = shield
			lines.append("%s gains a %d HP shield!" % [recipient.display_name, shield])
		events.append({"kind": "shield", "target": recipient, "damage": shield, "crit": false, "fainted": false, "stunned": false})
		return
	if move.move_name == "Meditate":
		lines.append("%s meditates." % actor.display_name)
	events.append({"kind": "cast", "target": recipient, "damage": 0, "crit": false, "fainted": false, "stunned": false})


func _resolve_hit(actor: Battler, move: MoveData, target: Battler, lines: Array[String], events: Array) -> void:
	var accuracy: int = move.accuracy
	for passive in actor.passives:
		accuracy = passive.modify_accuracy(actor, move, accuracy, target)
	for passive in target.passives:
		accuracy = passive.modify_incoming_accuracy(target, accuracy, move)
	accuracy = clampi(accuracy, 0, 100)
	if rng.rand_int(1, 100) > accuracy:
		if accuracy < move.accuracy:
			lines.append("%s dodges the attack!" % target.display_name)
		else:
			lines.append("Missed %s!" % target.display_name)
		for passive in actor.passives:
			passive.on_attack_missed(actor, move, lines)
		events.append({"kind": "miss", "target": target, "damage": 0, "crit": false, "fainted": false, "stunned": false})
		return
	for passive in target.passives:
		if passive.roll_dodge(target, actor, move):
			passive.on_dodged(target, actor, move, self, lines)
			events.append({"kind": "miss", "target": target, "damage": 0, "crit": false, "fainted": target.is_fainted(), "stunned": false})
			return

	var rate: int = actor.crit_rate
	for passive in actor.passives:
		rate = passive.modify_crit_rate(actor, move, rate)
	var is_crit: bool = rate > 0 and rng.rand_float() * 100.0 < float(rate)
	var crit_mult := _crit_multiplier(actor, move)
	var amount_f: float = float(damage.calculate(actor, target, move))
	if is_crit:
		amount_f *= crit_mult
	for passive in actor.passives:
		amount_f = passive.modify_outgoing(actor, target, move, amount_f, is_crit, crit_mult, lines)
	var before_incoming := amount_f
	for passive in target.passives:
		amount_f = passive.modify_incoming(target, actor, move, amount_f, lines)
	for ally in allies_of(target):
		for passive in ally.passives:
			amount_f = passive.modify_incoming_to_ally(ally, target, amount_f, lines)
	if actor.is_fainted():
		_notify_faint(actor, target, move, lines)

	var blocked := before_incoming > 0.0 and amount_f <= 0.0
	var amount: int = roundi(maxf(0.0, amount_f))
	var hp_loss := 0
	var applied_stun := false
	var noted_faint := false
	if amount > 0:
		hp_loss = _damage_through_shield(target, actor, amount, lines)
		if hp_loss > 0:
			var crit_note: String = " Critical hit!" if is_crit else ""
			lines.append("%s took %d damage!%s" % [target.display_name, hp_loss, crit_note])
			for passive in target.passives:
				passive.on_damage_taken(target, hp_loss, lines)
			if not target.is_fainted():
				applied_stun = _try_status(actor, move, target, hp_loss, lines)
			for passive in actor.passives:
				passive.on_hit_landed(actor, target, move, hp_loss, is_crit, lines, self)
			if target.hp <= 0:
				lines.append("%s has fainted!" % target.display_name)
				noted_faint = true
				_notify_faint(target, actor, move, lines)
	elif amount <= 0:
		lines.append("%s took no damage." % target.display_name)
	var standing: bool = target.hp > 0

	for passive in actor.passives:
		passive.on_attack_connected(actor, target, move, is_crit, lines, blocked)
	if target.hp <= 0 and (not noted_faint or standing):
		lines.append("%s has fainted!" % target.display_name)
		_notify_faint(target, actor, move, lines)

	events.append({
		"kind": "hit",
		"target": target,
		"damage": hp_loss,
		"crit": is_crit,
		"fainted": target.is_fainted(),
		"stunned": applied_stun,
	})


func _notify_faint(victim: Battler, killer: Battler, move: MoveData, lines: Array[String]) -> void:
	if victim == null:
		return
	for passive in victim.passives:
		passive.on_faint(victim, lines, self)
	if killer != null and not killer.is_fainted() and killer != victim:
		for passive in killer.passives:
			passive.on_kill(killer, victim, self, lines)


func _status_suppressed(actor: Battler, target: Battler) -> bool:
	for passive in actor.passives:
		if passive.skips_status(target):
			return true
	return false


func _try_status(actor: Battler, move: MoveData, target: Battler, hp_loss: int, lines: Array[String]) -> bool:
	var status_id := move.status_id
	if status_id == "" or status_id == "heal" or status_id == "shield" or status_id == "self_shield":
		return false
	if _status_suppressed(actor, target):
		return false
	if status_id == "leech":
		if not actor.is_fainted():
			var stolen: int = roundi(float(hp_loss) * 0.25)
			var healed := _heal(actor, stolen)
			if healed > 0:
				lines.append("%s leeches %d HP!" % [actor.display_name, healed])
				for passive in actor.passives:
					passive.on_healed(actor, healed, lines)
		return false
	if not _roll_status(actor, move, target, lines):
		return false
	if status_id == "siphon":
		target.apply_siphon(actor, 3)
		lines.append("%s is being siphoned!" % target.display_name)
		return false
	if status_id == "wound":
		target.add_wound()
		lines.append("%s is wounded (%d)!" % [target.display_name, target.wound_stacks])
		return false
	if status_id == "stun":
		if target.is_immune(status_id):
			lines.append("%s shrugs off %s!" % [target.display_name, status_id])
			return false
		target.stunned = true
		lines.append("%s is stunned!" % target.display_name)
		for passive in target.passives:
			passive.on_status_received(target, status_id, actor, lines)
		return true
	if target.is_immune(status_id):
		lines.append("%s shrugs off %s!" % [target.display_name, status_id])
		return false
	var magnitude := 0
	if status_id == "bleed":
		magnitude = actor.attack
		for passive in actor.passives:
			magnitude = passive.modify_status_magnitude(actor, target, status_id, magnitude, lines)
	var result := target.apply_effect(status_id, magnitude, _status_duration(status_id))
	if result == "stacked":
		lines.append("%s's %s intensifies!" % [target.display_name, status_id])
	else:
		lines.append("%s is now %s!" % [target.display_name, status_id])
	for passive in target.passives:
		passive.on_status_received(target, status_id, actor, lines)
	return false


func _crit_multiplier(actor: Battler, move: MoveData) -> float:
	var bonus := 0
	for passive in actor.passives:
		bonus += passive.crit_damage_bonus(move, actor)
	return 1.0 + float(actor.crit_damage + bonus) / 100.0


func _move_with_status(options: Array[MoveData], status_id: String) -> MoveData:
	for move in options:
		if move.status_id == status_id:
			return move
	return null


func _move_named(options: Array[MoveData], move_name: String) -> MoveData:
	for move in options:
		if move.move_name == move_name:
			return move
	return null


func _is_taunting(actor: Battler) -> bool:
	for passive in actor.passives:
		if str(passive.kind) == "taunt" and int(passive.taunt_turns) > 0:
			return true
	return false


func _has_other_ally(actor: Battler, allies: Array[Battler]) -> bool:
	for ally in allies:
		if ally != actor:
			return true
	return false


func _lowest_without_shield(group: Array[Battler]) -> Battler:
	var picked: Battler = null
	var lowest := 2.0
	for battler in group:
		if battler.shield_hp > 0:
			continue
		var ratio: float = float(battler.hp) / float(maxi(1, battler.max_hp))
		if ratio < lowest:
			lowest = ratio
			picked = battler
	return picked


func _living(group: Array[Battler]) -> Array[Battler]:
	var alive: Array[Battler] = []
	for battler in group:
		if not battler.is_fainted():
			alive.append(battler)
	return alive


func _lowest_ratio(group: Array[Battler]) -> Battler:
	var picked: Battler = null
	var lowest := 2.0
	for battler in group:
		var ratio: float = float(battler.hp) / float(maxi(1, battler.max_hp))
		if ratio < lowest:
			lowest = ratio
			picked = battler
	return picked


func _tick_statuses(actor: Battler, lines: Array[String]) -> void:
	if actor.is_fainted():
		return
	_tick_siphon(actor, lines)
	if actor.is_fainted():
		return
	if actor.tick_wounds():
		lines.append("%s is no longer wounded!" % actor.display_name)
	var ids: Array = actor.effects.keys()
	for status_id in ids:
		if actor.is_fainted():
			return
		var key := str(status_id)
		if not actor.has_effect(key):
			continue
		var damage := _dot_amount(actor, key)
		if damage > 0:
			var actual := _damage_through_shield(actor, null, damage, lines)
			if actual > 0:
				lines.append("%s takes %d damage from %s!" % [actor.display_name, actual, key])
			if actor.is_fainted():
				lines.append("%s has fainted!" % actor.display_name)
				_notify_faint(actor, null, null, lines)
		if actor.effect_turns(key) > 0 and _decrement_effect(actor, key):
			lines.append(_expired_line(actor, key))


func _tick_siphon(actor: Battler, lines: Array[String]) -> void:
	if not actor.is_siphoned():
		return
	var damage: int = roundi(float(actor.max_hp) * 0.08)
	var source: Battler = actor.siphon_source
	if damage > 0:
		var actual := _damage_through_shield(actor, source, damage, lines)
		if actual > 0:
			lines.append("%s takes %d damage from siphon!" % [actor.display_name, actual])
		if source != null and not source.is_fainted():
			var stolen: int = roundi(float(actual) * 0.50)
			var healed := _heal(source, stolen)
			if healed > 0:
				lines.append("%s siphons %d HP from %s!" % [source.display_name, healed, actor.display_name])
				for passive in source.passives:
					passive.on_healed(source, healed, lines)
		if actor.is_fainted():
			lines.append("%s has fainted!" % actor.display_name)
			_notify_faint(actor, source, null, lines)
	if actor.tick_siphon():
		lines.append("%s is no longer siphoned!" % actor.display_name)


func _dot_amount(actor: Battler, status_id: String) -> int:
	var effectiveness := actor.effect_effectiveness(status_id)
	match status_id:
		"burn":
			return roundi(float(actor.max_hp) * 0.10 * effectiveness)
		"poison":
			return roundi(float(actor.max_hp) * 0.08 * effectiveness)
		"bleed":
			return roundi(float(actor.effect_magnitude("bleed")) * 0.40 * effectiveness)
		"curse":
			return roundi(float(actor.magic_attack) * 0.15 * effectiveness)
		_:
			return 0


func _decrement_effect(actor: Battler, status_id: String) -> bool:
	if not actor.has_effect(status_id):
		return false
	var current: Dictionary = actor.effects[status_id]
	var left: int = int(current.turns)
	if left <= 0:
		return false
	left -= 1
	current.turns = left
	actor.effects[status_id] = current
	if left == 0:
		actor.clear_effect(status_id)
		return true
	return false


func _expired_line(actor: Battler, status_id: String) -> String:
	match status_id:
		"burn":
			return "%s is no longer burning!" % actor.display_name
		"poison":
			return "%s is no longer poisoned!" % actor.display_name
		"bleed":
			return "%s is no longer bleeding!" % actor.display_name
		"curse":
			return "%s is no longer cursed!" % actor.display_name
		"slow":
			return "%s is no longer slowed!" % actor.display_name
		"paralysis":
			return "%s is no longer paralyzed!" % actor.display_name
		_:
			return "%s is no longer %s!" % [actor.display_name, status_id]


func _status_duration(status_id: String) -> int:
	match status_id:
		"curse", "burn", "poison", "bleed", "paralysis", "slow", "siphon":
			return 3
		"wound":
			return 2
		_:
			return 0


func _roll_status(actor: Battler, move: MoveData, target: Battler, lines: Array[String]) -> bool:
	if rng.rand_int(1, 100) <= move.status_chance:
		return true
	for passive in actor.passives:
		if passive.should_reroll_status(actor, target, move, lines):
			return rng.rand_int(1, 100) <= move.status_chance
	return false


func _damage_through_shield(target: Battler, attacker: Battler, amount: int, lines: Array[String]) -> int:
	var absorbed: int = mini(target.shield_hp, amount)
	if absorbed > 0:
		target.shield_hp -= absorbed
		lines.append("%s's shield absorbs %d damage!" % [target.display_name, absorbed])
		if target.shield_hp <= 0:
			lines.append("%s's shield shatters!" % target.display_name)
			for passive in target.passives:
				passive.on_shield_broken(target, attacker, self, lines)
	var leftover: int = amount - absorbed
	if leftover <= 0:
		return 0
	target.hp = maxi(0, target.hp - leftover)
	return leftover


func _heal(battler: Battler, amount: int) -> int:
	if battler == null or amount <= 0 or battler.is_fainted():
		return 0
	var before := battler.hp
	battler.hp = mini(battler.max_hp, battler.hp + amount)
	return battler.hp - before


func _notify_healed(actor: Battler, recipient: Battler, healed: int, lines: Array[String]) -> void:
	for passive in actor.passives:
		passive.on_ally_healed(actor, recipient, healed, lines)
	for passive in recipient.passives:
		passive.on_healed(recipient, healed, lines)


func _faint_orphans(party: Party, lines: Array[String]) -> void:
	for member in party.members:
		if not member.is_summon() or member.is_fainted():
			continue
		if member.summoner == null or member.summoner.is_fainted():
			member.hp = 0
			lines.append("%s fades away!" % member.display_name)


func winner_text() -> String:
	if player.any_alive() and not enemy.any_alive():
		return "Your team wins."
	if enemy.any_alive() and not player.any_alive():
		return "The enemy team wins."
	return "The battle ends in a draw."
