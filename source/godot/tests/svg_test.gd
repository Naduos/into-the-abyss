extends SceneTree
func _init():
	var d = JSON.parse_string(FileAccess.open("res://data/ui_data.json", FileAccess.READ).get_as_text())
	var bad := []; var n := 0
	for grp in ["card_art", "svg", "spec_art"]:
		for k in d[grp]:
			var s: String = d[grp][k]
			if not s.begins_with("<svg"): continue
			n += 1
			var img := Image.new()
			if not s.contains("xmlns"): s = s.replace("<svg ", "<svg xmlns=\"http://www.w3.org/2000/svg\" ")
			var err := img.load_svg_from_string(s, 2.0)
			if err != OK or img.is_empty(): bad.append(grp + "/" + k)
	print("svg ok ", n - bad.size(), "/", n, " bad: ", bad.slice(0, 30))
	var img := Image.new(); var s2: String = d["card_art"]["shadowbox"].replace("<svg ", "<svg xmlns=\"http://www.w3.org/2000/svg\" ")
	img.load_svg_from_string(s2, 3.0); img.save_png("/tmp/svg_shadowbox.png")
	var s3: String = d["svg"]["knight"].replace("<svg ", "<svg xmlns=\"http://www.w3.org/2000/svg\" ")
	img.load_svg_from_string(s3, 2.0); img.save_png("/tmp/svg_knight.png")
	quit()
