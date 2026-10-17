extends GutTest

# Steam Deck resolution (issue #68, D-048): the game opens at 1280×800 and, at that size, the help fits in the
# header beside the panel and no row of the panel asks for more than its width, in both languages and with either
# help (keyboard or gamepad).

const WIDTH: int = 1280
const HEIGHT: int = 800
const ROOT: String = "user://test_layout_1280x800"


func after_each() -> void:
	Strings.use_default_locale()


func _view() -> Node2D:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(WIDTH, HEIGHT)
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	view.set("mods_root", ROOT)
	view.set("saves_root", ROOT)
	viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	return view


func test_window_opens_at_steam_deck_resolution() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), WIDTH)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), HEIGHT)


func test_help_fits_beside_the_panel_in_both_languages_and_inputs() -> void:
	var view: Node2D = await _view()
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var help: Label = view.get("_help") as Label
	var block: Control = help.get_parent() as Control
	var room: Vector2 = Vector2(WIDTH - presentation.layout["panel_width"] - presentation.layout["help_x"],
		presentation.layout["header_height"] - presentation.layout["help_y"])
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		for gamepad: bool in [false, true]:
			view.set("_gamepad", gamepad)
			view.call("_update_help")
			await get_tree().process_frame
			assert_lte(block.get_rect().end.x, float(WIDTH) - presentation.layout["panel_width"],
				"Help stops short of the panel (%s, gamepad %s)" % [locale, gamepad])
			assert_lte(block.get_combined_minimum_size().x, room.x, "Help width (%s, gamepad %s)" % [locale, gamepad])
			assert_lte(block.get_combined_minimum_size().y, room.y, "Help height (%s, gamepad %s)" % [locale, gamepad])


func test_panel_rows_fit_its_width_in_both_languages() -> void:
	var view: Node2D = await _view()
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var panel: StatsPanel = view.get("_stats_panel") as StatsPanel
	var room: float = presentation.layout["panel_width"] - 2.0 * presentation.layout["panel_margin"]
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		await get_tree().process_frame
		for node: Node in panel.find_children("*", "HBoxContainer", true, false):
			var row: HBoxContainer = node as HBoxContainer
			assert_lte(row.get_combined_minimum_size().x, room, "Row %s (%s)" % [row.get_path(), locale])
