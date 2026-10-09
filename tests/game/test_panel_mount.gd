extends GutTest


func test_panel_mount_is_above_header_and_receives_clicks() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	# Isolate GUI dispatch from GUT's own overlay, which occupies the root viewport.
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1152, 800)
	add_child_autofree(viewport)
	viewport.add_child(scene)
	await get_tree().process_frame
	var view: Node = scene.get_node("Map")
	var layer: CanvasLayer
	for child: Node in view.get_children():
		if child is CanvasLayer:
			layer = child as CanvasLayer
	assert_not_null(layer)
	var mount: Control = layer.get_node("PanelMount") as Control
	for child: Node in layer.get_children():
		if child is ColorRect:
			assert_gt(mount.get_index(), child.get_index(), "Panel must draw above the opaque header")
	var button: Button = Button.new()
	button.position = Vector2(20, 20)
	button.size = Vector2(120, 30)
	mount.add_child(button)
	watch_signals(button)
	await get_tree().process_frame
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(40, 30)
	click.pressed = true
	viewport.push_input(click, true)
	click.pressed = false
	viewport.push_input(click, true)
	assert_signal_emitted(button, "pressed")
