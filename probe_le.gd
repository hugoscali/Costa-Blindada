extends SceneTree
func _init():
	var le = LineEdit.new()
	print("secret: ", le.has_property("secret"))
	print("secret_character: ", le.has_property("secret_character"))
	if le.has_property("secret_character"):
		print("default secret_character: '", le.secret_character, "'")
	quit(0)
