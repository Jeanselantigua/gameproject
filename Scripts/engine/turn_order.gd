class_name TurnOrder
extends RefCounted

## Java TurnOrderScheduler. Action value is 10000 / speed.
## Lower time acts first. Acting adds another delay.

const BASE_TICKS := 10000.0

var rng: BattleRng
var next_time: Dictionary = {}


func _init(combatants: Array[Battler], battle_rng: BattleRng) -> void:
	rng = battle_rng
	for battler in combatants:
		next_time[battler] = _delay_for(battler)


func next_actor() -> Battler:
	return _pick_next(next_time, true)


func advance_actor(battler: Battler) -> void:
	next_time[battler] = float(next_time[battler]) + _delay_for(battler)


func add_combatant(battler: Battler) -> void:
	var soonest := INF
	for time in next_time.values():
		soonest = minf(soonest, float(time))
	if soonest == INF:
		soonest = 0.0
	next_time[battler] = soonest + _delay_for(battler)


## Upcoming living actors. Each entry is {battler, time}.
func preview(count: int) -> Array:
	var upcoming: Array = []
	if count <= 0:
		return upcoming
	var simulated := next_time.duplicate()
	for _i in count:
		var nxt: Battler = _pick_next(simulated, false)
		if nxt == null:
			break
		var time := float(simulated[nxt])
		upcoming.append({"battler": nxt, "time": time})
		simulated[nxt] = time + _delay_for(nxt)
	return upcoming


func _delay_for(battler: Battler) -> float:
	return BASE_TICKS / float(maxi(1, battler.effective_speed()))


func _pick_next(times: Dictionary, random_ties: bool) -> Battler:
	var nxt: Battler = null
	var lowest := INF
	for key in times:
		var battler: Battler = key
		if battler.is_fainted():
			continue
		var time := float(times[key])
		if time < lowest:
			lowest = time
			nxt = battler
		elif time == lowest and random_ties and rng.rand_float() < 0.5:
			nxt = battler
	return nxt
