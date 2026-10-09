class_name DamageCalculator
extends RefCounted

## Java DamageCalculator.
## power * offense * scaling / defense, then STAB 1.5, type chart, 85-100% variance.

var chart: TypeChart
var rng: BattleRng


func _init(type_chart: TypeChart, battle_rng: BattleRng) -> void:
	chart = type_chart
	rng = battle_rng


func calculate(attacker: Battler, defender: Battler, move: MoveData) -> int:
	var power := attacker.effective_power(move)
	if power == 0:
		return 0

	var offense: int = attacker.magic_attack if move.is_magic else attacker.attack
	var defense: int = defender.magic_defense if move.is_magic else defender.defense
	var base: float = (float(power) * offense * attacker.move_scaling(move)) / float(maxi(1, defense))
	var stab: float = 1.5 if move.element == attacker.affinity else 1.0
	var type_multiplier: float = chart.multiplier(move.element, defender.affinity)
	var variance: float = rng.rand_int(85, 100) / 100.0
	return roundi(base * stab * type_multiplier * variance)
