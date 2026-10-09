class_name Roster
extends RefCounted

## Playable kits from PlayableCharacters.
## Battle mode knows every non-ult move immediately. The ult is known and starts on its cooldown.
## Dungeon mode knows move 1 and learns the rest at levels 6, 12, and 18.
##
## Base stats live in STATS. Order is HP, Attack, Defense, Magic Attack, Magic Defense, Speed.
## "dungeon" is the climb. "arena" is the team fight. Change a number here and the fighter uses it.

const STATS := {
	"Mechanized Champion": {
		"dungeon": [120, 30, 20, 0, -10, 20],
		"arena": [200, 57, 37, 0, -20, 26],
	},
	"Rogue": {
		"dungeon": [100, 30, 10, 10, 15, 35],
		"arena": [200, 60, 20, 20, 30, 70],
	},
	"Roeseph": {
		"dungeon": [84, 23, 18, 20, 25, 15],
		"arena": [200, 45, 35, 40, 50, 30],
	},
	"Randy": {
		"dungeon": [94, 25, 35, 0, 20, 10],
		"arena": [220, 50, 70, 0, 40, 20],
	},
	"Chefromancer": {
		"dungeon": [85, 11, 10, 30, 33, 17],
		"arena": [200, 21, 20, 60, 65, 34],
	},
	"Okirik": {
		"dungeon": [100, 5, 14, 30, 20, 16],
		"arena": [230, 10, 28, 60, 40, 32],
	},
	"Banished Mage": {
		"dungeon": [96, 8, 18, 30, 20, 20],
		"arena": [210, 15, 35, 60, 40, 40],
	},
	"Sion": {
		"dungeon": [117, 13, 18, 10, 18, 8],
		"arena": [270, 25, 35, 20, 35, 15],
	},
	"Kozan": {
		"dungeon": [75, 25, 25, 30, 15, 15],
		"arena": [180, 50, 50, 30, 30, 60],
	},
}


static func ids() -> Array[String]:
	return [
		"Mechanized Champion",
		"Rogue",
		"Roeseph",
		"Randy",
		"Chefromancer",
		"Okirik",
		"Banished Mage",
		"Sion",
		"Kozan",
	]


static func spawn(id: String, for_pvp: bool) -> Battler:
	var kit := _kit(id)
	var stats: Array = kit.arena if for_pvp else kit.dungeon
	var kit_moves: Array[MoveData] = []
	for move in kit.moves:
		kit_moves.append(move)
	var known: Array[MoveData] = []
	if for_pvp:
		for move in kit_moves:
			known.append(move)
	else:
		known.append(kit_moves[0])
	var battler := Battler.create(
		id, int(stats[0]), int(stats[1]), int(stats[2]), int(stats[3]), int(stats[4]), int(stats[5]),
		int(kit.affinity), kit.color, known
	)
	battler.kit_moves = kit_moves
	battler.sprite_id = str(kit.sprite)
	battler.specialties = _specialties(id)
	for kind in kit.passives:
		var passive: KitPassive = KitPassive.new()
		passive.kind = str(kind)
		battler.passives.append(passive)
	if for_pvp and kit_moves.size() >= 4:
		var ult: MoveData = kit_moves[3]
		if ult.cooldown_turns > 0:
			battler.cooldowns[ult.move_name] = ult.cooldown_turns
	return battler


static func _specialties(id: String) -> Array[String]:
	var specs: Array[String] = []
	match id:
		"Mechanized Champion", "Sion":
			specs.assign(["hp", "defense"])
		"Rogue":
			specs.assign(["speed", "attack"])
		"Roeseph", "Kozan":
			specs.assign(["attack", "magic_attack"])
		"Randy":
			specs.assign(["hp", "attack"])
		"Chefromancer":
			specs.assign(["magic_attack", "magic_defense"])
		"Okirik":
			specs.assign(["magic_attack", "hp"])
		"Banished Mage":
			specs.assign(["magic_attack", "speed"])
	return specs


static func _kit(id: String) -> Dictionary:
	var stats: Dictionary = STATS.get(id, STATS["Kozan"])
	match id:
		"Mechanized Champion":
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.PHYSICAL,
				"color": Color("8aa0b8"),
				"sprite": "champion",
				"passives": ["champion_strength", "rage", "taunt", "will"],
				"moves": [
					_hit("Uplifting Slash", Element.Id.PHYSICAL, 35, 100, false, "paralysis", 35),
					_hit("Prideful Taunt", Element.Id.PHYSICAL, 0, 100, false, "self_shield", 0, "cast", "self"),
					_hit("Visceral Wound", Element.Id.PHYSICAL, 60, 100, false, "bleed", 100),
					_hit("The Will of Humanity", Element.Id.PHYSICAL, 0, 100, false, "", 0, "cast", "self", 3),
				],
			}
		"Rogue":
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.ARCANE,
				"color": Color("7c6bb5"),
				"sprite": "rogue",
				"passives": ["rogue_stealth", "rogue_momentum", "rogue_wound"],
				"moves": [
					_hit("BackStab", Element.Id.PHYSICAL, 30, 90, false),
					_hit("Ambush", Element.Id.PHYSICAL, 40, 95, false, "", 0, "slash", "enemy", 0, false, 1),
					_maim(),
					_hit("Assassinate", Element.Id.ARCANE, 65, 90, false, "", 0, "slash", "enemy", 2, false, 1),
				],
			}
		"Roeseph":
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.HOLY,
				"color": Color("e6c36a"),
				"sprite": "roeseph",
				"passives": ["holy_split", "parry", "enlightenment", "master", "divine_palm"],
				"moves": [
					_hit("Oochie", Element.Id.HOLY, 60, 100, false),
					_hit("Meditate", Element.Id.HOLY, 0, 100, true, "", 0, "cast", "enemy", 1),
					_hit("Divine Palm", Element.Id.HOLY, 40, 95, true),
					_hit("Master of Any Art", Element.Id.HOLY, 0, 100, true, "", 0, "cast", "enemy", 3),
				],
			}
		"Randy":
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.PHYSICAL,
				"color": Color("d4783a"),
				"sprite": "randy",
				"passives": ["frenzy", "accuracy"],
				"moves": [
					_hit("Bonk", Element.Id.PHYSICAL, 120, 60, false, "stun", 40, "slam"),
					_hit("Devour", Element.Id.PHYSICAL, 40, 90, false, "leech", 100),
					_hit("Rampage", Element.Id.PHYSICAL, 55, 80, false),
					_hit("Meteor Club", Element.Id.PHYSICAL, 140, 70, false, "stun", 60, "slam", "enemy", 3),
				],
			}
		"Chefromancer":
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.UNDEAD,
				"color": Color("c4a574"),
				"sprite": "chef",
				"passives": ["chicken", "slow_cook"],
				"moves": [
					_hit("Night of the living Bread", Element.Id.UNDEAD, 50, 90, true, "curse", 30),
					_hit("Siphon", Element.Id.UNDEAD, 35, 90, true, "siphon", 100),
					_hit("Food Poisoning", Element.Id.UNDEAD, 40, 90, true, "poison", 80),
					_hit("Grand Banquet", Element.Id.UNDEAD, 85, 90, true, "curse", 50, "bolt", "enemy", 3),
				],
			}
		"Okirik":
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.HOLY,
				"color": Color("f2efe6"),
				"sprite": "okirik",
				"passives": ["blessing", "spark_mercy"],
				"moves": [
					_hit("Heal", Element.Id.HOLY, 0, 100, true, "heal", 100, "cast", "ally"),
					_hit("Holy Spark", Element.Id.HOLY, 35, 100, true),
					_hit("Barrier", Element.Id.HOLY, 80, 100, true, "shield", 100, "cast", "ally"),
					_hit("Holy Nova", Element.Id.HOLY, 80, 100, true, "", 0, "bolt", "enemy", 3),
				],
			}
		"Banished Mage":
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.LIGHTNING,
				"color": Color("6eb6ff"),
				"sprite": "wewe",
				"passives": ["hunt", "charged", "storm"],
				"moves": [
					_hit("Bolt", Element.Id.LIGHTNING, 45, 95, true, "paralysis", 30),
					_hit("Static", Element.Id.LIGHTNING, 20, 90, true, "paralysis", 70),
					_hit("Chain Lightning", Element.Id.LIGHTNING, 35, 90, true, "paralysis", 40),
					_hit("Thunder God's Wrath", Element.Id.LIGHTNING, 75, 90, true, "paralysis", 50, "bolt", "enemy", 3, true),
				],
			}
		"Sion":
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.LIGHTNING,
				"color": Color("c45c4a"),
				"sprite": "sion",
				"passives": ["revive", "explode", "kill_hp", "slam"],
				"moves": [
					_hit("Decamating Slam", Element.Id.PHYSICAL, 45, 60, false, "stun", 100, "slam"),
					_hit("Roar of the slayer", Element.Id.UNDEAD, 100, 100, true, "self_shield", 100, "cast", "self"),
					_hit("Slow", Element.Id.PHYSICAL, 20, 90, false, "slow", 100),
					_hit("Unstoppable Onslaught", Element.Id.PHYSICAL, 100, 80, false, "stun", 100, "slam", "enemy", 3),
				],
			}
		"Kozan", _:
			return {
				"dungeon": stats.dungeon,
				"arena": stats.arena,
				"affinity": Element.Id.PHYSICAL,
				"color": Color("5ebeb0"),
				"sprite": "dual",
				"passives": ["dual_repeat", "status_reroll", "whirlwind"],
				"moves": [
					_hit("Thunderbolt", Element.Id.LIGHTNING, 30, 90, true, "slow", 15),
					_hit("Diagonal Strike", Element.Id.PHYSICAL, 25, 90, false, "bleed", 15),
					_hit("Lightning slash", Element.Id.LIGHTNING, 25, 90, false, "paralysis", 15),
					_hit("Electric Whirlwind", Element.Id.LIGHTNING, 40, 100, false, "paralysis", 100, "slash", "enemy", 4),
				],
			}


static func _maim() -> MoveData:
	var move := _hit("Maim", Element.Id.ARCANE, 5, 90, false, "wound", 15)
	move.min_hits = 2
	move.max_hits = 8
	return move


static func _hit(
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
	return MoveData.make(
		move_name, element, power, accuracy, is_magic,
		status_id, status_chance, anim, targets, cooldown_turns, hits_all, priority
	)
