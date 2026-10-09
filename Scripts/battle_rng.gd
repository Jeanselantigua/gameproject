class_name BattleRng
extends RefCounted

## Matches Java RandomProvider: nextInt is inclusive on both ends.

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func rand_float() -> float:
	return _rng.randf()


func rand_int(min_value: int, max_value: int) -> int:
	return _rng.randi_range(min_value, max_value)
