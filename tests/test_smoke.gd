extends GutTest


func test_main_scene_can_be_instantiated() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	assert_not_null(main_scene, "The main scene must load.")
	if main_scene == null:
		return

	var main: Node = main_scene.instantiate()
	assert_is(main, Node2D, "The placeholder scene must be a 2D map.")
	assert_not_null(main.get_node_or_null("Map"), "The map placeholder must exist.")
	main.free()
