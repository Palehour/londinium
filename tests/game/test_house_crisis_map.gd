extends GutTest

# Houses in a crisis on the map (issue #222, D-108): selecting a locked house opens its tooltip with why it is locked,
# the price and length of a disinfection and the Disinfect button; R (Y on the gamepad) disinfects, and a refused
# demolition says why. Everything comes from the snapshot; the screen holds no rule.

const ROOT: String = "user://test_house_crisis_map"

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


func _view() -> Node2D:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 800)
	add_child_autofree(_viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	view.set("mods_root", ROOT)
	view.set("saves_root", ROOT)
	_viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	return view


func _session(view: Node2D) -> GameSession:
	return view.get("session") as GameSession


func _select(view: Node2D, cell: Vector2i) -> void:
	(view.get("geometry") as MapGeometry).selected = cell
	view.call("_update_mode")


func _tick(view: Node2D) -> void:
	_session(view).simulation.tick()
	_session(view).publish_tick()


func _key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_viewport.push_input(event)


# A house of the player, made sick through the D-054 hook, and the snapshot published. Not one standing at the start:
# those are historic and never demolished anyway (issues #152, #180).
func _sick_house(view: Node2D) -> Vector2i:
	var map: MapDef = _session(view).context.map
	for y: int in range(map.height):
		for x: int in range(map.width):
			var build: BuildCommand = BuildCommand.new(_session(view).context, &"housing", Vector2i(x, y))
			_session(view).simulation.apply_command(build)
			_session(view).simulation.tick()
			if build.accepted:
				assert_true(_session(view).simulation.mark_house_sick(Vector2i(x, y)))
				_session(view).publish_tick()
				return Vector2i(x, y)
	fail_test("No cell takes a house")
	return Vector2i(-1, -1)


func test_a_sick_house_shows_its_tooltip_with_the_price_the_duration_and_the_button() -> void:
	var view: Node2D = await _view()
	var cell: Vector2i = _sick_house(view)
	var tip: PanelContainer = view.get("_crisis_tip") as PanelContainer
	assert_false(tip.visible, "Nothing is selected yet")
	_select(view, cell + Vector2i.ONE)
	assert_true(tip.visible)
	var crisis: Dictionary = _session(view).get_snapshot()["crisis"]
	var text: String = (view.get("_crisis_text") as Label).text
	assert_string_contains(text, Strings.reason(CrisisSystem.HOUSE_SICK))
	assert_string_contains(text, Strings.text(Strings.CRISIS_DISINFECTION) % [Strings.money(crisis["cost"]),
		crisis["duration_seconds"]])
	assert_string_contains(text, Strings.reason(CrisisSystem.OUTSIDE_POST), "No post covers it")
	var button: Button = view.get("_crisis_button") as Button
	assert_true(button.visible)
	assert_true(button.disabled)
	assert_eq(button.text, Strings.text(Strings.CRISIS_DISINFECT))
	_select(view, Vector2i(-1, -1))
	assert_false(tip.visible)


func test_r_asks_for_a_disinfection_and_delete_says_why_the_house_stays() -> void:
	var view: Node2D = await _view()
	var cell: Vector2i = _sick_house(view)
	var status: Label = view.get("_status") as Label
	_select(view, cell)
	_key(KEY_R)
	_tick(view)
	assert_eq(status.text, Strings.command_result(false, CrisisSystem.OUTSIDE_POST))
	_key(KEY_DELETE)
	_tick(view)
	assert_eq(status.text, Strings.command_result(false, CrisisSystem.HOUSE_SICK))
	_session(view).simulation.cure_house(cell)
	_tick(view)
	assert_false((view.get("_crisis_tip") as PanelContainer).visible, "The crisis is over")
