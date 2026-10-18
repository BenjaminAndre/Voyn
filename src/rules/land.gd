class_name Land
extends RefCounted
## The Land phase: the karma automaton (GDD R11.4) and the forecast (R11.5).
## Pure functions over per-cell packed int arrays indexed like HexGrid.cells. Integers only.
##
## All cells update at once, each from the state before the update. Neighbor sums count the existing
## neighbors; a missing neighbor (Arena edge) counts as 0. Every cell takes part, obstacles included.
## A rule "applies" by its condition, before clamping to the karma range, so a Blighted cell that
## also meets a purity condition is still Contested and does not change.

const BLIGHTED: int = -2
const CORRUPTED: int = -1
const NEUTRAL: int = 0
const PURE: int = 1
const THRIVING: int = 2


## R11.4 One Land phase. Returns the next karma array; the input is not modified.
## `threshold` is `land_sum_threshold` from data/combat/rules.json.
static func next_karma(grid: HexGrid, karma: PackedInt32Array, threshold: int) -> PackedInt32Array:
	var result: PackedInt32Array = karma.duplicate()
	for i: int in grid.size():
		result[i] = _next_value(grid, karma, i, threshold)
	return result


## R11.5 The cells the next Land phase would change, and the board karma after it.
## Returns {"changed": PackedInt32Array (cell indices, ascending = cell order),
## "next": PackedInt32Array, "board_karma_after": int}.
static func forecast(grid: HexGrid, karma: PackedInt32Array, threshold: int) -> Dictionary:
	var next: PackedInt32Array = next_karma(grid, karma, threshold)
	var changed: PackedInt32Array = PackedInt32Array()
	for i: int in grid.size():
		if next[i] != karma[i]:
			changed.append(i)
	return {"changed": changed, "next": next, "board_karma_after": board_karma(next)}


## R11.6 Board karma = the sum of every cell's karma.
static func board_karma(karma: PackedInt32Array) -> int:
	var total: int = 0
	for value: int in karma:
		total += value
	return total


static func _next_value(grid: HexGrid, karma: PackedInt32Array, index: int, threshold: int) -> int:
	var value: int = karma[index]
	var neighbor_sum: int = 0
	var has_blighted: bool = false
	var has_thriving: bool = false
	for n: int in grid.neighbor_indices[index]:
		var nk: int = karma[n]
		neighbor_sum += nk
		if nk == BLIGHTED:
			has_blighted = true
		elif nk == THRIVING:
			has_thriving = true

	var corrupts: bool = neighbor_sum <= -threshold or (value == CORRUPTED and has_blighted)
	var purifies: bool = neighbor_sum >= threshold or (value == PURE and has_thriving)
	if corrupts == purifies:
		return value  # Neither applies, or Contested: no change.
	if corrupts:
		return maxi(value - 1, BLIGHTED)
	return mini(value + 1, THRIVING)
