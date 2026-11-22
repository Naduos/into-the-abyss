extends SceneTree
func _init():
	var r := Rng.new()
	for s in [1, 12345, 4294967295, 987654321987]:
		r.seed_rng(s)
		var out := []
		for i in 5: out.append("%.15f" % r.next())
		print(s, " ", out)
	var arr := [{"k":3,"i":0},{"k":1,"i":1},{"k":3,"i":2},{"k":2,"i":3},{"k":1,"i":4}]
	JS.jsort(arr, func(a, b): return a.k - b.k)
	print(arr.map(func(x): return x.i))
	DB.ensure(); print(DB.D["CARDS"].size(), " ", DB.D["CARDS"]["strike"])
	quit()
