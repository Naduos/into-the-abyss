## Grafiken & Texte für die Oberfläche (aus data/ui_data.json, siehe tools/dump_ui.js).
## SVG-Strings werden einmal in Texturen umgewandelt und zwischengespeichert.
class_name Art
extends RefCounted

static var U: Dictionary = {}
static var _cache: Dictionary = {}
static var _re_tag: RegEx
static var _re_up: RegEx
static var _re_b: RegEx
static var _re_span: RegEx

static func ensure() -> void:
	if not U.is_empty(): return
	U = JSON.parse_string(FileAccess.open("res://data/ui_data.json", FileAccess.READ).get_as_text())
	_re_up = RegEx.create_from_string("<b class=\"up\">(.*?)</b>")
	_re_b = RegEx.create_from_string("<b[^>]*>(.*?)</b>")
	_re_span = RegEx.create_from_string("<span class=\"([^\"]*)\"[^>]*>(.*?)</span>")
	_re_tag = RegEx.create_from_string("<[^>]+>")

## SVG -> Textur (Höhe in Pixeln; Seitenverhältnis bleibt)
static func tex(svg: String, height: float = 64.0) -> Texture2D:
	if svg == "" or not svg.begins_with("<svg"): return null
	var key := "%d|%d" % [svg.hash(), int(height)]
	if _cache.has(key): return _cache[key]
	var s := svg
	if not s.contains("xmlns="): s = s.replace("<svg ", "<svg xmlns=\"http://www.w3.org/2000/svg\" ")
	var h0 := 54.0
	var m := RegEx.create_from_string("height=\"([0-9.]+)\"").search(s)
	if m: h0 = maxf(1.0, float(m.get_string(1)))
	var img := Image.new()
	if img.load_svg_from_string(s, clampf(height / h0, 0.1, 12.0)) != OK: return null
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

static func card_tex(key: String, h := 80.0) -> Texture2D: return tex(U["card_art"].get(key, ""), h)
static func unit_tex(u: Dictionary, h := 150.0) -> Texture2D:
	var spec = u.get("spec")
	var k: String = u["key"]
	if spec == "acolyte":
		var c: int = u.get("corruption", 0)
		var stg := 4 if c >= 100 else 3 if c >= 50 else 2 if c >= 25 else 1 if c >= 10 else 0
		if U["spec_art"].has("acolyte_%d" % stg): return tex(U["spec_art"]["acolyte_%d" % stg], h)
	if spec != null and U["spec_art"].has(spec): return tex(U["spec_art"][spec], h)
	return tex(U["svg"].get(k, ""), h)
static func svg(name: String, h := 24.0) -> Texture2D: return tex(U["svg"].get(name, ""), h)

## HTML-Kartentext -> BBCode für RichTextLabel
static func bb(html: String) -> String:
	var s := html.replace("<br>", "\n").replace("<br/>", "\n").replace("<div", "\n<div")
	s = _re_up.sub(s, "[b][color=#8dff8d]$1[/color][/b]", true)
	s = _re_b.sub(s, "[b]$1[/b]", true)
	for _i in 3:
		s = _re_span.sub(s, "[color=#ffb36a]$2[/color]", true)
	s = _re_tag.sub(s, "", true)
	return s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&#39;", "'").replace("&quot;", "\"").strip_edges()

static func card_text(c: Dictionary) -> String:
	var t: Array = U["card_text"].get(c["key"], ["", ""])
	return bb(t[1] if c.get("upgraded") else t[0])

static func status_tip(k: String, n) -> String:
	var st: Dictionary = U["status"].get(k, {})
	return bb(str(st.get("tip", k)).replace("#", str(n)))

const RARITY_COL := {"common": Color("#a9a6b0"), "uncommon": Color("#4ac84a"), "rare": Color("#3a8aff"), "epic": Color("#b44aff"), "legendary": Color("#ffb03a")}
