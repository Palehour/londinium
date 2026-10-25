extends GutTest

# The service buildings on the map (issue #87, D-118): key 0 goes through them, selecting one opens its tooltip with
# its attribute and the bar of its availability, and selecting a house shows its district's attributes. Everything
# comes from the snapshot; the screen holds no rule.

const ROOT: String = "user://test_service_tooltip"

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


func _key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_viewport.push_input(event)


# The first cell, row by row, that takes the building, and the snapshot published.
func _build(view: Node2D, id: StringName) -> Vector2i:
	var map: MapDef = _session(view).context.map
	for y: int in range(map.height):
		for x: int in range(map.width):
			var build: BuildCommand = BuildCommand.new(_session(view).context, id, Vector2i(x, y))
			_session(view).simulation.apply_command(build)
			_session(view).simulation.tick()
			if build.accepted:
				_session(view).publish_tick()
				return Vector2i(x, y)
	fail_test("No cell takes a %s" % id)
	return Vector2i(-1, -1)


func test_key_0_goes_through_the_services() -> void:
	var view: Node2D = await _view()
	for expected: StringName in [&"fire_station", &"health_post", &"police_station", &"fire_station"]:
		_key(KEY_0)
		assert_eq(view.get("_building_type"), expected)


func test_a_service_shows_its_attribute_and_its_availability_bar() -> void:
	var view: Node2D = await _view()
	var cell: Vector2i = _build(view, &"health_post")
	var tip: PanelContainer = view.get("_service_tip") as PanelContainer
	assert_false(tip.visible, "Nothing is selected yet")
	_select(view, cell + Vector2i.ONE)
	assert_true(tip.visible)
	var title: String = (view.get("_service_title") as Label).text
	assert_string_contains(title, Strings.building_label("health_post"))
	assert_string_contains(title, Strings.text(Strings.SERVICE_ATTRIBUTES[ServiceSystem.HEALTH]))
	assert_string_contains(title, Strings.text(Strings.SERVICE_ICONS[ServiceSystem.HEALTH]))
	var bar: ProgressBar = view.get("_service_bar") as ProgressBar
	var top: float = float(_session(view).get_snapshot()["services"]["buildings"][0]["availability_max"])
	assert_true(bar.visible)
	assert_eq(bar.max_value, top)
	assert_eq(bar.value, top)
	assert_true(_session(view).simulation.consume_service(cell, 50.0))
	_session(view).publish_tick()
	assert_eq(bar.value, top - 50.0)
	assert_eq((view.get("_service_text") as Label).text,
		Strings.text(Strings.SERVICE_AVAILABILITY) % [roundi(top - 50.0), roundi(top)])


func test_a_house_shows_its_district_attributes() -> void:
	var view: Node2D = await _view()
	var cell: Vector2i = _build(view, &"housing")
	_select(view, cell)
	assert_true((view.get("_service_tip") as PanelContainer).visible)
	assert_false((view.get("_service_bar") as ProgressBar).visible)
	var house: Dictionary = {}
	for entry: Dictionary in _session(view).get_snapshot()["services"]["houses"]:
		if entry["cell"] == [cell.x, cell.y]:
			house = entry
	var district: Dictionary = _session(view).get_snapshot()["services"]["districts"][house["district"]]
	var text: String = (view.get("_service_text") as Label).text
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		assert_string_contains(text, Strings.text(Strings.SERVICE_VALUE) % [
			Strings.text(Strings.SERVICE_ATTRIBUTES[attribute]), roundi(float(district[attribute]))])
