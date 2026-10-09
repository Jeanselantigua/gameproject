class_name Element
extends RefCounted

## Java Type. Affinities and move elements.

enum Id {
	PHYSICAL,
	FIRE,
	ICE,
	LIGHTNING,
	EARTH,
	ARCANE,
	HOLY,
	SHADOW,
	UNDEAD,
	MONSTER,
}

const NAMES := {
	Id.PHYSICAL: "Physical",
	Id.FIRE: "Fire",
	Id.ICE: "Ice",
	Id.LIGHTNING: "Lightning",
	Id.EARTH: "Earth",
	Id.ARCANE: "Arcane",
	Id.HOLY: "Holy",
	Id.SHADOW: "Shadow",
	Id.UNDEAD: "Undead",
	Id.MONSTER: "Monster",
}


static func name_of(id: int) -> String:
	return String(NAMES.get(id, "Physical"))
