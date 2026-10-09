class_name TypeChart
extends RefCounted

## Java TypeChart. Missing pairs are 1.0.

var _chart: Dictionary = {}


func _init() -> void:
	set_matchup(Element.Id.PHYSICAL, Element.Id.HOLY, 1.25)
	set_matchup(Element.Id.PHYSICAL, Element.Id.ARCANE, 1.5)
	set_matchup(Element.Id.PHYSICAL, Element.Id.SHADOW, 0.25)
	set_matchup(Element.Id.PHYSICAL, Element.Id.UNDEAD, 0.75)

	set_matchup(Element.Id.FIRE, Element.Id.ICE, 1.5)
	set_matchup(Element.Id.FIRE, Element.Id.MONSTER, 1.25)
	set_matchup(Element.Id.FIRE, Element.Id.EARTH, 0.5)
	set_matchup(Element.Id.FIRE, Element.Id.FIRE, 0.5)

	set_matchup(Element.Id.ICE, Element.Id.EARTH, 1.5)
	set_matchup(Element.Id.ICE, Element.Id.FIRE, 0.5)
	set_matchup(Element.Id.ICE, Element.Id.ICE, 0.5)

	set_matchup(Element.Id.EARTH, Element.Id.LIGHTNING, 1.5)
	set_matchup(Element.Id.EARTH, Element.Id.EARTH, 0.5)

	set_matchup(Element.Id.LIGHTNING, Element.Id.EARTH, 0.0)
	set_matchup(Element.Id.LIGHTNING, Element.Id.PHYSICAL, 1.15)
	set_matchup(Element.Id.LIGHTNING, Element.Id.LIGHTNING, 0.5)

	set_matchup(Element.Id.HOLY, Element.Id.UNDEAD, 1.5)
	set_matchup(Element.Id.HOLY, Element.Id.SHADOW, 1.5)
	set_matchup(Element.Id.HOLY, Element.Id.MONSTER, 2.0)
	set_matchup(Element.Id.HOLY, Element.Id.HOLY, 0.5)

	set_matchup(Element.Id.ARCANE, Element.Id.PHYSICAL, 1.5)
	set_matchup(Element.Id.ARCANE, Element.Id.UNDEAD, 0.5)

	set_matchup(Element.Id.SHADOW, Element.Id.HOLY, 1.5)
	set_matchup(Element.Id.SHADOW, Element.Id.ARCANE, 0.5)

	set_matchup(Element.Id.MONSTER, Element.Id.HOLY, 0.5)


func multiplier(attacking: int, defending: int) -> float:
	return float(_chart.get(_key(attacking, defending), 1.0))


func set_matchup(attacking: int, defending: int, amount: float) -> void:
	_chart[_key(attacking, defending)] = amount


func _key(attacking: int, defending: int) -> String:
	return "%d:%d" % [attacking, defending]
