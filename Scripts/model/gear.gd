class_name Gear
extends RefCounted

## One piece. The main stat is locked to the slot and grows every level.
## Every third level either unlocks a substat or strengthens one, up to five.

const MAX_LEVEL := 30
const MAX_SUBSTATS := 5
const SUBSTAT_EVERY := 3
const TOTAL_UPGRADE_GOLD := 3000

var uid: int = 0
var slot: String = "helm"
var set_id: String = "warlord"
var rarity: String = "common"
var main_kind: String = "hp"
var level: int = 0
var main_value: int = 0
var substats: Array[Dictionary] = []


static func gold_to_reach(gear_level: int) -> int:
	var reached := clampi(gear_level, 0, MAX_LEVEL)
	if reached == 0:
		return 0
	var triangle := int(float(reached * (reached + 1)) / 2.0)
	return int(float(TOTAL_UPGRADE_GOLD) * float(triangle) / 465.0)


static func upgrade_cost(current_level: int) -> int:
	if current_level < 0 or current_level >= MAX_LEVEL:
		return 0
	return gold_to_reach(current_level + 1) - gold_to_reach(current_level)


static func scrap_value(rarity_id: String) -> int:
	match rarity_id:
		"legendary":
			return 120
		"epic":
			return 60
		"rare":
			return 25
		"common":
			return 10
		_:
			return 0


static func main_at(kind: String, gear_level: int) -> int:
	var bounded := clampi(gear_level, 0, MAX_LEVEL)
	if kind == "hp":
		return 14 + 2 * bounded
	if kind == "speed":
		return 3 + int(float(bounded) / 2.0)
	if kind == "crit_rate" or kind == "crit_damage":
		return 4 + int(float(bounded) / 2.0)
	return 6 + bounded


static func roll_sub_value(kind: String) -> int:
	if kind == "hp":
		return randi_range(5, 8)
	if kind == "speed":
		return randi_range(1, 2)
	if kind == "crit_rate":
		return randi_range(2, 4)
	if kind == "crit_damage":
		return randi_range(4, 8)
	return randi_range(2, 4)


func sell_value() -> int:
	return scrap_value(rarity) + gold_to_reach(level)


func bonus(kind: String) -> int:
	var total := main_value if kind == main_kind else 0
	for affix in substats:
		if str(affix.get("kind", "")) == kind:
			total += int(affix.get("value", 0))
	return total


func summary() -> String:
	return "%s %s %s +%d  %s" % [
		GearBook.rarity_label(rarity),
		GearBook.set_label(set_id),
		GearBook.slot_label(slot),
		level,
		GearBook.format_bonus(main_kind, main_value),
	]


func describe() -> String:
	var text := summary()
	if substats.is_empty():
		return text
	var parts: PackedStringArray = []
	for affix in substats:
		parts.append(GearBook.format_bonus(str(affix.get("kind", "")), int(affix.get("value", 0))))
	return "%s\n%s" % [text, ", ".join(parts)]


func level_up() -> String:
	if level >= MAX_LEVEL:
		return "Already at +%d." % MAX_LEVEL
	level += 1
	var old_main := main_value
	main_value = main_at(main_kind, level)
	var note := "%s  (%s +%d)" % [
		summary(),
		GearBook.stat_label(main_kind),
		main_value - old_main,
	]
	if level % SUBSTAT_EVERY != 0:
		return note
	return "%s\n%s" % [note, _roll_substat()]


func _roll_substat() -> String:
	if substats.size() < MAX_SUBSTATS:
		var pool := _open_kinds()
		if not pool.is_empty():
			var kind: String = pool[randi_range(0, pool.size() - 1)]
			var value := roll_sub_value(kind)
			substats.append({"kind": kind, "value": value})
			return "New substat: %s" % GearBook.format_bonus(kind, value)
	if substats.is_empty():
		return ""
	var index := randi_range(0, substats.size() - 1)
	var affix: Dictionary = substats[index]
	var kind := str(affix.get("kind", "attack"))
	var value := roll_sub_value(kind)
	affix["value"] = int(affix.get("value", 0)) + value
	substats[index] = affix
	return "Substat grew: %s" % GearBook.format_bonus(kind, value)


func _open_kinds() -> Array[String]:
	var pool: Array[String] = []
	for kind in GearBook.STAT_KINDS:
		if kind == main_kind or bonus(kind) > (main_value if kind == main_kind else 0):
			continue
		var taken := false
		for affix in substats:
			if str(affix.get("kind", "")) == kind:
				taken = true
				break
		if not taken:
			pool.append(kind)
	return pool


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"slot": slot,
		"set": set_id,
		"rarity": rarity,
		"main": main_kind,
		"level": level,
		"main_value": main_value,
		"subs": substats.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Gear:
	var gear := Gear.new()
	gear.uid = int(data.get("uid", 0))
	gear.slot = str(data.get("slot", "helm"))
	gear.set_id = str(data.get("set", "warlord"))
	gear.rarity = str(data.get("rarity", "common"))
	gear.main_kind = str(data.get("main", "hp"))
	gear.level = int(data.get("level", 0))
	gear.main_value = int(data.get("main_value", main_at(gear.main_kind, gear.level)))
	var subs: Array[Dictionary] = []
	for entry in data.get("subs", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		subs.append({
			"kind": str(entry.get("kind", "attack")),
			"value": int(entry.get("value", 0)),
		})
	gear.substats = subs
	return gear
