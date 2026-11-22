extends SceneTree
func _init():
	var g = Game.new()
	print("compiled ok, cards=", g.CARDS.size())
	quit()
