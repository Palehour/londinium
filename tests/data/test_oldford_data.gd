extends GutTest

# Issue #202, task 2b (D-090): the Old Ford mission's data. Its card carries Chronicler's fields (tag, sources,
# liberties) without [A VERIFICAR], its goal reads mission.min_water_d, and the weights of prep add up to 1.

const MISSION: String = "eras/victorian/missions/oldford.json"
const EVENTS: String = "economy/events.json"
const UNVERIFIED: String = "[A VERIFICAR]"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "eras/victorian/missions"]:
		for name: String in DirAccess.open("res://data/" + folder).get_files():
			if name.ends_with(".json"):
				var path: String = folder.path_join(name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _loaded() -> DataLoadResult:
	return DataLoader.new().load_documents(_documents)


func _assert_invalid(message: String) -> void:
	var loaded: DataLoadResult = _loaded()
	assert_false(loaded.is_ok())
	assert_has(loaded.errors, message)


func test_the_mission_loads_with_its_trigger_goal_and_card() -> void:
	var loaded: DataLoadResult = _loaded()
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	var mission: MissionDef = loaded.catalog.missions[&"oldford"]
	assert_eq(mission.trigger_id, &"cholera_1866_warning")
	assert_eq(mission.closes_at_key, &"events.cholera.trigger_min")
	assert_eq(mission.goal_metric, &"water")
	assert_eq(mission.goal_key, &"mission.min_water_d")
	assert_eq(mission.card["tag"], "[DEBATED]")
	assert_gt(mission.card["sources"].size(), 0)
	assert_true(mission.card["liberties"].any(func(text: String) -> bool:
		return text.begins_with("mortalidad exagerada para el juego")))
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	for key: String in ["mission.oldford.duration_min", "events.cholera.trigger_min", "mission.min_water_d",
			"cholera.fail_mortality", "cholera.vacancy_min", "cholera.recovery_mult", "cholera.recovery_min"]:
		assert_not_null(params.get_value(StringName(key)), key)
	assert_eq(params.get_value(&"mission.oldford.duration_min"), 6.5)
	assert_eq(params.get_value(&"mission.min_water_d"), 0.6)
	assert_eq(params.get_value(&"cholera.fail_mortality"), 0.25)


func test_no_text_of_the_mission_or_the_game_is_unverified() -> void:
	assert_false(FileAccess.get_file_as_string("res://data/" + MISSION).contains(UNVERIFIED))
	assert_false(FileAccess.get_file_as_string("res://locale/ui.csv").contains(UNVERIFIED))


func test_a_card_tagged_unverified_is_rejected() -> void:
	_documents[MISSION]["card"]["tag"] = UNVERIFIED
	_assert_invalid("%s.card.tag: %s is not allowed" % [MISSION, UNVERIFIED])


func test_a_card_without_sources_is_rejected() -> void:
	_documents[MISSION]["card"]["sources"] = []
	_assert_invalid("%s.card.sources: expected a nonempty list of texts" % MISSION)


func test_a_goal_naming_an_unknown_key_is_rejected() -> void:
	_documents[MISSION]["goal"]["at_least"] = "mission.no_such_key"
	_assert_invalid("%s.goal.at_least: unknown parameter mission.no_such_key" % MISSION)


func test_the_prep_weights_must_add_up_to_one() -> void:
	_documents[EVENTS]["prep"]["w_health"] = 0.25
	_assert_invalid("%s.prep: the weights must add up to 1" % EVENTS)
	before_each()
	_documents[EVENTS]["prep"]["w_health"] = 0.2005
	assert_true(_loaded().is_ok(), "Within 0.001")


func test_the_ranges_of_the_issue() -> void:
	for case: Array in [["economy/mission.json", "min_water_d", 0.29], ["economy/mission.json", "min_water_d", 0.91],
			["economy/cholera.json", "fail_mortality", 0.51], ["economy/cholera.json", "vacancy_min", 11],
			["economy/cholera.json", "recovery_mult", 0.9], ["economy/cholera.json", "recovery_mult", 3.1],
			["economy/cholera.json", "recovery_min", 0.5], ["economy/cholera.json", "recovery_min", 16]]:
		before_each()
		_documents[case[0]][case[1]] = case[2]
		assert_false(_loaded().is_ok(), str(case))
	before_each()
	_documents[EVENTS]["cholera"]["trigger_min"] = 24
	assert_false(_loaded().is_ok(), "trigger_min under 25")


# The mod of the manual check (#202): copied into user://mods/, it turns the events on and brings the outbreak to the
# earliest minute of its range, so the warning of Bromley comes sooner.
func test_the_manual_check_mod_turns_the_events_on() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", DataLoader.DEFAULT_ERA, "res://tests/mods")
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	assert_true(params.get_value(&"events.enabled"))
	assert_eq(params.get_value(&"events.cholera.trigger_min"), 25.0)


# Issue #209: the cut names the district source it falls on, one a map district can drink from.
func test_the_cut_names_a_known_water_source() -> void:
	var loaded: DataLoadResult = _loaded()
	assert_true(loaded.is_ok(), str(loaded.errors))
	if loaded.is_ok():
		assert_eq(loaded.catalog.missions[&"oldford"].effects[&"started"][0]["source"], &"old_ford")
	_documents[MISSION]["on_started"][0]["source"] = "nowhere"
	_assert_invalid("%s.on_started[0].source: expected one of %s" % [MISSION, MapDef.WATER_SOURCES])
