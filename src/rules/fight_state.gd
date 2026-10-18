class_name FightState
extends RefCounted
## The complete state of one fight, as plain data that clone() copies in one call
## (docs/architecture.md: previews and AI copy it constantly). Per-cell data lives in packed int
## arrays indexed like HexGrid.cells. Time is the integer `step` counter; there is no clock.

const STATUS_PLACEMENT: String = "placement"
const STATUS_FIGHTING: String = "fighting"
const STATUS_ENDED: String = "ended"

## Shared and never modified, so clones reference the same grid and rules.
var grid: HexGrid
var rules: Dictionary = {}
## Validated definitions by ID (Defs.ability, Defs.status), shared by reference like `rules`.
var abilities: Dictionary = {}
var status_defs: Dictionary = {}

var karma: PackedInt32Array = PackedInt32Array()
var walkable: PackedInt32Array = PackedInt32Array()
var blocks_los: PackedInt32Array = PackedInt32Array()
## Fighter ID standing on each cell, or -1.
var occupant: PackedInt32Array = PackedInt32Array()
## Cell indices where Creatures may be placed, ascending.
var start_cells: PackedInt32Array = PackedInt32Array()
var collapse_at: int = 0
var bloom_at: int = 0

## Roster order: Creatures first, then Monsters. A fighter's ID is its index here.
var fighters: Array[FighterState] = []

## 0 during placement; the number of the step being planned or resolved while fighting.
var step: int = 0
var status: String = STATUS_PLACEMENT
## "" until the fight ends, then "victory", "defeat", "collapse" or "bloom".
var outcome: String = ""
var cleansed_count: int = 0
var prng: Prng = null


## Builds a fight in its Placement phase. Provisional data shapes, until D2/G1 fix the content files:
##   arena  = {"radius": int, "obstacles": [[q, r]], "karma": [[q, r, k]] (default 0),
##             "creature_start_cells": [[q, r]], "collapse_at": int, "bloom_at": int}
##   roster = [{"side": "creature" | "monster", "player": int, "name": String, "max_hp", "max_ap",
##              "max_mp", "power", "recharge_steps": int, "traits": [String],
##              "abilities": [ability ID], "cell": [q, r] (Monsters only: the Encounter spawn cell)}].
##              Stats are inline until
##              data/ has creature and Monster files. Creatures come first, ordered by player then
##              party order from data (never placement order); Monsters follow in Encounter order.
##              A fighter's ID is its index and is never reused.
##   defs   = {"abilities": {id: Defs.ability value}, "statuses": {id: Defs.status value}}
## Returns {"ok": bool, "state": FightState or null, "errors": Array[String]}.
static func create(arena: Dictionary, roster: Array, rules: Dictionary, seed: int, defs: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var radius: Variant = arena.get("radius", null)
	if typeof(radius) != TYPE_INT or int(radius) < 1:
		return {"ok": false, "state": null, "errors": ["arena.radius must be an int >= 1"] as Array[String]}

	var state: FightState = FightState.new()
	state.grid = HexGrid.hexagon(int(radius))
	state.rules = rules
	state.abilities = defs.get("abilities", {})
	state.status_defs = defs.get("statuses", {})
	for ability_id: Variant in state.abilities.keys():
		for effect: Dictionary in (state.abilities[ability_id] as Dictionary)["effects"]:
			if effect["type"] == "apply_status" and not state.status_defs.has(effect["status"]):
				errors.append("ability %s applies unknown status %s" % [str(ability_id), str(effect["status"])])
	state.prng = Prng.create(seed)
	var size: int = state.grid.size()
	state.karma.resize(size)
	state.walkable.resize(size)
	state.blocks_los.resize(size)
	state.occupant.resize(size)
	state.karma.fill(0)
	state.walkable.fill(1)
	state.blocks_los.fill(0)
	state.occupant.fill(-1)
	state.collapse_at = int(arena.get("collapse_at", 0))
	state.bloom_at = int(arena.get("bloom_at", 0))

	for pair: Array in arena.get("obstacles", []):
		var index: int = state.grid.index_of(Vector2i(int(pair[0]), int(pair[1])))
		if index < 0:
			errors.append("obstacle outside the arena: %s" % str(pair))
			continue
		state.walkable[index] = 0
		state.blocks_los[index] = 1

	for triple: Array in arena.get("karma", []):
		var index: int = state.grid.index_of(Vector2i(int(triple[0]), int(triple[1])))
		var value: int = int(triple[2])
		if index < 0 or value < Land.BLIGHTED or value > Land.THRIVING:
			errors.append("bad karma entry: %s" % str(triple))
			continue
		state.karma[index] = value

	var starts: Array[int] = []
	for pair: Array in arena.get("creature_start_cells", []):
		var index: int = state.grid.index_of(Vector2i(int(pair[0]), int(pair[1])))
		if index < 0 or state.walkable[index] == 0 or starts.has(index):
			errors.append("bad start cell: %s" % str(pair))
			continue
		starts.append(index)
	starts.sort()
	state.start_cells = PackedInt32Array(starts)

	var seen_monster: bool = false
	for i: int in roster.size():
		var entry: Dictionary = roster[i]
		var fighter: FighterState = FighterState.new()
		fighter.id = i
		fighter.name = str(entry.get("name", "fighter%d" % i))
		var side: String = str(entry.get("side", ""))
		if side == "creature":
			fighter.side = FighterState.SIDE_KEEPERS
			fighter.player = int(entry.get("player", 0))
			if seen_monster:
				errors.append("%s: Creatures must come before Monsters in the roster" % fighter.name)
		elif side == "monster":
			fighter.side = FighterState.SIDE_MONSTERS
			fighter.player = -1
			seen_monster = true
		else:
			errors.append("%s: side must be 'creature' or 'monster'" % fighter.name)
		fighter.max_hp = int(entry.get("max_hp", 0))
		fighter.max_ap = int(entry.get("max_ap", 0))
		fighter.max_mp = int(entry.get("max_mp", 0))
		fighter.power = int(entry.get("power", 0))
		fighter.recharge_steps = int(entry.get("recharge_steps", 0))
		for trait_name: Variant in entry.get("traits", []):
			fighter.traits.append(str(trait_name))
		for ability_id: Variant in entry.get("abilities", []):
			if not state.abilities.has(str(ability_id)):
				errors.append("%s: unknown ability %s" % [fighter.name, str(ability_id)])
			fighter.abilities.append(str(ability_id))
		if fighter.max_hp < 1:
			errors.append("%s: max_hp must be >= 1" % fighter.name)
		if fighter.recharge_steps < 1:
			errors.append("%s: recharge_steps must be >= 1" % fighter.name)
		# A fight starts with full pools; they refill every recharge_steps steps (R3.5).
		fighter.hp = fighter.max_hp
		fighter.ap = fighter.max_ap
		fighter.mp = fighter.max_mp
		state.fighters.append(fighter)

		if fighter.side == FighterState.SIDE_MONSTERS:
			var spawn: Array = entry.get("cell", [])
			var index: int = -1
			if spawn.size() == 2:
				index = state.grid.index_of(Vector2i(int(spawn[0]), int(spawn[1])))
			if index < 0 or state.walkable[index] == 0 or state.occupant[index] != -1:
				errors.append("%s: bad spawn cell %s" % [fighter.name, str(spawn)])
			else:
				state.set_position(fighter, index)

	var creatures: int = state.living_count(FighterState.SIDE_KEEPERS)
	if creatures == 0 or state.living_count(FighterState.SIDE_MONSTERS) == 0:
		errors.append("a fight needs at least one Creature and one Monster")
	if creatures > state.start_cells.size():
		errors.append("fewer start cells than Creatures")

	if not errors.is_empty():
		return {"ok": false, "state": null, "errors": errors}
	return {"ok": true, "state": state, "errors": errors}


func clone() -> FightState:
	var copy: FightState = FightState.new()
	copy.grid = grid
	copy.rules = rules
	copy.abilities = abilities
	copy.status_defs = status_defs
	copy.karma = karma.duplicate()
	copy.walkable = walkable.duplicate()
	copy.blocks_los = blocks_los.duplicate()
	copy.occupant = occupant.duplicate()
	copy.start_cells = start_cells
	copy.collapse_at = collapse_at
	copy.bloom_at = bloom_at
	for fighter: FighterState in fighters:
		copy.fighters.append(fighter.clone())
	copy.step = step
	copy.status = status
	copy.outcome = outcome
	copy.cleansed_count = cleansed_count
	copy.prng = prng.clone()
	return copy


## Puts a fighter on a cell (it must be free), vacating its old cell. Keeps `occupant` consistent.
func set_position(fighter: FighterState, cell_index: int) -> void:
	if fighter.cell >= 0 and occupant[fighter.cell] == fighter.id:
		occupant[fighter.cell] = -1
	fighter.cell = cell_index
	occupant[cell_index] = fighter.id


## Takes a fighter off the board (defeat).
func remove_from_board(fighter: FighterState) -> void:
	if fighter.cell >= 0 and occupant[fighter.cell] == fighter.id:
		occupant[fighter.cell] = -1
	fighter.cell = -1


## The fighter standing on a cell index, or null.
func fighter_at(cell_index: int) -> FighterState:
	var id: int = occupant[cell_index]
	if id < 0:
		return null
	return fighters[id]


func cell_of(fighter: FighterState) -> Vector2i:
	return grid.cell_at(fighter.cell)


## Fighters of a side that are still in the fight, in roster order.
func living(side: int) -> Array[FighterState]:
	var result: Array[FighterState] = []
	for fighter: FighterState in fighters:
		if fighter.alive and fighter.side == side:
			result.append(fighter)
	return result


func living_count(side: int) -> int:
	var count: int = 0
	for fighter: FighterState in fighters:
		if fighter.alive and fighter.side == side:
			count += 1
	return count


## True if the cell stops line of sight (R5.1): outside the Arena, `blocks_los`, or holding a fighter.
## Suitable as the `blocks` callback of Los.has_los.
func blocks_sight(cell: Vector2i) -> bool:
	var index: int = grid.index_of(cell)
	if index < 0:
		return true
	return blocks_los[index] == 1 or occupant[index] >= 0
