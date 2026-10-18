class_name Prng
extends RefCounted
## Seeded integer PRNG: PCG32 (pcg_basic, XSH-RR output, 64-bit state), written by hand so a Go port
## reproduces it bit for bit (docs/architecture.md, determinism). Never use the engine RNG in src/rules/.
##
## GDScript ints are 64-bit and wrap on overflow, which matches uint64 arithmetic bit for bit.
## But `>>` is an arithmetic shift, so every right shift of the state goes through `_lsr`.
##
## State is two plain ints (`state`, `inc`), so a fight state or a preview can copy it with `clone()`.
## Only `chance` effects draw from the real generator; previews and AI work on a clone.

const MULTIPLIER: int = 6364136223846793005
const DEFAULT_STREAM: int = 54
const U32_MASK: int = 0xFFFFFFFF

var state: int = 0
var inc: int = 0


## Same seeding as pcg32_srandom_r(initstate, initseq).
static func create(initstate: int, initseq: int = DEFAULT_STREAM) -> Prng:
	var prng: Prng = Prng.new()
	prng.inc = (initseq << 1) | 1
	prng.state = 0
	prng.next_u32()
	prng.state += initstate
	prng.next_u32()
	return prng


func clone() -> Prng:
	var copy: Prng = Prng.new()
	copy.state = state
	copy.inc = inc
	return copy


## Next 32-bit unsigned output, as an int in [0, 2^32).
func next_u32() -> int:
	var old: int = state
	state = old * MULTIPLIER + inc
	var xorshifted: int = _lsr((_lsr(old, 18) ^ old), 27) & U32_MASK
	var rot: int = _lsr(old, 59)
	return ((_lsr(xorshifted, rot)) | (xorshifted << ((-rot) & 31))) & U32_MASK


## Unbiased integer in [0, bound), bound > 0 (pcg32_boundedrand_r: reject the low biased zone).
func next_below(bound: int) -> int:
	assert(bound > 0 and bound <= U32_MASK, "bound must be in 1..2^32-1")
	var threshold: int = (0x100000000 - bound) % bound
	while true:
		var r: int = next_u32()
		if r >= threshold:
			return r % bound
	return 0


## True with probability pct/100 (pct clamped to 0..100). For `chance` effects.
func roll_percent(pct: int) -> bool:
	if pct <= 0:
		return false
	if pct >= 100:
		return true
	return next_below(100) < pct


## Logical (unsigned) right shift of a 64-bit value; n in 0..63.
static func _lsr(value: int, n: int) -> int:
	if n == 0:
		return value
	return (value >> n) & ((1 << (64 - n)) - 1)
