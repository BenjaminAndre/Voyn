class_name FighterState
extends RefCounted
## One fighter's plain data (GDD R2). The fighter ID is its roster index in FightState.fighters.

const SIDE_KEEPERS: int = 0
const SIDE_MONSTERS: int = 1

var id: int = 0
var side: int = SIDE_KEEPERS
## Index of the player who controls this fighter (Creatures); -1 for Monsters.
var player: int = -1
var name: String = ""
var max_hp: int = 1
var hp: int = 1
var max_ap: int = 0
var ap: int = 0
var max_mp: int = 0
var mp: int = 0
var power: int = 0
var recharge_steps: int = 1
var traits: PackedStringArray = PackedStringArray()
## Index into the Arena's cells; -1 while unplaced or after defeat.
var cell: int = -1
var alive: bool = true
## Active statuses, each {"name": String, "effect": String, "sign": int, "magnitude": int,
## "ends_step": int, "source": int} (see Statuses).
var statuses: Array[Dictionary] = []
## Ability IDs this fighter can plan, from its creature or Monster data.
var abilities: PackedStringArray = PackedStringArray()
## Ability ID -> the first step it can be used again (R6.1 cooldown).
var cooldowns: Dictionary = {}


func is_creature() -> bool:
	return side == SIDE_KEEPERS


func has_trait(trait_name: String) -> bool:
	return traits.has(trait_name)


func has_status(status_name: String) -> bool:
	for status: Dictionary in statuses:
		if status.get("name", "") == status_name:
			return true
	return false


func on_board() -> bool:
	return alive and cell >= 0


func clone() -> FighterState:
	var copy: FighterState = FighterState.new()
	copy.id = id
	copy.side = side
	copy.player = player
	copy.name = name
	copy.max_hp = max_hp
	copy.hp = hp
	copy.max_ap = max_ap
	copy.ap = ap
	copy.max_mp = max_mp
	copy.mp = mp
	copy.power = power
	copy.recharge_steps = recharge_steps
	copy.traits = traits.duplicate()
	copy.cell = cell
	copy.alive = alive
	for status: Dictionary in statuses:
		copy.statuses.append(status.duplicate(true))
	copy.abilities = abilities.duplicate()
	copy.cooldowns = cooldowns.duplicate()
	return copy
