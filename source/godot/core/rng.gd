## Zufall mit Seed – bitgenau identisch zu rng() der Browser-Version (mulberry32)
class_name Rng
extends RefCounted

const M32 := 0xFFFFFFFF
var _seed: int = 1

func seed_rng(s) -> void:
	var v := posmod(int(s), 0x100000000)
	_seed = v if v != 0 else 1

func next() -> float:
	_seed = (_seed + 0x6D2B79F5) & M32
	var t := JS.imul(_seed ^ (_seed >> 15), 1 | _seed)
	t = ((t + JS.imul(t ^ (t >> 7), 61 | t)) & M32) ^ t
	return float((t ^ (t >> 14)) & M32) / 4294967296.0

func rand(a: int, b: int) -> int:
	return int(floor(next() * (b - a + 1))) + a

func pick(a: Array):
	var i := int(floor(next() * a.size()))
	return a[i] if i < a.size() else null

func shuffle(a: Array) -> Array:
	var i := a.size() - 1
	while i > 0:
		var j := int(floor(next() * (i + 1)))
		var t = a[i]; a[i] = a[j]; a[j] = t
		i -= 1
	return a
