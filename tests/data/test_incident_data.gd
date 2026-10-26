extends GutTest

# Issue #87, task 2 (D-119, D-121, D-122): incidents/<attribute>.json holds the pressure of one district attribute and
# its causes, every value with a range. Each scenario says whether it has incidents, off unless it switches them on:
# the scenarios of before keep them off and the trial one has them. The health post keeps a single radius (D-121).

const SAFETY: String = "incidents/safety.json"
const LESSONS: String = "incidents/lessons.json"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services", "incidents", "scenarios"]:
		for name: String in DirAccess.open("res://data/" + folder).get_files():
			if name.ends_with(".json"):
				var path: String = folder.path_join(name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _load() -> DataLoadResult:
	return DataLoader.new().load_documents(_documents)


func _assert_invalid(message: String) -> void:
	var loaded: DataLoadResult = _load()
	assert_false(loaded.is_ok())
	assert_has(loaded.errors, message)


func test_every_attribute_has_its_incident_file_read_through_params() -> void:
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		var raw: Dictionary = _documents["incidents/%s.json" % attribute]
		for field: String in DataLoader.INCIDENT_FIELDS:
			assert_eq(float(params.get_value(StringName("incident.%s.%s" % [attribute, field]))), float(raw[field]),
				"%s.%s" % [attribute, field])
		for cause: Dictionary in raw["causes"]:
			assert_eq(float(params.get_value(StringName("incident.%s.cause.%s" % [attribute, cause["id"]]))),
				float(cause["per_unit_per_min"]))


func test_the_three_causes_of_the_task_are_in_the_data() -> void:
	var found: Array[StringName] = []
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		for cause: Dictionary in _documents["incidents/%s.json" % attribute]["causes"]:
			if StringName(cause["id"]) not in found:
				found.append(StringName(cause["id"]))
	found.sort()
	var expected: Array[StringName] = IncidentSystem.CAUSES.duplicate()
	expected.sort()
	assert_eq(found, expected)


func test_a_value_out_of_its_range_is_rejected() -> void:
	_documents[SAFETY]["k"] = 0.5
	_assert_invalid("%s.k: invalid fraction value 0.5" % SAFETY)


func test_a_warning_above_the_top_is_rejected() -> void:
	_documents[SAFETY]["warning_threshold"] = _documents[SAFETY]["pressure_max"] + 1
	_assert_invalid("%s.warning_threshold: must be <= pressure_max" % SAFETY)


func test_an_unknown_cause_is_rejected() -> void:
	_documents[SAFETY]["causes"].append({"id": "gin_palaces", "per_unit_per_min": 1})
	_assert_invalid("%s.causes[1].id: expected one of %s, once" % [SAFETY, IncidentSystem.CAUSES])


func test_a_file_for_an_unknown_attribute_is_rejected() -> void:
	_documents["incidents/fire.json"] = _documents[SAFETY].duplicate(true)
	_assert_invalid("incidents/fire.json: expected safety, health or order")


func test_a_missing_field_is_rejected() -> void:
	_documents[SAFETY].erase("pressure_drop")
	_assert_invalid("%s.pressure_drop: missing field" % SAFETY)


func test_the_scenarios_of_before_have_no_incidents_and_the_trial_one_has_them() -> void:
	var scenarios: Dictionary[StringName, Dictionary] = _load().catalog.scenarios
	assert_false(scenarios[&"victorian_demo"]["incidents_enabled"])
	assert_false(scenarios[&"whitechapel_full"]["incidents_enabled"])
	assert_true(scenarios[&"incidents_trial"]["incidents_enabled"])


func test_a_scenario_without_the_switch_has_no_incidents() -> void:
	_documents["scenarios/whitechapel_full.json"].erase("incidents_enabled")
	assert_false(_load().catalog.scenarios[&"whitechapel_full"]["incidents_enabled"])


func test_the_switch_must_be_a_boolean() -> void:
	_documents["scenarios/incidents_trial.json"]["incidents_enabled"] = 1
	_assert_invalid("scenarios/incidents_trial.json.incidents_enabled: expected a boolean")


# D-121: one radius, the post's service_radius_m along the streets; the crisis has no radius of its own.
func test_the_crisis_has_no_radius_of_its_own() -> void:
	assert_false(_documents["economy/crisis.json"]["health"].has("post_radius_m"))
	assert_false(_load().catalog.base_values.has(&"crisis.health.post_radius_m"))
	_documents["economy/crisis.json"]["health"]["post_radius_m"] = 150
	_assert_invalid("economy/crisis.json.health.post_radius_m: unknown field")


func test_the_tavern_tag_is_known() -> void:
	assert_has(_load().catalog.buildings[&"brewery"].tags, IncidentSystem.TAVERN_TAG)


# Issue #87, task 3 (D-120): incidents/lessons.json holds the severity of the crisis and what each lesson takes off it,
# every value read through Params with its range.
func test_the_lessons_file_is_read_through_params() -> void:
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	var raw: Dictionary = _documents[LESSONS]
	assert_eq(raw.keys().size(), DataLoader.LESSON_FIELDS.size())
	for field: String in DataLoader.LESSON_FIELDS:
		assert_eq(float(params.get_value(StringName("incident.lessons.%s" % field))), float(raw[field]), field)


func test_a_severity_base_above_2_is_rejected() -> void:
	_documents[LESSONS]["severity_base"] = 2.5
	_assert_invalid("%s.severity_base: invalid number value 2.5" % LESSONS)


func test_a_lesson_value_or_cap_above_1_is_rejected() -> void:
	_documents[LESSONS]["lesson_value"] = 1.5
	_documents[LESSONS]["lesson_cap"] = 1.2
	_assert_invalid("%s.lesson_value: invalid fraction value 1.5" % LESSONS)
	_assert_invalid("%s.lesson_cap: invalid fraction value 1.2" % LESSONS)


func test_a_missing_lesson_field_is_rejected() -> void:
	_documents[LESSONS].erase("lesson_cap")
	_assert_invalid("%s.lesson_cap: missing field" % LESSONS)


func test_the_lessons_file_is_required() -> void:
	_documents.erase(LESSONS)
	_assert_invalid("%s: missing file" % LESSONS)
