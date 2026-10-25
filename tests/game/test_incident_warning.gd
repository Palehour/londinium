extends GutTest

# The small incidents on the map (issue #87, D-119, D-122): `--scenario=<id>` plays another scenario of data/, and on
# the trial one a selected house shows its district's pressure and, once it reaches the threshold, the warning. With
# the incidents off the tooltip is the one of before. Everything comes from the snapshot; the screen holds no rule.

const ROOT: String = "user://test_incident_warning"
const TRIAL: StringName = &"incidents_trial"
const MAX_MINUTES: int = 60

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


func _view(scenario: StringName = &"") -> Node2D:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 800)
	add_child_autofree(_viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	view.set("mods_root", ROOT)
	view.set("saves_root", ROOT)
	if scenario != &"":
		view.set("scenario_id", scenario)
	_viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	return view


func _session(view: Node2D) -> GameSession:
	return view.get("session") as GameSession


func _select(view: Node2D, cell: Vector2i) -> void:
	(view.get("geometry") as MapGeometry).selected = cell
	view.call("_update_mode")


# The first cell, row by row, that takes a house with a street beside it.
func _build_house(view: Node2D) -> Vector2i:
	var map: MapDef = _session(view).context.map
	for y: int in range(map.height):
		for x: int in range(map.width):
			var build: BuildCommand = BuildCommand.new(_session(view).context, &"housing", Vector2i(x, y))
			_session(view).simulation.apply_command(build)
			_session(view).simulation.tick()
			if build.accepted:
				_session(view).publish_tick()
				return Vector2i(x, y)
	fail_test("No cell takes a house")
	return Vector2i(-1, -1)


func _text(view: Node2D) -> String:
	return (view.get("_service_text") as Label).text


func test_the_scenario_flag_picks_a_scenario_of_the_data() -> void:
	var catalog: DataCatalog = DataLoader.new().load_all().catalog
	assert_eq(MapView.launch_scenario(catalog, &"victorian_demo", ["--scenario=incidents_trial"]), TRIAL)
	assert_eq(MapView.launch_scenario(catalog, &"victorian_demo", ["--scenario=atlantis"]), &"victorian_demo")
	assert_eq(MapView.launch_scenario(catalog, &"victorian_demo", []), &"victorian_demo")


func test_with_the_incidents_off_a_house_shows_no_pressure() -> void:
	var view: Node2D = await _view()
	_select(view, _build_house(view))
	assert_false(_session(view).get_snapshot()["incidents"]["enabled"])
	assert_false(_text(view).contains(Strings.text(Strings.INCIDENT_PRESSURE) % ""))


func test_on_the_trial_scenario_a_house_shows_the_pressure_and_then_the_warning() -> void:
	var view: Node2D = await _view(TRIAL)
	# Defeats off: a city with only a house starves and stops ticking before the warning.
	var catalog: DataCatalog = view.get("_catalog") as DataCatalog
	_session(view).restart_with(Params.new(catalog, catalog.roles[&"neutral_administrator"],
		[Modifier.new(&"defeat.enabled", &"set", 0.0)] as Array[Modifier]), DataLayers.NORMAL)
	var cell: Vector2i = _build_house(view)
	_select(view, cell)
	assert_true(_session(view).get_snapshot()["incidents"]["enabled"])
	assert_string_contains(_text(view), Strings.text(Strings.INCIDENT_PRESSURE) % "")
	assert_false(_text(view).contains(Strings.text(Strings.INCIDENT_WARNING) % ""), "Not at the start")
	var district: StringName = &""
	for house: Dictionary in _session(view).get_snapshot()["services"]["houses"]:
		if house["cell"] == [cell.x, cell.y]:
			district = StringName(house["district"])
	var warned: bool = false
	for minute: int in range(MAX_MINUTES):
		for tick: int in range(SimTime.TICKS_PER_MINUTE):
			_session(view).simulation.tick()
		var safety: Dictionary = _session(view).simulation.snapshot()["incidents"]["districts"][district][ServiceSystem.SAFETY]
		if safety["warning"]:
			warned = true
			break
	assert_true(warned, "Without services the pressure reaches the warning")
	_session(view).publish_tick()
	view.call("_update_mode")
	assert_string_contains(_text(view), Strings.text(Strings.INCIDENT_WARNING)
		% Strings.text(Strings.SERVICE_ATTRIBUTES[ServiceSystem.SAFETY]))
