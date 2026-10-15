extends GutTest

const DEMO: String = "scenarios/victorian_demo.json"
const REVENUE: StringName = &"victory.victorian_demo.revenue.threshold"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "scenarios"]:
		for name: String in DirAccess.open("res://data/" + folder).get_files():
			if name.ends_with(".json"):
				var path: String = folder.path_join(name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func test_demo_stages_load_as_structure_with_numeric_params() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	var stages: Array = loaded.catalog.scenarios[&"victorian_demo"]["stages"]
	assert_eq(stages.size(), 3)
	assert_eq(stages[1]["class_id"], &"artisan")
	assert_false(stages[0].has("threshold"), "numbers live only in Params")
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	assert_eq(params.get_value(REVENUE), 250)
	assert_eq(params.get_value(&"victory.victorian_demo.revenue.required_minutes"), 30)
	assert_eq(params.get_value(&"victory.victorian_demo.population.duration_seconds"), 120)
	assert_eq(params.get_value(&"victory.victorian_demo.artisans.duration_seconds"), 300)


func test_missing_victory_disables_objectives_and_scenarios_are_optional() -> void:
	_documents[DEMO] = {}
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	assert_eq(result.catalog.scenarios[&"victorian_demo"]["stages"], [])
	_documents.erase(DEMO)
	result = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	assert_true(result.catalog.scenarios.is_empty())


func test_rejects_invalid_values_in_data_and_after_role_modifiers() -> void:
	var invalid: Dictionary[String, Array] = {"threshold": [-1, 0.5, INF, NAN],
		"required_minutes": [0, -1, 1.5, INF, NAN]}
	for field: String in invalid:
		for value: Variant in invalid[field]:
			before_each()
			_documents[DEMO]["victory"]["stages"][2][field] = value
			assert_false(DataLoader.new().load_documents(_documents).is_ok(), "%s=%s" % [field, value])
			before_each()
			_documents["roles/neutral_administrator.json"]["modifiers"] = [
				{"key": "victory.victorian_demo.revenue." + field, "op": "set", "value": value}]
			assert_false(DataLoader.new().load_documents(_documents).is_ok(), "modified %s=%s" % [field, value])
	for stage: int in [0, 1]:
		for value: Variant in [0, -1, 0.5, INF, NAN]:
			before_each()
			_documents[DEMO]["victory"]["stages"][stage]["duration_seconds"] = value
			assert_false(DataLoader.new().load_documents(_documents).is_ok())


func test_valid_role_modifier_applies_and_scenarios_do_not_share_keys() -> void:
	_documents["scenarios/other.json"] = _documents[DEMO].duplicate(true)
	_documents["scenarios/other.json"]["victory"]["stages"][2]["threshold"] = 100
	_documents["roles/neutral_administrator.json"]["modifiers"] = [{"key": String(REVENUE), "op": "add", "value": 10}]
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		var params: Params = Params.new(result.catalog, result.catalog.roles[&"neutral_administrator"])
		assert_eq(params.get_value(REVENUE), 260)
		assert_eq(params.get_value(&"victory.other.revenue.threshold"), 100)


func test_rejects_unknown_metrics_classes_duplicates_and_empty_stages() -> void:
	for change: Dictionary in [{"metric": "money"}, {"mode": "unknown"}, {"class_id": "missing"}, {"id": "population"}]:
		before_each()
		_documents[DEMO]["victory"]["stages"][1].merge(change, true)
		assert_false(DataLoader.new().load_documents(_documents).is_ok(), str(change))
	_documents[DEMO]["victory"]["stages"] = []
	assert_false(DataLoader.new().load_documents(_documents).is_ok())


func test_unknown_fields_and_missing_fields_are_rejected() -> void:
	_documents[DEMO]["victory"]["stages"][2]["tolerance"] = 1
	assert_false(DataLoader.new().load_documents(_documents).is_ok())
	before_each()
	_documents[DEMO]["victory"]["stages"][2].erase("required_minutes")
	assert_false(DataLoader.new().load_documents(_documents).is_ok())
