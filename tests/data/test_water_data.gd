extends GutTest

# Issue #202, task 2a (D-090): a water building names the section of its radius (`coverage`) and, unless it drinks from
# the district's source, the section of its own source (`water_source`, with its `source_risk`). A building
# `priced_as` another reads that one's cost, upkeep, wage and jobs instead of copying them.

const BUILDINGS: String = "economy/buildings.json"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian"]:
		for name: String in DirAccess.open("res://data/" + folder).get_files():
			if name.ends_with(".json"):
				var path: String = folder.path_join(name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _assert_invalid(message: String) -> void:
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_false(loaded.is_ok())
	assert_has(loaded.errors, message)


func test_the_real_data_loads() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	var lea: BuildingDef = loaded.catalog.buildings[&"lea_bridge_fountain"]
	assert_eq(lea.coverage, &"fountain")
	assert_eq(lea.water_source, &"lea_bridge")
	assert_eq(loaded.catalog.buildings[&"public_fountain"].water_source, &"")


func test_a_water_building_needs_its_coverage() -> void:
	_documents[BUILDINGS]["well"].erase("coverage")
	_assert_invalid("%s.well.coverage: missing field" % BUILDINGS)


func test_a_coverage_without_a_radius_is_rejected() -> void:
	_documents[BUILDINGS]["well"]["coverage"] = "lea_bridge"
	_assert_invalid("%s.well.coverage: expected a section with radius_m" % BUILDINGS)


func test_a_water_source_without_a_risk_is_rejected() -> void:
	_documents[BUILDINGS]["well"]["water_source"] = "fountain"
	_assert_invalid("%s.well.water_source: expected a section with source_risk" % BUILDINGS)


func test_only_a_water_building_has_a_coverage() -> void:
	_documents[BUILDINGS]["mill"]["coverage"] = "fountain"
	_assert_invalid("%s.mill.coverage: unknown field" % BUILDINGS)


func test_priced_as_an_unknown_building_is_rejected() -> void:
	_documents[BUILDINGS]["lea_bridge_fountain"]["priced_as"] = "aqueduct"
	_assert_invalid("%s.lea_bridge_fountain.priced_as: unknown building aqueduct" % BUILDINGS)


func test_the_well_ranges_of_the_issue() -> void:
	for case: Array in [["well", "radius_m", 24], ["well", "radius_m", 101], ["well", "source_risk", 1.1],
			["lea_bridge", "max_fountains", 0], ["lea_bridge", "max_fountains", 7]]:
		before_each()
		_documents["economy/%s.json" % case[0]][case[1]] = case[2]
		var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
		assert_false(loaded.is_ok(), str(case))
	for case: Array in [["cost", 49], ["cost", 501], ["upkeep_per_minute", 6]]:
		before_each()
		_documents[BUILDINGS]["well"][case[0]] = case[1]
		var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
		assert_false(loaded.is_ok(), str(case))
