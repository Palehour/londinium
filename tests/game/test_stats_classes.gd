extends GutTest

# Statistics screen, classes view (issue #83, D-052): the city's satisfaction over a range of the chapter, stacked
# by class. Each layer is a class's satisfaction weighted by its share of the residents, read from the series of
# #82 (D-066) without adding any. The D-pad walks the buckets and the triggers change the range.

const ROOT: String = "user://test_stats_classes"
# Seven minutes: 42 closed buckets of the medium level and 7 of the chapter's.
const TICKS: int = 420
# The demo, left alone, empties before it is lost to depopulation at 8 min; at 2 min it still has residents.
const PEOPLED_TICKS: int = 120

var _catalog: DataCatalog
var _viewport: SubViewport


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func after_each() -> void:
	Strings.use_default_locale()


func _simulation(ticks: int) -> Simulation:
	var simulation: Simulation = GameSession.new(_catalog, Params.new(_catalog, RoleDef.new())).simulation
	for tick: int in ticks:
		simulation.tick()
	return simulation


func _ranges() -> Array[Dictionary]:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	return look.history_ranges


func _build(simulation: Simulation, range_index: int) -> Dictionary:
	var entry: Dictionary = _ranges()[range_index]
	return StatsClasses.build(simulation, entry["tier"], entry["span_seconds"])


# The newest bucket of one series of a class, read straight from the history.
func _latest(simulation: Simulation, metric: StringName, class_member: StringName, tier: StringName) -> float:
	for def: Dictionary in simulation.stats_series_defs():
		if def["metric"] == metric and def["dimensions"][&"class"] == class_member:
			return simulation.stats_series(def["id"], tier)["mean"][-1]
	return NAN


func _members(simulation: Simulation) -> Array[StringName]:
	var found: Array[StringName] = []
	for def: Dictionary in simulation.stats_series_defs():
		if def["metric"] == &"satisfaction":
			found.append(def["dimensions"][&"class"])
	return found


func test_one_layer_per_class_in_the_data_order() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var labels: Array[String] = []
	for member: StringName in _members(simulation):
		labels.append(Strings.label(Strings.CLASS_LABELS, member))
	assert_gte(labels.size(), 2, "The victorian era has workers and artisans")
	var found: Array[String] = []
	for line: Dictionary in _build(simulation, 0)["lines"]:
		found.append(line["label"])
	assert_eq(found, labels)


func test_layers_add_up_to_the_satisfaction_of_the_average_resident() -> void:
	var simulation: Simulation = _simulation(PEOPLED_TICKS)
	var weighted: float = 0.0
	var people: float = 0.0
	for member: StringName in _members(simulation):
		var population: float = _latest(simulation, &"population", member, StatsHistory.TIER_MEDIUM)
		weighted += _latest(simulation, &"satisfaction", member, StatsHistory.TIER_MEDIUM) * population
		people += population
	assert_gt(people, 0.0, "The demo still has residents at 2 min")
	var chart: Dictionary = _build(simulation, 0)
	var top: float = 0.0
	for line: Dictionary in chart["lines"]:
		top += line["values"][-1]
	assert_almost_eq(top, weighted / people, 0.01)
	assert_almost_eq(chart["total"][-1], weighted / people, 0.01)


func test_a_layer_is_the_class_satisfaction_times_its_share_of_residents() -> void:
	var layers: Array[PackedFloat32Array] = StatsClasses.layers(
		[PackedFloat32Array([60.0, 80.0]), PackedFloat32Array([90.0, 50.0])] as Array[PackedFloat32Array],
		[PackedFloat32Array([30.0, 10.0]), PackedFloat32Array([10.0, 0.0])] as Array[PackedFloat32Array])
	assert_almost_eq(layers[0][0], 45.0, 0.001, "60 × 30/40")
	assert_almost_eq(layers[1][0], 22.5, 0.001, "90 × 10/40")
	assert_almost_eq(layers[0][1], 80.0, 0.001, "The only class with people is the whole city")
	assert_eq(layers[1][1], 0.0, "A class without residents adds nothing, whatever its score")


func test_a_bucket_without_residents_or_data_is_a_gap() -> void:
	var layers: Array[PackedFloat32Array] = StatsClasses.layers(
		[PackedFloat32Array([60.0, 60.0, NAN]), PackedFloat32Array([90.0, 90.0, 90.0])] as Array[PackedFloat32Array],
		[PackedFloat32Array([0.0, NAN, 5.0]), PackedFloat32Array([0.0, 5.0, 5.0])] as Array[PackedFloat32Array])
	for bucket: int in 3:
		for layer: int in 2:
			assert_true(is_nan(layers[layer][bucket]), "Bucket %d, layer %d" % [bucket, layer])


func test_each_range_reads_its_level_over_its_span() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var ten: Dictionary = _build(simulation, 0)
	assert_eq((ten["lines"][0]["values"] as PackedFloat32Array).size(), 42, "7 min of 10 s buckets")
	assert_eq(ten["bucket_seconds"], 10)
	var whole: Dictionary = _build(simulation, 2)
	assert_eq(whole["bucket_seconds"], 60, "The whole chapter is the minute level")
	assert_eq(whole["first_bucket"], 0)
	var member: StringName = _members(simulation)[0]
	assert_almost_eq(whole["lines"][0]["satisfaction"][-1],
		_latest(simulation, &"satisfaction", member, StatsHistory.TIER_CHAPTER), 0.01)


func test_reading_names_the_city_and_each_class() -> void:
	var chart: Dictionary = {"total": PackedFloat32Array([67.5]), "lines": [
		{"label": "A", "values": PackedFloat32Array([45.0]), "satisfaction": PackedFloat32Array([60.0]),
			"share": PackedFloat32Array([0.75])},
		{"label": "B", "values": PackedFloat32Array([22.5]), "satisfaction": PackedFloat32Array([90.0]),
			"share": PackedFloat32Array([0.25])},
	] as Array[Dictionary]}
	assert_eq(StatsClasses.reading(chart, 0), " · ".join([Strings.text(Strings.STATS_SCREEN_CLASSES_CITY) % 67.5,
		Strings.text(Strings.STATS_SCREEN_CLASSES_CLASS) % ["A", 60.0, 75.0],
		Strings.text(Strings.STATS_SCREEN_CLASSES_CLASS) % ["B", 90.0, 25.0]]))
	chart["total"] = PackedFloat32Array([NAN])
	assert_eq(StatsClasses.reading(chart, 0), "", "No residents, no reading")


func test_building_the_classes_view_leaves_the_game_unchanged() -> void:
	var simulation: Simulation = _simulation(120)
	# Compared as bytes: an empty bucket holds NaN, which is never equal to itself.
	var before: PackedByteArray = var_to_bytes(simulation.to_save())
	for range_index: int in _ranges().size():
		_build(simulation, range_index)
	assert_eq(var_to_bytes(simulation.to_save()), before)


func test_presentation_reads_the_fill_of_the_layers() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	assert_eq(look.errors, [] as Array[String])
	assert_gt(look.fill_alpha, 0.0)
	assert_lte(look.fill_alpha, 1.0)
	var bad: StatsPresentation = StatsPresentation.new()
	bad.validate({"summary": {}, "layout": {}, "colors": {}, "strokes": [{"color": "#ffffff", "dash": 0}],
		"classes": {"fill_alpha": 1.5}})
	assert_true(bad.errors.has("data/ui/stats.json.classes.fill_alpha: expected more than 0 and at most 1"))


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


func _pad(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	_viewport.push_input(event)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	_viewport.push_input(event)


func _trigger(axis: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	_viewport.push_input(event)


# The screen on its classes tab, after two minutes of play.
func _classes(view: Node2D) -> ClassesTab:
	((view.get("_stats_panel") as StatsPanel).get("_stats_button") as Button).pressed.emit()
	var session: GameSession = view.get("session") as GameSession
	for tick: int in 120:
		session.simulation.tick()
	session.publish_tick()
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	return (view.get("_stats_screen") as StatsScreen).get("_classes") as ClassesTab


func test_rb_twice_goes_to_the_classes_and_the_dpad_walks_the_buckets() -> void:
	var view: Node2D = await _view()
	var classes: ClassesTab = _classes(view)
	var tabs: TabContainer = (view.get("_stats_screen") as StatsScreen).get("_tabs") as TabContainer
	assert_eq(tabs.current_tab, StatsScreen.CLASSES_TAB)
	assert_eq(classes.cursor_index(), 11, "On the newest of twelve buckets")
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(classes.cursor_index(), 9)
	var chart: Dictionary = classes.get("_chart") as Dictionary
	assert_eq((classes.get("_reading") as Label).text, Strings.text(Strings.STATS_SCREEN_HISTORY_READING)
		% ["1:40", StatsClasses.reading(chart, 9)], "Reads the bucket that ends at 1:40")


func test_a_trigger_pull_changes_the_range_of_the_classes() -> void:
	var view: Node2D = await _view()
	var classes: ClassesTab = _classes(view)
	_trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
	assert_eq(classes.get("_range"), 2, "Two pulls: the whole chapter")
	assert_eq((classes.get("_chart") as Dictionary)["bucket_seconds"], 60)
	assert_eq(view.get("_building_type"), &"", "The map behind does not take them")


func test_classes_fit_the_steam_deck_screen() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	var classes: ClassesTab = _classes(view)
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		await get_tree().process_frame
		assert_lte(screen.get_combined_minimum_size().x, 1280.0, "Width (%s)" % locale)
		assert_lte(screen.get_combined_minimum_size().y, 800.0, "Height (%s)" % locale)
	assert_true(classes.visible)
