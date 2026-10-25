extends GutTest

# Statistics screen, summary view (issue #83, D-052): six cards read from the series of #82 (D-066) without adding
# any; fear and debt have no series yet, so they say there is no data. The screen takes the map's input while it
# shows: the shoulders change tab and B goes back.

const ROOT: String = "user://test_stats_screen"
# Two minutes: twelve closed buckets of the medium level.
const TICKS: int = 120

var _catalog: DataCatalog
var _viewport: SubViewport


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func after_each() -> void:
	Strings.use_default_locale()


func _simulation(ticks: int) -> Simulation:
	var session: GameSession = GameSession.new(_catalog, Params.new(_catalog, RoleDef.new()))
	for tick: int in ticks:
		session.simulation.tick()
	return session.simulation


func _card(cards: Array[Dictionary], id: StringName) -> Dictionary:
	return cards[StatsSummary.CARDS.find(id)]


func _medium(simulation: Simulation, id: StringName, field: String) -> PackedFloat32Array:
	return simulation.stats_series(id, StatsHistory.TIER_MEDIUM)[field]


func _ids(simulation: Simulation, metric: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for def: Dictionary in simulation.stats_series_defs():
		if def["metric"] == metric:
			found.append(def["id"])
	return found


func test_presentation_data_loads() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	assert_eq(look.errors, [] as Array[String])
	assert_gte(look.layout["font_size"], 16.0, "Text of 16 px or more on the Steam Deck")
	assert_gt(look.summary_span_seconds, 0)


func test_presentation_rejects_bad_data() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.validate({"summary": {"span_seconds": 0}, "layout": {}, "colors": {"background": "nope"},
		"strokes": [{"color": "#ffffff", "dash": -1}]})
	assert_true(look.errors.has("data/ui/stats.json.summary.span_seconds: invalid positive value"))
	assert_true(look.errors.has("data/ui/stats.json.colors.background: invalid color"))
	assert_true(look.errors.has("data/ui/stats.json.strokes.0.dash: expected a length of 0 or more"))


func test_strokes_differ_by_dash_as_well_as_colour() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	assert_ne(look.stroke_dash(0), look.stroke_dash(1), "Two lines of a card never share a stroke")
	assert_ne(look.stroke_color(0), look.stroke_color(1))


func test_summary_has_the_six_cards_in_order() -> void:
	var cards: Array[Dictionary] = StatsSummary.build(_simulation(TICKS), 600)
	var ids: Array[StringName] = []
	for card: Dictionary in cards:
		ids.append(card["id"])
	assert_eq(ids, StatsSummary.CARDS)


func test_population_card_adds_every_class() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var expected: float = 0.0
	for id: StringName in _ids(simulation, &"population"):
		expected += _medium(simulation, id, "mean")[-1]
	var card: Dictionary = _card(StatsSummary.build(simulation, 600), &"population")
	assert_eq(card["lines"].size(), 1)
	assert_almost_eq(card["lines"][0]["values"][-1], expected, 0.01)
	assert_eq(card["value"], str(roundi(expected)))


func test_balance_card_is_income_minus_expense_per_minute() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var net: float = 0.0
	for id: StringName in _ids(simulation, &"income"):
		net += _medium(simulation, id, "total")[-1]
	for id: StringName in _ids(simulation, &"expense"):
		net -= _medium(simulation, id, "total")[-1]
	var bucket_seconds: int = simulation.stats_series(&"money", StatsHistory.TIER_MEDIUM)["bucket_seconds"]
	var card: Dictionary = _card(StatsSummary.build(simulation, 600), &"balance")
	assert_almost_eq(card["lines"][0]["values"][-1], net * 60.0 / bucket_seconds, 0.01)
	assert_ne(net, 0.0, "The demo has a balance to show")


func test_satisfaction_card_has_one_line_per_class() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var card: Dictionary = _card(StatsSummary.build(simulation, 600), &"satisfaction")
	var ids: Array[StringName] = _ids(simulation, &"satisfaction")
	assert_eq(card["lines"].size(), ids.size())
	assert_eq(card["lines"][0]["label"], Strings.label(Strings.CLASS_LABELS, &"worker"))
	assert_almost_eq(card["lines"][0]["values"][-1], _medium(simulation, ids[0], "mean")[-1], 0.01)


func test_coverage_card_shows_bread_and_beer_in_percent() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var card: Dictionary = _card(StatsSummary.build(simulation, 600), &"coverage")
	assert_eq(card["lines"].size(), 2)
	assert_eq(card["lines"][1]["label"], Strings.label(Strings.GOOD_LABELS, &"beer"))
	assert_almost_eq(card["lines"][0]["values"][-1], _medium(simulation, &"coverage:bread", "mean")[-1] * 100.0, 0.01)


func test_fear_and_debt_have_no_series_to_draw() -> void:
	var cards: Array[Dictionary] = StatsSummary.build(_simulation(TICKS), 600)
	for id: StringName in [&"fear", &"debt"]:
		assert_eq(_card(cards, id)["lines"].size(), 0, "%s draws nothing" % id)
		assert_eq(_card(cards, id)["value"], "")


func test_summary_window_keeps_only_the_last_span() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var card: Dictionary = _card(StatsSummary.build(simulation, 30), &"population")
	assert_eq(card["lines"][0]["values"].size(), 3, "30 s of 10 s buckets")


func test_before_the_first_bucket_there_is_no_reading() -> void:
	var card: Dictionary = _card(StatsSummary.build(_simulation(5), 600), &"population")
	assert_eq(card["lines"].size(), 1, "The chart is there, waiting")
	assert_eq(card["value"], "")


func test_building_the_summary_leaves_the_game_unchanged() -> void:
	var simulation: Simulation = _simulation(TICKS)
	# Compared as bytes: an empty bucket holds NaN, which is never equal to itself.
	var before: PackedByteArray = var_to_bytes(simulation.to_save())
	StatsSummary.build(simulation, 600)
	assert_eq(var_to_bytes(simulation.to_save()), before)


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


func _open(view: Node2D) -> StatsScreen:
	((view.get("_stats_panel") as StatsPanel).get("_stats_button") as Button).pressed.emit()
	return view.get("_stats_screen") as StatsScreen


func test_panel_button_opens_the_screen_and_b_goes_back() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	assert_false(screen.visible, "Hidden until asked for")
	_open(view)
	assert_true(screen.visible)
	_pad(JOY_BUTTON_B)
	assert_false(screen.visible)


func test_shoulders_change_tab_instead_of_the_building() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _open(view)
	var tabs: TabContainer = screen.get("_tabs") as TabContainer
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(view.get("_building_type"), &"", "The map does not cycle buildings behind the screen")
	assert_eq(tabs.current_tab, StatsScreen.HISTORY_TAB, "RB goes on to the next view")


func test_fear_card_says_no_data_in_both_languages() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _open(view)
	var fear: int = StatsSummary.CARDS.find(&"fear")
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		await get_tree().process_frame
		assert_eq((screen.get("_values") as Array)[fear].text, Strings.text(Strings.STATS_SCREEN_NO_DATA))
		assert_false((screen.get("_charts") as Array)[fear].visible, "No chart is drawn for it")


func test_summary_fits_the_steam_deck_screen() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _open(view)
	var session: GameSession = view.get("session") as GameSession
	for tick: int in TICKS:
		session.simulation.tick()
	session.publish_tick()
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		await get_tree().process_frame
		assert_lte(screen.get_combined_minimum_size().x, 1280.0, "Width (%s)" % locale)
		assert_lte(screen.get_combined_minimum_size().y, 800.0, "Height (%s)" % locale)
