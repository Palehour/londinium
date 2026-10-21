extends GutTest

# Tierra de época on the map (issue #178, D-083): free land is drawn by its 1870 lot style, the damaged wharf is drawn
# with what repairing costs, and R (Y on the gamepad) on any of its cells repairs it. The cost and which wharves can be
# repaired come from the snapshot; the screen holds no rule.

const ROOT: String = "user://test_period_land_map"
const DAMAGED_WHARF: Vector2i = Vector2i(28, 14)
# Another cell of the same 2x2 footprint (D-086): repairing works from any of them.
const DAMAGED_WHARF_CORNER: Vector2i = Vector2i(29, 15)
const PLAIN_RIVER: Vector2i = Vector2i(26, 14)

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


func _geometry(view: Node2D) -> MapGeometry:
	return view.get("geometry") as MapGeometry


func _select(view: Node2D, cell: Vector2i) -> void:
	_geometry(view).selected = cell
	view.call("_update_mode")


func _tick(view: Node2D) -> void:
	_session(view).simulation.tick()
	_session(view).publish_tick()


func _press(view: Node2D, event: InputEvent) -> void:
	event.set("pressed", true)
	_viewport.push_input(event)
	var release: InputEvent = event.duplicate()
	release.set("pressed", false)
	_viewport.push_input(release)


func _key(view: Node2D, keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	_press(view, event)


func _pad(view: Node2D, button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	_press(view, event)


func _wharf_at(view: Node2D, cell: Vector2i) -> Dictionary:
	for building: Dictionary in _session(view).get_snapshot()["economy"]["buildings"]:
		if building["cell"] == [cell.x, cell.y] and building["definition_id"] == &"wharf":
			return building
	return {}


func _repair_cost(view: Node2D) -> int:
	return int(_session(view).get_snapshot()["repair"]["wharves"][0]["cost"])


func test_every_lot_style_of_the_maps_has_a_colour_and_a_name() -> void:
	var catalog: DataCatalog = DataLoader.new().load_all().catalog
	var presentation: MapPresentation = MapPresentation.new()
	var ids: Array[StringName] = []
	ids.assign(catalog.buildings.keys())
	presentation.load_data(ids)
	assert_true(presentation.errors.is_empty(), str(presentation.errors))
	for map: MapDef in catalog.maps.values():
		for cell: Vector2i in map.lot_styles:
			var style: StringName = map.lot_styles[cell]
			assert_true(presentation.lot_colors.has(style), "%s: %s has a colour" % [map.id, style])
			assert_false(presentation.lot_labels.get(style, "").is_empty(), "%s: %s has a name" % [map.id, style])
	var seen: Array[Color] = [presentation.terrain["land"], presentation.terrain["cultivable"]]
	for style: StringName in presentation.lot_colors:
		assert_false(presentation.lot_colors[style] in seen, "%s is told apart from the other lots" % style)
		seen.append(presentation.lot_colors[style])


func test_a_lot_without_its_colour_fails_cleanly() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/map.json"))
	raw["lot_styles"].erase("garden")
	raw["colors"].erase("damaged_wharf")
	var presentation: MapPresentation = MapPresentation.new()
	presentation.validate(raw, [])
	assert_eq(presentation.errors.size(), 2, str(presentation.errors))


func test_the_selected_lot_and_the_damaged_wharf_and_its_cost_show_in_the_mode_line() -> void:
	var view: Node2D = await _view()
	var map: MapDef = _session(view).context.map
	var lot: Vector2i = map.lot_styles.keys()[0]
	_select(view, lot)
	var mode: Label = view.get("_mode") as Label
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	assert_string_contains(mode.text, presentation.lot_labels[map.lot_styles[lot]])
	_select(view, DAMAGED_WHARF_CORNER)
	assert_string_contains(mode.text, Strings.text(Strings.REPAIR_HINT) % Strings.money(_repair_cost(view)))
	_select(view, PLAIN_RIVER)
	assert_false(mode.text.contains(Strings.text(Strings.DAMAGED_WHARF)), "A plain river cell offers no repair")


func test_r_on_any_cell_of_the_damaged_wharf_repairs_it_for_its_cost() -> void:
	var view: Node2D = await _view()
	var cost: int = _repair_cost(view)
	_select(view, DAMAGED_WHARF_CORNER)
	_key(view, KEY_R)
	_tick(view)
	assert_false(_wharf_at(view, DAMAGED_WHARF).is_empty(), "The ruin became a wharf at its north-west corner")
	assert_eq(_wharf_at(view, DAMAGED_WHARF).get("paid"), cost, "It paid the cost the map showed")
	assert_eq(_session(view).get_snapshot()["repair"]["wharves"], [])
	var mode: Label = view.get("_mode") as Label
	assert_false(mode.text.contains(Strings.text(Strings.DAMAGED_WHARF)), "Nothing left to repair there")


func test_y_on_the_gamepad_repairs_the_damaged_wharf() -> void:
	var view: Node2D = await _view()
	view.set("_gamepad", true)
	_select(view, DAMAGED_WHARF)
	assert_string_contains((view.get("_mode") as Label).text,
		Strings.text(Strings.REPAIR_HINT_GAMEPAD) % Strings.money(_repair_cost(view)), "The hint names the Y button")
	_pad(view, JOY_BUTTON_Y)
	_tick(view)
	assert_false(_wharf_at(view, DAMAGED_WHARF).is_empty())


func test_r_elsewhere_says_why_nothing_is_repaired() -> void:
	var view: Node2D = await _view()
	_select(view, PLAIN_RIVER)
	_key(view, KEY_R)
	_tick(view)
	assert_eq((view.get("_status") as Label).text, Strings.command_result(false, &"not_damaged_wharf"))
	assert_true(_wharf_at(view, PLAIN_RIVER).is_empty())
	assert_eq(_session(view).get_snapshot()["repair"]["wharves"].size(), 1, "The damaged wharf is still there")
