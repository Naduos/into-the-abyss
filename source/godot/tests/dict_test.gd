extends SceneTree
func _init():
	var d := {}
	d.x = 3
	d["y"] = 4
	print(d.get("x"), " ", d.has("x"), " ", d["x"] if d.has("x") else "no", " ", d.y, " ", d.keys(), " ", typeof(d.keys()[0]))
	var k := "x"
	d[k] += 1
	print(d, " ", JSON.stringify(d))
	d.erase("x")
	print(d)
	quit()
