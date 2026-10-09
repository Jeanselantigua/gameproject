class_name BattleGame
extends Control

## Title flow for a team fight: pick your fighters, pick the AI team, then battle.

@onready var team_select: TeamSelect = $TeamSelect
@onready var battle_screen: BattleScreen = $BattleScreen

var player_ids: Array[String] = []
var ai_ids: Array[String] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	team_select.confirmed.connect(_on_team_confirmed)
	team_select.backed.connect(_on_back)
	battle_screen.dismissed.connect(_on_battle_dismissed)
	battle_screen.visible = false
	_ask_player_team()


func _ask_player_team() -> void:
	battle_screen.abort()
	battle_screen.visible = false
	team_select.visible = true
	team_select.begin("Pick your team", "Choose 1 to 3 fighters. You control this team.", false)


func _ask_ai_team() -> void:
	battle_screen.visible = false
	team_select.visible = true
	team_select.begin("Pick the AI team", "Choose 1 to 3 fighters. The AI controls this team.", true)


func _on_team_confirmed(ids: Array[String]) -> void:
	if team_select.picking_ai:
		ai_ids = ids
		_start_fight()
	else:
		player_ids = ids
		_ask_ai_team()


func _on_back() -> void:
	_ask_player_team()


func _start_fight() -> void:
	team_select.visible = false
	battle_screen.visible = true
	battle_screen.begin(player_ids, ai_ids)


func _on_battle_dismissed(action: String) -> void:
	if action == "again" and not player_ids.is_empty() and not ai_ids.is_empty():
		_start_fight()
	else:
		_ask_player_team()
