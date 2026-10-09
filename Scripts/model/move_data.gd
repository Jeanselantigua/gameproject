class_name MoveData
extends RefCounted

## Java Move, trimmed to what the first battle scene resolves.
## anim is the presentation key the battle scene plays. It does not affect damage.

var move_name: String
var element: int
var power: int
var accuracy: int
var is_magic: bool
var status_id: String
var status_chance: int
var anim: String
var targets: String = "enemy"
var cooldown_turns: int = 0
var hits_all: bool = false
var min_hits: int = 1
var max_hits: int = 1
var priority: int = 0


static func make(
	move_name: String,
	element: int,
	power: int,
	accuracy: int,
	is_magic: bool,
	status_id: String = "",
	status_chance: int = 0,
	anim: String = "slash",
	targets: String = "enemy",
	cooldown_turns: int = 0,
	hits_all: bool = false,
	priority: int = 0
) -> MoveData:
	var move := MoveData.new()
	move.move_name = move_name
	move.element = element
	move.power = power
	move.accuracy = accuracy
	move.is_magic = is_magic
	move.status_id = status_id
	move.status_chance = status_chance
	move.anim = anim
	move.targets = targets
	move.cooldown_turns = cooldown_turns
	move.hits_all = hits_all
	move.priority = priority
	return move
