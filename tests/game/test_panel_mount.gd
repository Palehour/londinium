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


func test_idle_frames_and_hover_do_not_redraw_but_changes_do() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1152, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	viewport.add_child(scene)
	var view: Node2D = scene.get_node("Map") as Node2D
	(view.get("clock") as SimClock).speed = 0
	view.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	watch_signals(view)
	view.call("_process", 0.0)
	view.call("_unhandled_input", InputEventMouseMotion.new())
	var session: GameSession = view.get("session") as GameSession
	view.call("_snapshot_received", session.get_snapshot())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_signal_not_emitted(view, "draw")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	view.call("_unhandled_input", key)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_signal_emit_count(view, "draw", 1)
	view.call("_unhandled_input", key)
	await get_tree().process_frame
	assert_signal_emit_count(view, "draw", 1)
	session.simulation.tick()
	session.publish_tick()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_signal_emit_count(view, "draw", 2)
