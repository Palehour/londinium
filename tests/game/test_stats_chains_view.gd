extends GutTest

# Chains view on the pad (issue #315, D-173). One chain on screen. LB/RB still changes tab. The D-pad ←/→ switches
# chain and ↑/↓ walks the links, without wrapping and without a detail. Text is at least 16 px, on one line, and the
# screen fits 1280×800. The highlight border is the colour from stats.json only where the logic marks the link.

const ROOT: String = "user://test_stats_chains_view"
const MIN_FONT_SIZE: int = 16

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


func test_the_pad_walks_both_chains_and_every_link_at_the_steam_deck_size() -> void:
	var view: Node2D = await _view()
	var tab: ChainsTab = await _open_chains(view)
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	var simulation: Simulation = (view.get("session") as GameSession).simulation
	assert_eq(tab.chain_index(), 0)
	assert_eq(tab.link_index(), 0)
	await _check_link(tab, screen, simulation)
	_pad(JOY_BUTTON_DPAD_DOWN)
	await _check_link(tab, screen, simulation)
	_pad(JOY_BUTTON_DPAD_DOWN)
	await _check_link(tab, screen, simulation)
	assert_eq(tab.link_index(), 2, "Walks the three links")
	_pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(tab.link_index(), 2, "Does not wrap past the last link")
	_pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(tab.chain_index(), 1, "Right goes to the beer chain")
	assert_eq(tab.link_index(), 0, "A new chain starts on its first link")
	await _check_link(tab, screen, simulation)
	_pad(JOY_BUTTON_DPAD_DOWN)
	await _check_link(tab, screen, simulation)
	_pad(JOY_BUTTON_DPAD_DOWN)
	await _check_link(tab, screen, simulation)
	assert_eq(tab.link_index(), 2, "Stops on the last beer link")
	_pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(tab.link_index(), 2, "Does not wrap past the last link")
	_pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(tab.chain_index(), 1, "Does not wrap past the last chain")
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(tab.chain_index(), 0, "Left stops on the first chain")
	var children: int = tab.get_child_count()
	var link: int = tab.link_index()
	_pad(JOY_BUTTON_A)
	await get_tree().process_frame
	assert_eq(tab.get_child_count(), children, "A does not open a detail")
	assert_eq(tab.link_index(), link)
	_pull(JOY_AXIS_TRIGGER_LEFT)
	await get_tree().process_frame
	await _check_link(tab, screen, simulation)
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		await get_tree().process_frame
		assert_eq(tab.titles.text, Strings.label(Strings.STATS_SCREEN_CHAIN_NAMES, &"bread"))


# The mark of issue #353 on the tab itself, with the simulation's reading faked: one bread row with the stroke and
# the cause line under the chain, none on beer, and nothing on no data or no bottleneck.
func test_the_tab_marks_one_bread_row_with_its_cause_and_never_beer() -> void:
	var tab: ChainsTab = _standalone_tab({"ten_minutes": _reading(StatsChains.STATUS_BOTTLENECK, &"mill")})
	assert_eq(_stroked_rows(tab), [1], "Only the mill row has the highlight stroke")
	assert_true(tab.cause.visible)
	assert_eq(tab.cause.text, Strings.text(Strings.STATS_SCREEN_CHAINS_CAUSE) % Strings.building_label("mill"))
	assert_gte(tab.cause.get_theme_font_size(&"font_size"), MIN_FONT_SIZE)
	assert_ne(tab.cause.autowrap_mode, TextServer.AUTOWRAP_OFF, "The cause wraps, so it is not cut")
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_RIGHT
	event.pressed = true
	tab.handle(event)
	assert_eq(tab.chain_index(), 1)
	assert_eq(_stroked_rows(tab), [], "Beer shows no stroke")
	assert_false(tab.cause.visible, "Beer shows no cause line")
	assert_eq(tab.cause.text, "")


func test_the_tab_marks_nothing_without_data_or_without_a_bottleneck() -> void:
	for status: StringName in [StatsChains.STATUS_NO_DATA, StatsChains.STATUS_NO_BOTTLENECK]:
		var tab: ChainsTab = _standalone_tab({"ten_minutes": _reading(status, &"mill")})
		assert_eq(_stroked_rows(tab), [], "%s has no stroke" % status)
		assert_true(tab.cause.visible)
	var calm: ChainsTab = _standalone_tab({"ten_minutes": _reading(StatsChains.STATUS_NO_BOTTLENECK, &"")})
	assert_eq(calm.cause.text, Strings.text(Strings.STATS_SCREEN_CHAINS_NO_BOTTLENECK))
	var blank: ChainsTab = _standalone_tab({})
	assert_eq(blank.cause.text, Strings.text(Strings.STATS_SCREEN_NO_DATA))


func test_a_contradicting_bread_cause_does_not_draw_a_stroke() -> void:
	var tab: ChainsTab = _standalone_tab({"ten_minutes": _reading(StatsChains.STATUS_BOTTLENECK, &"bakery")},
		[{"definition_id": &"wharf", "reason": &"wheat_purchases_disabled"}])
	assert_eq(_stroked_rows(tab), [2], "The bakery, not the wharf that bread_causes names")


func test_the_wharf_cause_shows_the_split_and_the_imported_flour() -> void:
	var reading: Dictionary = _reading(StatsChains.STATUS_BOTTLENECK, &"wharf")
	reading["barley_percent"] = 100.0
	reading["imported_flour_uses_capacity"] = true
	var tab: ChainsTab = _standalone_tab({"ten_minutes": reading})
	assert_eq(_stroked_rows(tab), [0])
	assert_true(tab.cause.text.contains(Strings.text(Strings.STATS_SCREEN_CHAINS_IMPORTS_TAKE)), tab.cause.text)
	assert_true(tab.cause.text.contains("100 %"), tab.cause.text)
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		tab.refresh()
		assert_false(tab.cause.text.is_empty())
		assert_false(tab.cause.text.contains("ui.stats_screen"), "Both locales have the text")


class FakeSim extends Simulation:
	var bottlenecks: Dictionary = {}
	var causes: Array = []


	func snapshot(ranges: Array[Dictionary] = []) -> Dictionary:
		var data: Dictionary = super.snapshot(ranges)
		data["chain_bottlenecks"] = bottlenecks
		data["diagnostics"]["bread_causes"] = causes
		return data


func _standalone_tab(bottlenecks: Dictionary, causes: Array = []) -> ChainsTab:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var params: Params = SimTestParams.isolated_params(loaded.catalog)
	var context: EconomyContext = EconomyContext.new(loaded.catalog, loaded.catalog.maps[&"whitechapel_1850s"])
	var session: GameSession = GameSession.new(loaded.catalog, params)
	var fake: FakeSim = FakeSim.new(params, EconomyState.new(), 1, context)
	fake.bottlenecks = bottlenecks
	fake.causes = causes
	session.simulation = fake
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	var tab: ChainsTab = ChainsTab.new()
	add_child_autofree(tab)
	tab.setup(session, look)
	tab.refresh()
	return tab


func _reading(status: StringName, link: StringName) -> Dictionary:
	return {"status": status, "limiting_link": link, "reason": &"", "barley_percent": 0.0,
		"imported_flour_uses_capacity": false}


# Indexes of the visible rows drawn with the highlight stroke.
func _stroked_rows(tab: ChainsTab) -> Array[int]:
	var found: Array[int] = []
	for index: int in tab.readings.size():
		var row: PanelContainer = tab.readings[index].get_parent() as PanelContainer
		if not row.visible:
			continue
		var style: StyleBoxFlat = row.get_theme_stylebox(&"panel") as StyleBoxFlat
		if style.border_color == tab.presentation.chains_highlight_color \
				and style.get_border_width(SIDE_LEFT) == int(tab.presentation.chains_highlight_width):
			found.append(index)
	return found


func _check_link(tab: ChainsTab, screen: StatsScreen, simulation: Simulation) -> void:
	var entry: Dictionary = tab.presentation.history_ranges[tab.get("_range")]
	var built: Dictionary = StatsChains.build(simulation, tab.presentation.chains_order, tab.chain_index(),
		entry["span_seconds"], entry["tier"])
	var columns: Array[StringName] = []
	for column: Dictionary in tab.presentation.chains_columns:
		columns.append(column["id"])
	await get_tree().process_frame
	assert_lte(screen.get_combined_minimum_size().x, 1280.0)
	assert_lte(screen.get_combined_minimum_size().y, 800.0)
	var index: int = tab.link_index()
	var label: Label = tab.readings[index]
	var link: Dictionary = built["links"][index]
	assert_eq(label.text, StatsChains.reading(link, columns))
	assert_gte(label.get_theme_font_size(&"font_size"), MIN_FONT_SIZE)
	assert_eq(label.get_line_count(), 1, label.text)
	var style: StyleBoxFlat = (label.get_parent() as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	if link["highlighted"]:
		assert_eq(style.border_color, tab.presentation.chains_highlight_color)
		assert_eq(style.get_border_width(SIDE_LEFT), int(tab.presentation.chains_highlight_width))
	elif index == tab.link_index():
		assert_eq(style.border_color, tab.presentation.colors["cursor"])
	else:
		assert_eq(style.get_border_width(SIDE_LEFT), 0)


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


func _open_chains(view: Node2D) -> ChainsTab:
	((view.get("_stats_panel") as StatsPanel).get("_stats_button") as Button).pressed.emit()
	await get_tree().process_frame
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	await get_tree().process_frame
	return (view.get("_stats_screen") as StatsScreen).get("_chains") as ChainsTab


func _pad(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	_viewport.push_input(event)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	_viewport.push_input(event)


func _pull(axis: JoyAxis) -> void:
	for value: float in [1.0, 0.0]:
		var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
		event.axis = axis
		event.axis_value = value
		_viewport.push_input(event)
