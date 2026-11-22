## JS-kompatible Helfer, damit sich die Godot-Engine exakt wie die Browser-Version verhält
## (gleicher Zufallsgenerator, stabile Sortierung, JS-Rundung und JS-"Truthiness").
class_name JS
extends RefCounted

const M32 := 0xFFFFFFFF

## JS-Truthiness: 0, "", null, false sind falsch – leere Arrays/Objekte sind WAHR (wie in JS).
static func T(v) -> bool:
	match typeof(v):
		TYPE_NIL: return false
		TYPE_BOOL: return v
		TYPE_INT: return v != 0
		TYPE_FLOAT: return v != 0.0 and not is_nan(v)
		TYPE_STRING, TYPE_STRING_NAME: return v != ""
	return true

## Math.round (rundet .5 immer nach oben, auch bei negativen Zahlen)
static func rnd(x) -> int:
	return int(floor(float(x) + 0.5))

static func flr(x) -> int:
	return int(floor(float(x)))

static func cel(x) -> int:
	return int(ceil(float(x)))

## Zahl aus einem Dictionary, 0 falls nicht vorhanden/null (entspricht "x || 0")
static func n(d: Dictionary, k: String):
	var v = d.get(k, 0)
	if v == null or (typeof(v) == TYPE_BOOL and v == false): return 0
	return v

## Math.imul für vorzeichenlose 32-Bit-Werte
static func imul(a: int, b: int) -> int:
	a &= M32; b &= M32
	var lo := (a * (b & 0xFFFF)) & M32
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & M32

## Stabile Sortierung (wie Array.prototype.sort in modernen Browsern), sortiert IN-PLACE.
## cmp(a, b) liefert eine Zahl: < 0 = a zuerst, > 0 = b zuerst, 0 = Reihenfolge behalten.
static func jsort(arr: Array, cmp: Callable) -> Array:
	var n0 := arr.size()
	if n0 < 2: return arr
	var src := arr.duplicate()
	var dst := arr.duplicate()
	var width := 1
	while width < n0:
		var i := 0
		while i < n0:
			var mid := mini(i + width, n0)
			var hi := mini(i + 2 * width, n0)
			var a := i
			var b := mid
			var k := i
			while a < mid and b < hi:
				if float(cmp.call(src[b], src[a])) < 0.0:
					dst[k] = src[b]; b += 1
				else:
					dst[k] = src[a]; a += 1
				k += 1
			while a < mid:
				dst[k] = src[a]; a += 1; k += 1
			while b < hi:
				dst[k] = src[b]; b += 1; k += 1
			i += 2 * width
		var tmp := src; src = dst; dst = tmp
		width *= 2
	for j in n0: arr[j] = src[j]
	return arr

## Index per Objekt-Identität (Dictionaries werden in Godot sonst nach Inhalt verglichen)
static func idx(arr: Array, obj) -> int:
	for i in arr.size():
		if is_same(arr[i], obj): return i
	return -1

static func has(arr: Array, obj) -> bool:
	return idx(arr, obj) >= 0

static func without(arr: Array, obj) -> Array:
	var out := []
	for x in arr:
		if not is_same(x, obj): out.append(x)
	return out

## JSON-Zahlen: ganzzahlige Floats werden zu int (JS kennt keinen Unterschied)
static func normalize(v):
	match typeof(v):
		TYPE_FLOAT:
			if v == floor(v) and abs(v) < 9.0e15: return int(v)
			return v
		TYPE_ARRAY:
			var a := []
			for x in v: a.append(normalize(x))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v: d[k] = normalize(v[k])
			return d
	return v

## Tiefe Kopie wie {...x} bzw. structuredClone für reine Daten
static func clone(v):
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY: return v.duplicate(true)
	return v
