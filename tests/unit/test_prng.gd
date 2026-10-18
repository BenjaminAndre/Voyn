extends GutTest
## T2b: seeded PCG32. The golden file is the port contract: a Go port must reproduce it exactly.

const GOLDEN_PATH: String = "res://tests/golden/prng_pcg32.json"


func test_matches_pcg32_reference_vectors() -> void:
	# pcg32 output for initstate = 42, initseq = 54, as printed by the pcg32 demo and
	# cross-checked against an independent Python implementation (all 1000 golden outputs).
	var expected: Array[int] = [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
	var prng: Prng = Prng.create(42, 54)
	for value: int in expected:
		assert_eq(prng.next_u32(), value)


func test_golden_first_1000_outputs() -> void:
	var data: Variant = JSON.parse_string(DataFiles.read_text(GOLDEN_PATH))
	assert_true(data is Dictionary, "golden file loads")
	var golden: Dictionary = data
	var prng: Prng = Prng.create(int(golden["initstate"]), int(golden["initseq"]))
	var outputs: Array = golden["outputs"]
	assert_eq(outputs.size(), 1000)
	var mismatches: int = 0
	for i: int in outputs.size():
		if prng.next_u32() != int(outputs[i]):
			mismatches += 1
	assert_eq(mismatches, 0, "all 1000 outputs match")


func test_same_seed_same_sequence() -> void:
	var a: Prng = Prng.create(123456789)
	var b: Prng = Prng.create(123456789)
	for i: int in 100:
		assert_eq(a.next_u32(), b.next_u32())


func test_different_seeds_differ() -> void:
	var a: Prng = Prng.create(1)
	var b: Prng = Prng.create(2)
	var same: int = 0
	for i: int in 100:
		if a.next_u32() == b.next_u32():
			same += 1
	assert_lt(same, 3)


func test_clone_is_independent() -> void:
	var a: Prng = Prng.create(7)
	a.next_u32()
	var b: Prng = a.clone()
	assert_eq(a.next_u32(), b.next_u32(), "clone continues from the same point")
	b.next_u32()
	b.next_u32()
	var a_next: int = a.next_u32()
	var c: Prng = Prng.create(7)
	c.next_u32()
	c.next_u32()
	assert_eq(a_next, c.next_u32(), "advancing the clone did not move the original")


func test_outputs_are_32_bit_unsigned() -> void:
	var prng: Prng = Prng.create(99)
	for i: int in 1000:
		var value: int = prng.next_u32()
		assert_between(value, 0, 0xFFFFFFFF)


func test_next_below_stays_in_range_and_hits_every_value() -> void:
	var prng: Prng = Prng.create(5)
	var seen: Dictionary = {}
	for i: int in 2000:
		var value: int = prng.next_below(6)
		assert_between(value, 0, 5)
		seen[value] = true
	assert_eq(seen.size(), 6)


func test_next_below_one_is_zero() -> void:
	var prng: Prng = Prng.create(5)
	for i: int in 20:
		assert_eq(prng.next_below(1), 0)


func test_roll_percent_edges() -> void:
	var prng: Prng = Prng.create(11)
	var before: int = prng.state
	assert_false(prng.roll_percent(0))
	assert_true(prng.roll_percent(100))
	assert_eq(prng.state, before, "0 and 100 never draw")


func test_roll_percent_is_roughly_calibrated() -> void:
	var prng: Prng = Prng.create(2024)
	var hits: int = 0
	for i: int in 10000:
		if prng.roll_percent(30):
			hits += 1
	assert_between(hits, 2700, 3300)
