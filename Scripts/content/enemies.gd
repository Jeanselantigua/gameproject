class_name Enemies
extends RefCounted

## 100-floor dungeon. Every 20 floors the road changes biome, enemies, and backdrop.
## Floors 13-19 of a biome mix in an elite. Floor 20 of each biome is a boss.
## Stats climb every floor inside a biome, then step up again when the biome changes.
## Opening floor is 0.85. Solo and duo parties still fight a lighter version.


const FLOORS := 100
const BLOCK := 20
const ROOMS := FLOORS


static func biome_index(room: int) -> int:
	return int(clampi(room, 0, FLOORS - 1) / float(BLOCK))


static func is_boss_floor(room: int) -> bool:
	return (clampi(room, 0, FLOORS - 1) % BLOCK) == BLOCK - 1


static func scale_for(room: int, party_size: int) -> float:
	var floor := clampi(room, 0, FLOORS - 1)
	var within := float(floor % BLOCK) / float(BLOCK - 1)
	var base := 0.85 + float(biome_index(room)) * 0.20 + within * 0.16
	if party_size <= 1:
		return base * 0.75
	if party_size == 2:
		return base * 0.90
	return base


static func background_for(room: int) -> Texture2D:
	var path := str(_biome(room).background)
	if not ResourceLoader.exists(path):
		path = "res://Art/forest_road.jpg"
	return load(path)


static func room_blurb(room: int) -> String:
	var biome := _biome(room)
	var slot := (clampi(room, 0, FLOORS - 1) % BLOCK) + 1
	if slot == BLOCK:
		return str(biome.boss_blurb)
	if slot == 1:
		return str(biome.enter)
	return str(biome.blurb)


static func for_room(room: int, heroes: int) -> Array[Battler]:
	var biome := _biome(room)
	var slot := (clampi(room, 0, FLOORS - 1) % BLOCK) + 1
	var normals: Array = biome.normals
	var ids: Array[String] = []
	if slot == BLOCK:
		ids.append(str(biome.boss))
		if heroes >= 3:
			ids.append(_pick(normals))
	elif slot >= 13:
		ids.append(_pick(normals))
		ids.append(str(biome.elite))
		if heroes >= 3:
			ids.append(_pick(normals))
	else:
		ids.append(_pick(normals))
		ids.append(_pick(normals))
		if heroes >= 3:
			ids.append(_pick(normals))
	return _group(ids, scale_for(room, heroes))


static func _biomes() -> Array:
	return [
		{
			"enter": "Slimes puddle across the forest road.",
			"blurb": "The trees crowd the road.",
			"boss_blurb": "The grove warden blocks the end of the path.",
			"background": "res://Art/forest_road.jpg",
			"normals": ["slime", "wolf", "thornling", "bat"],
			"elite": "alpha_wolf",
			"boss": "warden",
		},
		{
			"enter": "The trees give way to broken stone.",
			"blurb": "Goblins and bones pick through the ruins.",
			"boss_blurb": "The goblin king holds the causeway.",
			"background": "res://Art/backgrounds/ruins.jpg",
			"normals": ["goblin", "spider", "sword_skeleton", "bow_skeleton"],
			"elite": "orc",
			"boss": "goblin_king",
		},
		{
			"enter": "The road drops into a crypt.",
			"blurb": "The dead do not stay down here.",
			"boss_blurb": "A cave brute bars the tomb.",
			"background": "res://Art/backgrounds/crypt.jpg",
			"normals": ["ghoul", "ice_slime", "sword_skeleton", "bow_skeleton"],
			"elite": "greater_ghoul",
			"boss": "hulk",
		},
		{
			"enter": "The crypt opens onto a burning caldera.",
			"blurb": "Heat shimmers over the lava path.",
			"boss_blurb": "The fire dragon uncoils.",
			"background": "res://Art/backgrounds/caldera.jpg",
			"normals": ["magma_slime", "earth_slime", "spider"],
			"elite": "fire_spirit",
			"boss": "dragon",
		},
		{
			"enter": "The climb breaks into a thunderstorm.",
			"blurb": "Lightning hunts along the ridge.",
			"boss_blurb": "The fastest man alive is already moving.",
			"background": "res://Art/backgrounds/storm.jpg",
			"normals": ["lightning_slime", "wolf", "bat"],
			"elite": "storm_wolf",
			"boss": "fastest",
		},
	]


static func _biome(room: int) -> Dictionary:
	var biomes := _biomes()
	return biomes[mini(biome_index(room), biomes.size() - 1)]


static func _pick(pool: Array) -> String:
	return str(pool[randi() % pool.size()])


static func _group(ids: Array[String], scale: float) -> Array[Battler]:
	var foes: Array[Battler] = []
	for id in ids:
		foes.append(_spawn(id, scale))
	var counts: Dictionary = {}
	for battler in foes:
		var base := battler.display_name
		counts[base] = int(counts.get(base, 0)) + 1
	var seen: Dictionary = {}
	for battler in foes:
		var base := battler.display_name
		if int(counts.get(base, 0)) < 2:
			continue
		var number := int(seen.get(base, 0)) + 1
		seen[base] = number
		battler.display_name = "%s %d" % [base, number]
	return foes


static func _spawn(id: String, scale: float) -> Battler:
	var kit: Dictionary = _kit(id)
	var stats: Array = kit.stats
	var moves: Array[MoveData] = []
	for move in kit.moves:
		moves.append(move)
	var xp := int(kit.xp)
	var used := scale
	var rank := "normal"
	if xp >= 750:
		rank = "boss"
		used *= 1.12
	elif xp >= 200:
		rank = "elite"
		used *= 1.06
	var battler := Battler.create(
		str(kit.name),
		_scaled_stat(int(stats[0]), used, 1),
		_scaled_stat(int(stats[1]), used, 0),
		_scaled_stat(int(stats[2]), used, 0),
		_scaled_stat(int(stats[3]), used, 0),
		_scaled_stat(int(stats[4]), used, 0),
		_scaled_stat(int(stats[5]), used, 1),
		int(kit.affinity), kit.color, moves
	)
	battler.rank = rank
	battler.sprite_id = str(kit.sprite)
	battler.bounty = maxi(1, roundi(float(xp) * scale))
	if kit.has("tint"):
		battler.sprite_tint = kit.tint
	if kit.has("immunities"):
		for status_id in kit.immunities:
			battler.immunities.append(str(status_id))
	if kit.has("passives"):
		for kind in kit.passives:
			var passive := KitPassive.new()
			passive.kind = str(kind)
			battler.passives.append(passive)
	return battler


static func _scaled_stat(base: int, scale: float, floor_value: int) -> int:
	return maxi(floor_value, roundi(float(base) * scale))


static func _kit(id: String) -> Dictionary:
	match id:
		"wolf":
			return {
				"name": "Wolf",
				"sprite": "wolf",
				"stats": [58, 16, 12, 0, 8, 20],
				"affinity": Element.Id.PHYSICAL,
				"color": Color("8a7560"),
				"xp": 100,
				"moves": [
					_hit("Bite", Element.Id.PHYSICAL, 26, 95, false),
					_hit("Snarl", Element.Id.PHYSICAL, 8, 90, false, "slow", 60),
				],
			}
		"alpha_wolf":
			return {
				"name": "Alpha Wolf",
				"sprite": "wolf",
				"stats": [140, 30, 16, 0, 12, 24],
				"affinity": Element.Id.PHYSICAL,
				"color": Color("6e5a42"),
				"xp": 200,
				"moves": [
					_hit("Bite", Element.Id.PHYSICAL, 34, 95, false),
					_hit("Howl", Element.Id.PHYSICAL, 10, 90, false, "slow", 80),
				],
			}
		"thornling":
			return {
				"name": "Thornling",
				"sprite": "thornling",
				"stats": [50, 10, 16, 18, 14, 11],
				"affinity": Element.Id.MONSTER,
				"color": Color("5a8f3a"),
				"xp": 100,
				"moves": [
					_hit("Thorns", Element.Id.EARTH, 22, 95, true),
					_hit("Tangle", Element.Id.EARTH, 10, 90, true, "slow", 70),
				],
			}
		"bat":
			return {
				"name": "Shade Bat",
				"sprite": "bat",
				"stats": [36, 14, 8, 10, 10, 26],
				"affinity": Element.Id.SHADOW,
				"color": Color("6a4a78"),
				"xp": 100,
				"moves": [
					_hit("Dive", Element.Id.SHADOW, 20, 95, false),
					_hit("Screech", Element.Id.SHADOW, 8, 85, true, "paralysis", 40),
				],
			}
		"goblin":
			return {
				"name": "Goblin",
				"sprite": "goblin",
				"stats": [60, 15, 15, 0, 10, 25],
				"affinity": Element.Id.MONSTER,
				"color": Color("6a8f45"),
				"xp": 100,
				"moves": [
					_hit("Jab", Element.Id.PHYSICAL, 20, 100, false),
				],
			}
		"spider":
			return {
				"name": "Spider",
				"sprite": "spider",
				"stats": [80, 20, 20, 0, 15, 20],
				"affinity": Element.Id.PHYSICAL,
				"color": Color("5c4038"),
				"xp": 100,
				"moves": [
					_hit("Web", Element.Id.PHYSICAL, 20, 100, false, "slow", 100),
					_hit("Poison Strike", Element.Id.PHYSICAL, 20, 100, false, "poison", 80),
				],
			}
		"ice_slime":
			return {
				"name": "Ice Slime",
				"sprite": "slime",
				"tint": Color(0.65, 0.9, 1.35),
				"stats": [50, 20, 25, 0, 10, 15],
				"affinity": Element.Id.ICE,
				"color": Color("8ec8e8"),
				"xp": 100,
				"moves": [
					_hit("Bounce", Element.Id.ICE, 20, 100, false, "slow", 75),
				],
			}
		"magma_slime":
			return {
				"name": "Magma Slime",
				"sprite": "slime",
				"tint": Color(1.35, 0.62, 0.4),
				"stats": [50, 20, 25, 0, 10, 15],
				"affinity": Element.Id.FIRE,
				"color": Color("e07040"),
				"xp": 100,
				"moves": [
					_hit("Bounce", Element.Id.FIRE, 20, 100, false, "burn", 75),
				],
			}
		"earth_slime":
			return {
				"name": "Earth Slime",
				"sprite": "slime",
				"tint": Color(0.85, 0.72, 0.4),
				"stats": [50, 20, 25, 0, 10, 15],
				"affinity": Element.Id.EARTH,
				"color": Color("8a7040"),
				"xp": 100,
				"moves": [
					_hit("Bounce", Element.Id.EARTH, 20, 100, false, "poison", 75),
				],
			}
		"lightning_slime":
			return {
				"name": "Lightning Slime",
				"sprite": "slime",
				"tint": Color(0.75, 0.9, 1.45),
				"stats": [50, 20, 25, 0, 10, 15],
				"affinity": Element.Id.LIGHTNING,
				"color": Color("d8e26a"),
				"xp": 100,
				"moves": [
					_hit("Bounce", Element.Id.LIGHTNING, 20, 100, false, "paralysis", 75),
				],
			}
		"sword_skeleton":
			return {
				"name": "Swords Skeleton",
				"sprite": "skeleton",
				"stats": [120, 35, 25, 0, 20, 16],
				"affinity": Element.Id.UNDEAD,
				"color": Color("c8c0a8"),
				"xp": 100,
				"moves": [
					_hit("Slash", Element.Id.PHYSICAL, 25, 90, false, "bleed", 20),
					_hit("Shield", Element.Id.PHYSICAL, 15, 100, false, "self_shield", 100, "cast", "self"),
				],
			}
		"bow_skeleton":
			return {
				"name": "Bow Skeleton",
				"sprite": "skeleton",
				"stats": [100, 35, 25, 0, 20, 25],
				"affinity": Element.Id.UNDEAD,
				"color": Color("b0a890"),
				"xp": 100,
				"moves": [
					_hit("Bow Shot", Element.Id.PHYSICAL, 25, 90, false),
					_hit("Poison Arrow", Element.Id.PHYSICAL, 15, 90, false, "poison", 40),
					_hit("Shock Arrow", Element.Id.PHYSICAL, 15, 90, false, "paralysis", 40),
				],
			}
		"ghoul":
			return {
				"name": "Ghoul",
				"sprite": "ghoul",
				"stats": [120, 25, 25, 10, 20, 30],
				"affinity": Element.Id.UNDEAD,
				"color": Color("7a8a78"),
				"xp": 100,
				"moves": [
					_hit("Bite", Element.Id.UNDEAD, 20, 90, false, "curse", 40),
				],
			}
		"greater_ghoul":
			return {
				"name": "Greater Ghoul",
				"sprite": "ghoul",
				"stats": [200, 32, 22, 12, 18, 22],
				"affinity": Element.Id.UNDEAD,
				"color": Color("5e6e5c"),
				"xp": 200,
				"moves": [
					_hit("Bite", Element.Id.UNDEAD, 28, 90, false, "curse", 50),
					_hit("Claw", Element.Id.PHYSICAL, 24, 90, false, "bleed", 40),
				],
			}
		"orc":
			return {
				"name": "Orc",
				"sprite": "orc",
				"stats": [250, 35, 25, 10, 20, 18],
				"affinity": Element.Id.MONSTER,
				"color": Color("6a7a48"),
				"xp": 200,
				"moves": [
					_hit("Club Slam", Element.Id.PHYSICAL, 45, 90, false),
				],
			}
		"fire_spirit":
			return {
				"name": "Greater Fire Spirit",
				"sprite": "fire_spirit",
				"stats": [250, 10, 25, 35, 20, 30],
				"affinity": Element.Id.FIRE,
				"color": Color("e07030"),
				"xp": 200,
				"moves": [
					_hit("Fireball", Element.Id.FIRE, 45, 90, true, "burn", 40, "bolt"),
					_hit("Fire Blast", Element.Id.FIRE, 35, 100, true, "burn", 50, "bolt"),
				],
			}
		"storm_wolf":
			return {
				"name": "Storm Wolf",
				"sprite": "wolf",
				"stats": [160, 28, 16, 18, 14, 32],
				"affinity": Element.Id.LIGHTNING,
				"color": Color("8aa0c0"),
				"xp": 200,
				"moves": [
					_hit("Bite", Element.Id.LIGHTNING, 30, 95, false, "paralysis", 30),
					_hit("Shock", Element.Id.LIGHTNING, 18, 90, true, "paralysis", 60, "bolt"),
				],
			}
		"warden":
			return {
				"name": "Grove Warden",
				"sprite": "warden",
				"stats": [320, 28, 22, 18, 18, 12],
				"affinity": Element.Id.MONSTER,
				"color": Color("6b5a3e"),
				"xp": 750,
				"moves": [
					_hit("Trunk Slam", Element.Id.PHYSICAL, 34, 90, false),
					_hit("Briar", Element.Id.EARTH, 24, 90, true),
					_hit("Sap", Element.Id.EARTH, 0, 100, true, "heal", 100, "cast", "self"),
				],
			}
		"goblin_king":
			return {
				"name": "Goblin King",
				"sprite": "goblin_king",
				"stats": [600, 45, 55, 10, 50, 30],
				"affinity": Element.Id.MONSTER,
				"color": Color("6a8f45"),
				"xp": 750,
				"moves": [
					_hit("Smash", Element.Id.PHYSICAL, 45, 90, false, "stun", 20, "slam"),
				],
			}
		"hulk":
			return {
				"name": "Hulk",
				"sprite": "hulk",
				"stats": [600, 50, 45, 0, 40, 35],
				"affinity": Element.Id.PHYSICAL,
				"color": Color("6a7058"),
				"xp": 750,
				"immunities": ["stun"],
				"moves": [
					_hit("Smash", Element.Id.PHYSICAL, 60, 90, false, "", 0, "slam"),
					_hit("Roar", Element.Id.PHYSICAL, 20, 100, false, "stun", 30),
				],
			}
		"dragon":
			return {
				"name": "Fire Dragon",
				"sprite": "dragon",
				"stats": [600, 30, 25, 50, 40, 35],
				"affinity": Element.Id.FIRE,
				"color": Color("c45028"),
				"xp": 750,
				"immunities": ["burn"],
				"passives": ["dragon_phase"],
				"moves": [
					_hit("Flame Breath", Element.Id.FIRE, 60, 90, true, "burn", 70, "bolt"),
					_hit("Roar", Element.Id.PHYSICAL, 20, 100, false, "stun", 30),
					_hit("Claw", Element.Id.PHYSICAL, 40, 100, false, "bleed", 40),
				],
			}
		"fastest":
			return {
				"name": "Fastest Man Alive",
				"sprite": "fastest",
				"stats": [500, 35, 25, 0, 20, 100],
				"affinity": Element.Id.PHYSICAL,
				"color": Color("c45c3a"),
				"xp": 750,
				"immunities": ["slow"],
				"moves": [
					_hit("Punch", Element.Id.PHYSICAL, 25, 100, false),
					_hit("Sucker Punch", Element.Id.PHYSICAL, 15, 100, false, "stun", 60),
				],
			}
		_:
			return {
				"name": "Slime",
				"sprite": "slime",
				"stats": [42, 8, 14, 6, 12, 9],
				"affinity": Element.Id.MONSTER,
				"color": Color("6fbf4a"),
				"xp": 100,
				"moves": [
					_hit("Tackle", Element.Id.PHYSICAL, 16, 100, false),
					_hit("Spit", Element.Id.MONSTER, 12, 90, true, "poison", 45),
				],
			}


static func _hit(
	move_name: String,
	element: int,
	power: int,
	accuracy: int,
	is_magic: bool,
	status_id: String = "",
	status_chance: int = 0,
	anim: String = "slash",
	targets: String = "enemy"
) -> MoveData:
	return MoveData.make(
		move_name, element, power, accuracy, is_magic,
		status_id, status_chance, anim, targets
	)
