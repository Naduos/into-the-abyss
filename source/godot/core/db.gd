## Spieldaten (automatisch 1:1 aus der Browser-Version exportiert, siehe tools/dump.js).
## Zugriff überall über DB.D["CARDS"] usw.
class_name DB
extends RefCounted

static var D: Dictionary = {}

static func ensure() -> void:
	if not D.is_empty(): return
	var f := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	D = JS.normalize(JSON.parse_string(f.get_as_text()))
