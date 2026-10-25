extends GutTest

# Issue #63, task 1 (D-090): a mission file is structure plus numbers, and the numbers become Params keys
# `mission.<id>.*` like the victory stages, so a role, preset or mod reaches them too.

const PATH: String = "eras/victorian/missions/drill.json"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		for name: String in DirAccess.open("res://data/" + folder).get_files():
			if name.ends_with(".json"):
				var path: String = folder.path_join(name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	_documents[PATH] = {
		"duration_min": 6.5,
		"defeat_pause": "events.cholera.defeat_pause",
		"goal": {"metric": "population", "at_least": 40},
		"on_completed": [{"type": "money", "pence": 500}],
		"on_failed": [],
		"on_abandoned": [],
	}


func test_mission_loads_as_structure_with_numeric_params() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	var mission: MissionDef = loaded.catalog.missions[&"drill"]
	assert_eq(mission.defeat_pause, &"events.cholera.defeat_pause")
	assert_eq(mission.goal_metric, &"population")
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	assert_eq(params.get_value(&"mission.drill.duration_min"), 6.5)
	assert_eq(params.get_value(&"mission.drill.goal.at_least"), 40)
	assert_eq(params.get_value(&"mission.drill.on_completed.0.pence"), 500)
	assert_eq(params.get_value(&"events.cholera.defeat_pause"), true)


func test_data_without_missions_loads() -> void:
	_documents.erase(PATH)
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_true(loaded.catalog.missions.is_empty())


func test_rejects_broken_missions() -> void:
	# Each break, and the part of the file its error must name.
	var broken: Dictionary[String, Array] = {
		"unknown metric": [func(raw: Dictionary) -> void: raw["goal"]["metric"] = "happiness", ".goal.metric"],
		"unknown effect": [func(raw: Dictionary) -> void: raw["on_failed"] = [{"type": "plague"}], ".on_failed[0].type"],
		"negative reward": [func(raw: Dictionary) -> void: raw["on_completed"][0]["pence"] = -1,
			".on_completed[0].pence"],
		"zero duration": [func(raw: Dictionary) -> void: raw["duration_min"] = 0, ".duration_min"],
		"missing outcome": [func(raw: Dictionary) -> void: raw.erase("on_abandoned"), ".on_abandoned: missing field"],
		"unknown pause key": [func(raw: Dictionary) -> void: raw["defeat_pause"] = "events.nothing", ".defeat_pause"],
		"numeric pause key": [func(raw: Dictionary) -> void: raw["defeat_pause"] = "mission.drill.duration_min",
			".defeat_pause"],
	}
	for label: String in broken:
		before_each()
		var breaks: Callable = broken[label][0]
		breaks.call(_documents[PATH])
		var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
		assert_false(loaded.is_ok(), label)
		assert_string_contains("\n".join(loaded.errors), PATH + broken[label][1], label)
