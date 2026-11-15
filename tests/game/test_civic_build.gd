extends GutTest

# The fountain, the well and the cemetery can be picked and built from the map (issue #376, D-089, D-195, D-048): key C
# and the LB/RB cycle reach them, only when they can be built. The Lea Bridge fountain and the atrium never show up.

const ROOT: String = "user://test_civic_build"
const CIVIC: Array[StringName] = [&"public_fountain", &"well", &"cemetery"]
const LEFT_OUT: Array[StringName] = [&"lea_bridge_fountain", &"st_mary_atrium"]
const CYCLE_BOUND: int = 40

var _viewport: SubViewport


func _view(enabled: bool = true) -> Node2D:
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
	if enabled:
		# The historic events and the mourning are off in this scenario's data; they gate the water and the cemetery.
		var params: Params = _session(view).get_params()
		params._modifiers.append(Modifier.new(&"events.enabled", &"set", 1.0))
		params._validated.clear()
		_session(view).simulation._state.mourning_enabled = true
	TaxBase.fund_session(_session(view))
	return view


func _session(view: Node2D) -> GameSession:
	return view.get("session") as GameSession


func _geometry(view: Node2D) -> MapGeometry:
	return view.get("geometry") as MapGeometry


func _key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_viewport.push_input(event)


func _pad(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	_viewport.push_input(event)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	_viewport.push_input(event)


func _tick(view: Node2D) -> void:
	_session(view).simulation.tick()
	_session(view).publish_tick()


func _built(view: Node2D, cell: Vector2i) -> StringName:
	for building: Dictionary in _session(view).get_snapshot()["economy"]["buildings"]:
		if building["cell"] == [cell.x, cell.y]:
			return StringName(building["definition_id"])
	return &""


# The first cell where the type can stand: the data's terrain rules, no street and nothing built on it yet.
func _valid_cell(view: Node2D, type: StringName) -> Vector2i:
	var context: EconomyContext = _session(view).context
	var taken: Array[Vector2i] = []
	for building: Dictionary in _session(view).get_snapshot()["economy"]["buildings"]:
		taken.append_array(context.cells_of(context.area_of(building)))
	for y: int in range(context.map.height):
		for x: int in range(context.map.width):
			var origin: Vector2i = Vector2i(x, y)
			if context.placement_reason(type, origin) != &"":
				continue
			var free: bool = true
			for cell: Vector2i in context.cells_of(Rect2i(origin, context.buildings[type].footprint)):
				free = free and cell not in taken and cell not in context.map.road_cells
			if free:
				return origin
	return Vector2i(-1, -1)


# Presses RB until the type is picked; bounded so a type the cycle never reaches fails instead of hanging.
func _cycle_to(view: Node2D, type: StringName) -> void:
	for press: int in range(CYCLE_BOUND):
		_pad(JOY_BUTTON_RIGHT_SHOULDER)
		if view.get("_building_type") == type:
			return


func _cycle(view: Node2D) -> Array[StringName]:
	var seen: Array[StringName] = []
	for press: int in range(CYCLE_BOUND):
		_pad(JOY_BUTTON_RIGHT_SHOULDER)
		var type: StringName = view.get("_building_type")
		if type in seen:
			break
		seen.append(type)
	return seen


func test_the_keyboard_reaches_and_places_the_three_buildings() -> void:
	var view: Node2D = await _view()
	for expected: StringName in CIVIC:
		_key(KEY_C)
		assert_eq(view.get("_building_type"), expected)
		var cell: Vector2i = _valid_cell(view, expected)
		assert_ne(cell, Vector2i(-1, -1))
		view.call("_submit", view.call("_place_command", cell))
		_tick(view)
		assert_eq(_built(view, cell), expected, "Placed with the keyboard: %s" % expected)
	_key(KEY_C)
	assert_eq(view.get("_building_type"), CIVIC[0], "Key C goes round")


func test_the_gamepad_reaches_and_places_the_three_buildings() -> void:
	var view: Node2D = await _view()
	for expected: StringName in CIVIC:
		_cycle_to(view, expected)
		assert_eq(view.get("_building_type"), expected)
		var cell: Vector2i = _valid_cell(view, expected)
		assert_ne(cell, Vector2i(-1, -1))
		_geometry(view).selected = cell
		_pad(JOY_BUTTON_A)
		_tick(view)
		assert_eq(_built(view, cell), expected, "Placed with the gamepad: %s" % expected)


func test_the_cycle_has_them_only_when_they_can_be_built() -> void:
	var on: Node2D = await _view()
	var seen_on: Array[StringName] = _cycle(on)
	for type: StringName in CIVIC:
		assert_true(type in seen_on, "%s is in the cycle" % type)
		assert_eq(_session(on).get_building_unavailable_reason(type), &"")
	on.queue_free()
	var off: Node2D = await _view(false)
	var seen_off: Array[StringName] = _cycle(off)
	for type: StringName in CIVIC:
		var reason: StringName = _session(off).get_building_unavailable_reason(type)
		assert_ne(reason, &"", "%s cannot be built here" % type)
		assert_false(type in seen_off, "%s is not in the cycle without a way to build it" % type)


func test_a_civic_building_that_cannot_be_built_says_why_with_key_c() -> void:
	var view: Node2D = await _view(false)
	_key(KEY_C)
	assert_eq(view.get("_building_type"), &"", "Nothing is picked")
	assert_ne(_session(view).get_building_unavailable_reason(CIVIC[0]), &"")


func test_the_preplaced_buildings_are_in_no_cycle() -> void:
	var view: Node2D = await _view()
	for type: StringName in _cycle(view):
		assert_false(type in LEFT_OUT, "%s is not a choice" % type)
	for press: int in range(CIVIC.size() + 1):
		_key(KEY_C)
		assert_false(view.get("_building_type") in LEFT_OUT)
	for press: int in range(view.call("_service_types").size() + 1):
		_key(KEY_0)
		assert_false(view.get("_building_type") in LEFT_OUT)
	assert_false(view.get("TYPES").any(func(type: StringName) -> bool: return type in LEFT_OUT))


func test_the_current_keys_do_not_change() -> void:
	var view: Node2D = await _view()
	var types: Array = view.get("TYPES")
	for index: int in range(types.size()):
		_key(KEY_1 + index)
		var reason: StringName = _session(view).get_building_unavailable_reason(types[index])
		assert_eq(view.get("_building_type"), types[index] if reason == &"" else &"", "Key %d" % (index + 1))
	_key(KEY_9)
	assert_eq(view.get("_building_type"), &"" if _session(view).get_building_unavailable_reason(GameSession.ROAD) != &"" else GameSession.ROAD)
	_key(KEY_ESCAPE)
	for expected: StringName in [&"fire_station", &"health_post", &"police_station", &"fire_station"]:
		_key(KEY_0)
		assert_eq(view.get("_building_type"), expected)
