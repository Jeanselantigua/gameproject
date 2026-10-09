class_name GearBook
extends RefCounted

## Persistent stash. Gold and pieces survive leaving a run.
## Equipped pieces are worn the next time that fighter is spawned.

const PATH := "user://gear_book.json"
const STAT_KINDS: Array[String] = [
	"hp", "attack", "defense", "magic_attack", "magic_defense", "speed", "crit_rate", "crit_damage",
]
const SLOTS: Array[String] = ["helm", "gloves", "chest", "boots", "amulet", "ring"]
const SETS: Array[String] = ["warlord", "sage", "swift", "bulwark", "vampire"]
const RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]

static var gold: int = 0
static var pieces: Array[Gear] = []
static var equipped: Dictionary = {}
static var _next_uid: int = 1
static var _loaded: bool = false


static func load_book() -> void:
	if _loaded:
		return
	_loaded = true
	gold = 0
	pieces.clear()
	equipped.clear()
	_next_uid = 1
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	gold = maxi(0, int(parsed.get("gold", 0)))
	_next_uid = maxi(1, int(parsed.get("next_uid", 1)))
	for entry in parsed.get("pieces", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var gear := Gear.from_dict(entry)
		if gear.uid <= 0:
			continue
		pieces.append(gear)
		_next_uid = maxi(_next_uid, gear.uid + 1)
	var worn: Dictionary = parsed.get("equipped", {})
	for hero_id in worn.keys():
		var slots: Dictionary = worn[hero_id]
		if typeof(slots) != TYPE_DICTIONARY:
			continue
		var clean := {}
		for slot in slots.keys():
			clean[str(slot)] = int(slots[slot])
		equipped[str(hero_id)] = clean


static func save_book() -> void:
	var dumped: Array = []
	for gear in pieces:
		dumped.append(gear.to_dict())
	var payload := {
		"gold": gold,
		"next_uid": _next_uid,
		"pieces": dumped,
		"equipped": equipped,
	}
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload))


static func piece_by_uid(uid: int) -> Gear:
	for gear in pieces:
		if gear.uid == uid:
			return gear
	return null


static func piece_on(hero_id: String, slot: String) -> Gear:
	var slots: Dictionary = equipped.get(hero_id, {})
	return piece_by_uid(int(slots.get(slot, 0)))


static func worn_by(hero_id: String) -> Array[Gear]:
	var worn: Array[Gear] = []
	for slot in SLOTS:
		var gear := piece_on(hero_id, slot)
		if gear != null:
			worn.append(gear)
	return worn


static func in_bag(gear: Gear) -> bool:
	return gear != null and not _is_worn(gear.uid)


static func bag(slot_filter: String = "") -> Array[Gear]:
	var found: Array[Gear] = []
	for gear in pieces:
		if _is_worn(gear.uid):
			continue
		if slot_filter != "" and gear.slot != slot_filter:
			continue
		found.append(gear)
	return found


static func add_piece(gear: Gear) -> void:
	if gear == null:
		return
	if gear.uid <= 0:
		gear.uid = _next_uid
		_next_uid += 1
	pieces.append(gear)


static func equip(hero_id: String, gear: Gear) -> bool:
	if gear == null or not in_bag(gear):
		return false
	var slots: Dictionary = equipped.get(hero_id, {})
	slots[gear.slot] = gear.uid
	equipped[hero_id] = slots
	save_book()
	return true


static func unequip(hero_id: String, slot: String) -> Gear:
	var slots: Dictionary = equipped.get(hero_id, {})
	var gear := piece_by_uid(int(slots.get(slot, 0)))
	if gear == null:
		return null
	slots.erase(slot)
	equipped[hero_id] = slots
	save_book()
	return gear


static func try_upgrade(gear: Gear) -> String:
	if gear == null:
		return "Select a piece."
	if gear.level >= Gear.MAX_LEVEL:
		return "That piece is already +%d." % Gear.MAX_LEVEL
	var cost := Gear.upgrade_cost(gear.level)
	if gold < cost:
		return "Need %d gold to upgrade." % cost
	gold -= cost
	var note := gear.level_up()
	save_book()
	return note


static func try_sell(gear: Gear) -> String:
	if gear == null or not in_bag(gear):
		return "Unequip a piece before selling it."
	var value := gear.sell_value()
	pieces.erase(gear)
	gold += value
	save_book()
	return "Sold for %d gold." % value


static func roll_wave(foes: Array, difficulty: float) -> Dictionary:
	load_book()
	var gained := 0
	var drops: Array[Gear] = []
	for foe in foes:
		var battler := foe as Battler
		if battler == null:
			continue
		var rank := battler.rank if battler.rank != "" else "normal"
		gained += gold_for(rank, difficulty)
		var piece := _maybe_drop(rank)
		if piece != null:
			add_piece(piece)
			drops.append(piece)
	if gained > 0:
		gold += gained
	if gained > 0 or not drops.is_empty():
		save_book()
	return {"gold": gained, "pieces": drops}


static func gold_for(rank: String, difficulty: float) -> int:
	if difficulty <= 0.0:
		return 0
	var base := 15
	if rank == "elite":
		base = 40
	elif rank == "boss":
		base = 120
	return maxi(0, int(round(float(base) * difficulty)))


static func apply(battler: Battler) -> void:
	if battler == null or battler.side != "player":
		return
	load_book()
	_clear_set_passives(battler)
	var old: Dictionary = battler.gear_bonus
	var flat := {}
	var counts := {}
	for gear in worn_by(battler.display_name):
		for kind in STAT_KINDS:
			flat[kind] = int(flat.get(kind, 0)) + gear.bonus(kind)
		counts[gear.set_id] = int(counts.get(gear.set_id, 0)) + 1
	var bonus := flat.duplicate()
	var two := {}
	if int(counts.get("warlord", 0)) >= 2:
		two["attack"] = _percent(_naked(battler, "attack", old) + int(flat.get("attack", 0)), 0.20)
	if int(counts.get("sage", 0)) >= 2:
		two["magic_attack"] = _percent(_naked(battler, "magic_attack", old) + int(flat.get("magic_attack", 0)), 0.20)
	if int(counts.get("swift", 0)) >= 2:
		two["speed"] = _percent(_naked(battler, "speed", old) + int(flat.get("speed", 0)), 0.20)
	if int(counts.get("bulwark", 0)) >= 2:
		two["defense"] = _percent(_naked(battler, "defense", old) + int(flat.get("defense", 0)), 0.20)
	for kind in two.keys():
		bonus[kind] = int(bonus.get(kind, 0)) + int(two[kind])
	_apply_delta(battler, old, bonus)
	battler.gear_bonus = bonus
	battler.set_two = two
	_grant_set_passives(battler, counts)


static func set_summary(hero_id: String) -> String:
	var counts := {}
	for gear in worn_by(hero_id):
		counts[gear.set_id] = int(counts.get(gear.set_id, 0)) + 1
	if counts.is_empty():
		return "No set pieces worn."
	var lines: PackedStringArray = []
	for set_id in SETS:
		var count := int(counts.get(set_id, 0))
		if count <= 0:
			continue
		lines.append("%s %d — %s" % [set_label(set_id), count, _set_blurb(set_id, count)])
	return "\n".join(lines)


static func stat_label(kind: String) -> String:
	match kind:
		"hp":
			return "HP"
		"attack":
			return "Attack"
		"defense":
			return "Defense"
		"magic_attack":
			return "Magic Attack"
		"magic_defense":
			return "Magic Defense"
		"speed":
			return "Speed"
		"crit_rate":
			return "Crit Rate"
		"crit_damage":
			return "Crit DMG"
		_:
			return kind


static func format_bonus(kind: String, value: int) -> String:
	var suffix := "%" if kind == "crit_rate" or kind == "crit_damage" else ""
	return "%s +%d%s" % [stat_label(kind), value, suffix]


static func slot_label(slot: String) -> String:
	match slot:
		"helm":
			return "Helm"
		"gloves":
			return "Gloves"
		"chest":
			return "Chest"
		"boots":
			return "Boots"
		"amulet":
			return "Amulet"
		"ring":
			return "Ring"
		_:
			return slot


static func set_label(set_id: String) -> String:
	match set_id:
		"warlord":
			return "Warlord"
		"sage":
			return "Sage"
		"swift":
			return "Swift"
		"bulwark":
			return "Bulwark"
		"vampire":
			return "Vampire"
		_:
			return set_id


static func rarity_label(rarity_id: String) -> String:
	match rarity_id:
		"common":
			return "Common"
		"rare":
			return "Rare"
		"epic":
			return "Epic"
		"legendary":
			return "Legendary"
		_:
			return rarity_id


static func rarity_color(rarity_id: String) -> Color:
	match rarity_id:
		"rare":
			return Color(0.55, 0.75, 1.0)
		"epic":
			return Color(0.78, 0.55, 0.95)
		"legendary":
			return Color(1.0, 0.72, 0.35)
		_:
			return Color(0.9, 0.86, 0.74)


static func _maybe_drop(rank: String) -> Gear:
	if rank == "boss":
		return _make(_boss_rarity(randf()))
	var roll := randf()
	if rank == "elite":
		if roll >= 0.75:
			return null
		return _make(_elite_rarity(randf()))
	if roll >= 0.20:
		return null
	return _make(_normal_rarity(randf()))


static func _make(rarity_id: String) -> Gear:
	var gear := Gear.new()
	gear.slot = SLOTS[randi_range(0, SLOTS.size() - 1)]
	gear.set_id = SETS[randi_range(0, SETS.size() - 1)]
	gear.rarity = rarity_id
	var pool := _main_pool(gear.slot)
	gear.main_kind = pool[randi_range(0, pool.size() - 1)]
	gear.main_value = Gear.main_at(gear.main_kind, 0)
	var starting := mini(_starting_subs(rarity_id), Gear.MAX_SUBSTATS)
	var open := GearBook.STAT_KINDS.duplicate()
	open.erase(gear.main_kind)
	for _i in starting:
		if open.is_empty():
			break
		var kind: String = open[randi_range(0, open.size() - 1)]
		open.erase(kind)
		gear.substats.append({"kind": kind, "value": Gear.roll_sub_value(kind)})
	return gear


static func _main_pool(slot: String) -> Array[String]:
	match slot:
		"helm":
			return ["hp"]
		"gloves":
			return ["attack"]
		"chest":
			return ["defense"]
		"boots":
			return ["speed"]
		"amulet":
			return ["magic_attack", "magic_defense"]
		_:
			return ["hp", "attack", "defense", "magic_attack", "magic_defense", "speed"]


static func _starting_subs(rarity_id: String) -> int:
	match rarity_id:
		"rare":
			return 1
		"epic":
			return 2
		"legendary":
			return 3
		_:
			return 0


static func _normal_rarity(roll: float) -> String:
	return "rare" if roll < 0.15 else "common"


static func _elite_rarity(roll: float) -> String:
	if roll < 0.15:
		return "legendary"
	if roll < 0.45:
		return "epic"
	return "rare"


static func _boss_rarity(roll: float) -> String:
	if roll < 0.20:
		return "legendary"
	if roll < 0.60:
		return "epic"
	return "rare"


static func _set_blurb(set_id: String, count: int) -> String:
	var parts: PackedStringArray = []
	if count >= 2:
		match set_id:
			"warlord":
				parts.append("+20% Attack")
			"sage":
				parts.append("+20% Magic Attack")
			"swift":
				parts.append("+20% Speed")
			"bulwark":
				parts.append("+20% Defense")
			"vampire":
				parts.append("physical hits heal 25%")
	if count >= 4:
		match set_id:
			"warlord":
				parts.append("more Attack while allies are down")
			"sage":
				parts.append("hurt: allies gain Speed")
			"swift":
				parts.append("extra crit damage at high Speed")
			"bulwark":
				parts.append("a shield below half HP")
			"vampire":
				parts.append("kills raise max HP")
	if parts.is_empty():
		return "1 piece"
	return ", ".join(parts)


static func _is_worn(uid: int) -> bool:
	for hero_id in equipped.keys():
		var slots: Dictionary = equipped[hero_id]
		for slot in slots.keys():
			if int(slots[slot]) == uid:
				return true
	return false


static func _naked(battler: Battler, kind: String, old: Dictionary) -> int:
	return _stat(battler, kind) - int(old.get(kind, 0))


static func _stat(battler: Battler, kind: String) -> int:
	match kind:
		"hp":
			return battler.max_hp
		"attack":
			return battler.attack
		"defense":
			return battler.defense
		"magic_attack":
			return battler.magic_attack
		"magic_defense":
			return battler.magic_defense
		"speed":
			return battler.speed
		"crit_rate":
			return battler.crit_rate
		"crit_damage":
			return battler.crit_damage
	return 0


static func _apply_delta(battler: Battler, old: Dictionary, new_bonus: Dictionary) -> void:
	for kind in STAT_KINDS:
		var delta := int(new_bonus.get(kind, 0)) - int(old.get(kind, 0))
		if delta == 0:
			continue
		match kind:
			"hp":
				battler.max_hp = maxi(1, battler.max_hp + delta)
				if delta > 0 and battler.hp > 0:
					battler.hp += delta
				battler.hp = clampi(battler.hp, 0, battler.max_hp)
			"attack":
				battler.attack += delta
			"defense":
				battler.defense += delta
			"magic_attack":
				battler.magic_attack += delta
			"magic_defense":
				battler.magic_defense += delta
			"speed":
				battler.speed = maxi(1, battler.speed + delta)
			"crit_rate":
				battler.crit_rate = maxi(0, battler.crit_rate + delta)
			"crit_damage":
				battler.crit_damage = maxi(0, battler.crit_damage + delta)


static func _clear_set_passives(battler: Battler) -> void:
	for passive in battler.passives:
		if str(passive.kind).begins_with("set_"):
			passive.reset_set(battler)
	var kept: Array = []
	for passive in battler.passives:
		if not str(passive.kind).begins_with("set_"):
			kept.append(passive)
	battler.passives = kept


static func _grant_set_passives(battler: Battler, counts: Dictionary) -> void:
	if int(counts.get("vampire", 0)) >= 2:
		_add_set(battler, "set_vampire")
	if int(counts.get("vampire", 0)) >= 4:
		_add_set(battler, "set_vampire4")
	if int(counts.get("swift", 0)) >= 4:
		_add_set(battler, "set_swift")
	if int(counts.get("bulwark", 0)) >= 4:
		_add_set(battler, "set_bulwark")
	if int(counts.get("warlord", 0)) >= 4:
		_add_set(battler, "set_warlord")
	if int(counts.get("sage", 0)) >= 4:
		_add_set(battler, "set_sage")


static func _add_set(battler: Battler, kind: String) -> void:
	var passive := KitPassive.new()
	passive.kind = kind
	battler.passives.append(passive)


static func _percent(value: int, ratio: float) -> int:
	if value <= 0 or ratio <= 0.0:
		return 0
	return int(round(float(value) * ratio))
