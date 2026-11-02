extends GutTest

# Issue #71: decrees.json is optional and empty until a decree is named. A present decree is validated.

const DECREES: String = "eras/victorian/decrees.json"
const SCENARIO: String = "scenarios/victorian_demo.json"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services", "scenarios"]:
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


func test_the_shipped_catalog_is_empty_and_competencies_default_to_none() -> void:
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_true(loaded.catalog.decrees.is_empty())
	assert_eq(loaded.catalog.scenarios[&"victorian_demo"]["competencies"], [] as Array[StringName])


func test_a_negative_upkeep_is_rejected() -> void:
	_documents[DECREES]["decrees"] = {"sewer": {"for": ["reformers"], "against": ["ratepayers"],
		"upkeep_per_min": -1, "name_key": "ui.decree.sewer"}}
	_assert_invalid("%s.decrees.sewer.upkeep_per_min: invalid money value -1" % DECREES)


func test_a_faction_on_both_sides_is_rejected() -> void:
	_documents[DECREES]["decrees"] = {"sewer": {"for": ["ratepayers"], "against": ["ratepayers"],
		"upkeep_per_min": 0, "name_key": "ui.decree.sewer"}}
	_assert_invalid("%s.decrees.sewer: ratepayers is both for and against" % DECREES)


func test_an_unknown_competency_is_rejected() -> void:
	_documents[SCENARIO]["competencies"] = ["sewer"]
	_assert_invalid("%s.competencies: unknown decree sewer" % SCENARIO)
