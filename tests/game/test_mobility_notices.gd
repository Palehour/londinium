extends GutTest

# Issue #352: the notice of posts lost to promotions and the demotion countdown in the stats panel. Snapshots are
# built by hand from the contract (GameSession.get_mobility_events(), demotion.seconds_left / missing_goods in the
# snapshot). The game data now has approved values (60/60/2); tests below override them to exercise edge cases.

# A session whose mobility events are the ones the test sets, the way the simulation would report them.
class EventSession:
	extends GameSession
	var events: Dictionary = {}


	func get_mobility_events() -> Dictionary:
		return events


# The real parameters, except for the ui.mobility.* keys the test overrides to exercise pending/off behaviour.
class KnobParams:
	extends Params
	var knobs: Dictionary[StringName, Variant] = {}


	func has_value(key: StringName) -> bool:
		return knobs.has(key) or super.has_value(key)


	func get_value(key: StringName) -> Variant:
		return knobs[key] if knobs.has(key) else super.get_value(key)


const NO_DATA: String = "sin dato"

var _catalog: DataCatalog
var _session: EventSession
var _clock: SimClock
var _panel: StatsPanel
var _knobs: KnobParams


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_knobs = KnobParams.new(_catalog, RoleDef.new())
	_session = EventSession.new(_catalog, _knobs)
	_clock = SimClock.new()
	_clock.simulation = _session.simulation
	add_child_autofree(_clock)
	_clock.set_process(false)
	_panel = StatsPanel.new()
	_panel.setup(_session, _clock)
	add_child_autofree(_panel)


func _set_knobs(window: Variant, warning: Variant, listed: Variant) -> void:
	_knobs.knobs[MobilityNoticeWindow.KEY_WINDOW] = window
	_knobs.knobs[MobilityNoticeWindow.KEY_WARNING] = warning
	_knobs.knobs[MobilityNoticeWindow.KEY_MAX_BUILDINGS] = listed


func _events(tick: int, employed: int, buildings: Array) -> Dictionary:
	return {"tick": tick, "employed_promoted": employed, "buildings": buildings}


func _lost(id: String, definition_id: StringName, workers: int) -> Dictionary:
	return {"id": id, "definition_id": definition_id, "workers_lost": workers}


func _artisans(population: int, below: int, left: int, missing: Array) -> Dictionary:
	return {"classes": {&"artisan": {
		"categories": [], "housing": {"building": &"artisan_housing", "base": 10, "bonus": 0, "max_bonus": 0},
		"population": population, "satisfaction": {"current": 0.0},
		"mobility": {"from": &"worker",
			"promotion": {"active": true, "blockers": [], "per_minute": 2.0},
			"demotion": {"active": left <= 0, "category": &"comunidad", "seconds_below": below,
				"seconds_required": below + left, "seconds_left": left, "missing_goods": missing, "per_minute": 2.0}},
	}}}


func _show(events: Dictionary, needs: Dictionary = {}) -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	_session.events = events
	if not needs.is_empty():
		snapshot["needs"] = needs
	_panel.update_snapshot(snapshot)


func _labor() -> EraNotice:
	return _panel.get("_labor_box") as EraNotice


func _countdown() -> EraNotice:
	return _panel.get("_demotion_box") as EraNotice


func _lost_text(workers: int) -> String:
	return Strings.text(Strings.LABOR_NOTICE) % workers


func _building_line(definition_id: StringName, workers: int) -> String:
	return Strings.text(Strings.LABOR_BUILDING) % [Strings.building_label(String(definition_id)), workers]


# --- Posts lost -----------------------------------------------------------------------------------------------

func test_sums_the_window_and_counts_a_repeated_tick_once() -> void:
	_set_knobs(60, 30, 5)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]))
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]))
	_show(_events(20, 1, [_lost("b1", &"bakery", 1)]))
	assert_true(_labor().visible)
	assert_eq(_labor().body.text, "\n".join([_lost_text(3), _building_line(&"bakery", 3)]))


func test_nothing_shows_when_only_the_unemployed_rose() -> void:
	_set_knobs(60, 30, 5)
	_show(_events(10, 0, []))
	assert_false(_labor().visible, "N = 0: no notice")


func test_ticks_outside_the_window_drop_out() -> void:
	_set_knobs(60, 30, 5)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]))
	_show(_events(69, 0, []))
	assert_true(_labor().visible, "59 s later it still counts")
	_show(_events(70, 0, []))
	assert_false(_labor().visible, "60 s later the window has passed")


func test_the_list_is_cut_at_the_limit_and_says_how_many_are_left() -> void:
	_set_knobs(60, 30, 2)
	_show(_events(10, 6, [_lost("w", &"wharf", 1), _lost("m", &"mill", 3), _lost("b", &"bakery", 2)]))
	_show(_events(11, 1, [_lost("br", &"brewery", 1)]))
	assert_eq(_labor().body.text, "\n".join([_lost_text(7), _building_line(&"wharf", 1), _building_line(&"mill", 3),
		Strings.text(Strings.LABOR_MORE) % 2]), "The first two reported, in the order the simulation gave them")


func test_a_new_game_starts_the_window_over() -> void:
	_set_knobs(600, 30, 5)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]))
	assert_true(_labor().visible)
	_session.restart()
	_clock.simulation = _session.simulation
	_show(_events(15, 0, []))
	assert_false(_labor().visible, "The restart forgot the old losses")


func test_a_new_simulation_at_the_same_tick_does_not_count_as_a_repeat() -> void:
	_set_knobs(600, 30, 5)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]))
	_session.restart()
	_clock.simulation = _session.simulation
	_show(_events(10, 3, [_lost("m1", &"mill", 3)]))
	assert_eq(_labor().body.text, "\n".join([_lost_text(3), _building_line(&"mill", 3)]), "Only the new game's losses")


func test_restart_on_default_data_keeps_notices_on() -> void:
	_set_knobs(60, 30, 5)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]), _artisans(4, 40, 20, [&"beer"]))
	assert_true(_labor().visible)
	assert_true(_countdown().visible)
	_session.restart_with(Params.new(_catalog, RoleDef.new()), DataLayers.NORMAL)
	_clock.simulation = _session.simulation
	_show(_events(11, 2, [_lost("b1", &"bakery", 2)]), _artisans(4, 40, 20, [&"beer"]))
	assert_true(_labor().visible, "The new game's data has the approved window: on")
	assert_true(_countdown().visible, "The new game's data has the approved warning seconds: on")


func test_a_tick_that_goes_back_starts_the_window_over() -> void:
	var window: MobilityNoticeWindow = MobilityNoticeWindow.new()
	window.record(_events(50, 2, [_lost("b1", &"bakery", 2)]), 600)
	window.record(_events(3, 1, [_lost("b1", &"bakery", 1)]), 600)
	assert_eq(window.summary(5)["total"], 1)


# --- Demotion countdown -----------------------------------------------------------------------------------------

func test_countdown_appears_from_the_limit_on_and_names_the_beer() -> void:
	_set_knobs(60, 20, 5)
	_show({}, _artisans(4, 40, 21, [&"beer"]))
	assert_false(_countdown().visible, "21 s left, the limit is 20")
	_show({}, _artisans(4, 41, 20, [&"beer"]))
	assert_true(_countdown().visible, "20 s left is inside the limit")
	assert_eq(_countdown().body.text, Strings.text(Strings.DEMOTION_COUNTDOWN) % [20,
		Strings.label(Strings.GOOD_LABELS, &"beer").to_lower(), Strings.label(Strings.CLASS_LABELS, &"artisan").to_lower(),
		Strings.label(Strings.CLASS_LABELS, &"worker").to_lower()])
	assert_string_contains(_countdown().body.text, "20")


func test_countdown_with_a_limit_of_a_minute_or_more_waits_for_the_clock_to_run() -> void:
	_set_knobs(60, 60, 5)
	_show({}, _artisans(4, 0, 60, [&"beer"]))
	assert_false(_countdown().visible, "Nothing is short: the clock is at zero")
	_show({}, _artisans(4, 1, 59, [&"beer"]))
	assert_true(_countdown().visible)
	_show({}, _artisans(4, 59, 1, [&"beer"]))
	assert_true(_countdown().visible, "At 59 s it still can be recovered")
	_show({}, _artisans(4, 0, 60, [&"beer"]))
	assert_false(_countdown().visible, "The beer came back: the countdown goes away")


func test_countdown_is_hidden_without_artisans_and_stays_at_zero_while_they_fall() -> void:
	_set_knobs(60, 60, 5)
	_show({}, _artisans(0, 30, 30, [&"beer"]))
	assert_false(_countdown().visible)
	_show({}, _artisans(0, 60, 0, [&"beer"]))
	assert_false(_countdown().visible, "Nobody left to fall")
	_show({}, _artisans(4, 60, 0, [&"beer"]))
	assert_true(_countdown().visible, "The fall is under way with artisans left")
	assert_string_contains(_countdown().body.text, Strings.text(Strings.DEMOTION_COUNTDOWN).split("%d")[0] + "0")


func test_countdown_names_the_category_when_no_good_is_listed() -> void:
	_set_knobs(60, 60, 5)
	_show({}, _artisans(4, 10, 50, []))
	assert_string_contains(_countdown().body.text, Strings.label(Strings.CATEGORY_LABELS, &"comunidad").to_lower())


func test_both_notices_show_together() -> void:
	_set_knobs(60, 30, 5)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]), _artisans(4, 40, 20, [&"beer"]))
	assert_true(_labor().visible)
	assert_true(_countdown().visible)


# --- Knobs without data -----------------------------------------------------------------------------------------

func test_knobs_without_data_switch_their_notice_off() -> void:
	_set_knobs(NO_DATA, NO_DATA, NO_DATA)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]), _artisans(4, 59, 1, [&"beer"]))
	assert_false(_labor().visible)
	assert_false(_countdown().visible)
	_set_knobs(60, NO_DATA, 5)
	_show(_events(11, 1, [_lost("b1", &"bakery", 1)]), _artisans(4, 59, 1, [&"beer"]))
	assert_true(_labor().visible, "The labour notice does not depend on the countdown knob")
	assert_false(_countdown().visible)
	_set_knobs(NO_DATA, 30, 5)
	_show(_events(12, 1, [_lost("b1", &"bakery", 1)]), _artisans(4, 59, 1, [&"beer"]))
	assert_false(_labor().visible, "Without a window nothing is counted")
	assert_true(_countdown().visible)


func test_a_list_size_below_one_switches_the_labour_notice_off() -> void:
	_set_knobs(60, 30, 0)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]))
	assert_false(_labor().visible)


func test_a_list_size_without_data_switches_the_labour_notice_off() -> void:
	_set_knobs(60, 30, NO_DATA)
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]))
	assert_false(_labor().visible)


func test_the_real_game_data_turns_the_notices_on() -> void:
	_session.restart_with(Params.new(_catalog, RoleDef.new()), DataLayers.NORMAL)
	_clock.simulation = _session.simulation
	_show(_events(10, 2, [_lost("b1", &"bakery", 2)]), _artisans(4, 59, 1, [&"beer"]))
	assert_true(_labor().visible, "Approved window and list size show the labour notice")
	assert_true(_countdown().visible, "Approved warning seconds show the demotion countdown")


func test_the_real_session_reports_its_events_outside_the_snapshot() -> void:
	var session: GameSession = GameSession.new(_catalog, Params.new(_catalog, RoleDef.new()))
	session.simulation.tick()
	var events: Dictionary = session.get_mobility_events()
	assert_eq(events["tick"], 1, "The counter of the simulation, tick by tick")
	assert_eq(events["employed_promoted"], 0)
	assert_eq(events["buildings"], [])
	assert_false(session.get_snapshot().has("mobility_events"), "A transient reading stays out of the saved state")
	events["employed_promoted"] = 9
	assert_eq(session.get_mobility_events()["employed_promoted"], 0, "A copy: the panel cannot change the simulation")


func test_the_real_session_feeds_the_panel_without_errors() -> void:
	var session: GameSession = GameSession.new(_catalog, Params.new(_catalog, RoleDef.new()))
	_clock.simulation = session.simulation
	var panel: StatsPanel = StatsPanel.new()
	panel.setup(session, _clock)
	add_child_autofree(panel)
	session.simulation.tick()
	panel.update_snapshot(session.get_snapshot())
	assert_false((panel.get("_labor_box") as EraNotice).visible, "Data without values: off")


func test_the_real_game_data_has_approved_knob_values() -> void:
	var params: Params = Params.new(_catalog, RoleDef.new())
	assert_true(params.has_value(MobilityNoticeWindow.KEY_WINDOW))
	assert_true(params.has_value(MobilityNoticeWindow.KEY_WARNING))
	assert_true(params.has_value(MobilityNoticeWindow.KEY_MAX_BUILDINGS))
	assert_eq(params.get_value(MobilityNoticeWindow.KEY_WINDOW), 60)
	assert_eq(params.get_value(MobilityNoticeWindow.KEY_WARNING), 60)
	assert_eq(params.get_value(MobilityNoticeWindow.KEY_MAX_BUILDINGS), 2)


func test_read_knob_takes_numbers_and_nothing_else() -> void:
	_set_knobs(0, 7.0, NO_DATA)
	assert_eq(MobilityNoticeWindow.read_knob(_knobs, MobilityNoticeWindow.KEY_WINDOW), 0)
	assert_eq(MobilityNoticeWindow.read_knob(_knobs, MobilityNoticeWindow.KEY_WARNING), 7)
	assert_eq(MobilityNoticeWindow.read_knob(_knobs, MobilityNoticeWindow.KEY_MAX_BUILDINGS), MobilityNoticeWindow.PENDING)
	assert_eq(MobilityNoticeWindow.read_knob(_knobs, MobilityNoticeWindow.KEY_MAX_BUILDINGS, 1), MobilityNoticeWindow.PENDING)
	assert_eq(MobilityNoticeWindow.read_knob(null, MobilityNoticeWindow.KEY_WINDOW), MobilityNoticeWindow.PENDING)
	_set_knobs(0, 7.0, 0)
	assert_eq(MobilityNoticeWindow.read_knob(_knobs, MobilityNoticeWindow.KEY_MAX_BUILDINGS, 1), MobilityNoticeWindow.PENDING)


# --- Period skin (D-181) ----------------------------------------------------------------------------------------

func test_the_notices_wear_the_period_skin() -> void:
	for box: EraNotice in [_labor(), _countdown(), _panel.get("_notice_box") as EraNotice]:
		var style: StyleBox = box.get_theme_stylebox("panel")
		assert_true(style is StyleBoxFlat)
		assert_eq((style as StyleBoxFlat).bg_color, EraNotice.PAPER)
		assert_eq(box.body.get_theme_color("font_color"), EraNotice.INK)
