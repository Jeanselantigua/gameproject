class_name Party
extends RefCounted

var side: String
var members: Array[Battler] = []


func _init(side_name: String) -> void:
	side = side_name


func add(battler: Battler) -> void:
	battler.side = side
	members.append(battler)


func any_alive() -> bool:
	for battler in members:
		if not battler.is_fainted():
			return true
	return false


func living() -> Array[Battler]:
	var alive: Array[Battler] = []
	for battler in members:
		if not battler.is_fainted():
			alive.append(battler)
	return alive
