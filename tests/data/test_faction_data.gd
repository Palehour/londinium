extends GutTest

# Issue #84: data/eras/victorian/factions.json, with ranges checked on load and on every role or mod read.

const FACTIONS: String = "eras/victorian/factions.json"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
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


func test_the_real_data_loads_three_factions() -> void:
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_eq(loaded.catalog.factions.keys(), [&"ratepayers", &"reformers", &"vestrymen"])
	assert_eq(loaded.catalog.factions[&"reformers"].coverage,
		[ServiceSystem.HEALTH, ServiceSystem.SAFETY, ServiceSystem.ORDER] as Array[StringName])


func test_an_era_without_factions_loads_without_them() -> void:
	_documents.erase(FACTIONS)
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_true(loaded.catalog.factions.is_empty())


# D-140: a floor of 0 would let the ratepayers' ratio divide by zero.
func test_a_floor_of_r_of_zero_is_rejected() -> void:
	_documents[FACTIONS]["ratio_income_floor"] = 0
	_assert_invalid("%s.ratio_income_floor: invalid positive value 0" % FACTIONS)


func test_a_role_cannot_take_the_floor_to_zero() -> void:
	var loaded: DataLoadResult = _load()
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"factions.ratio_income_floor", &"set", 0.0))
	assert_has(Params.new(loaded.catalog, role).validation_errors(),
		"Params: invalid range for 'factions.ratio_income_floor'")


func test_legitimacy_values_above_100_are_rejected() -> void:
	_documents[FACTIONS]["legitimacy_start"] = 101
	_assert_invalid("%s.legitimacy_start: invalid percent value 101" % FACTIONS)


func test_an_unknown_engine_is_rejected() -> void:
	_documents[FACTIONS]["factions"]["vestrymen"]["engine"] = "elections"
	_assert_invalid("%s.factions.vestrymen.engine: unknown engine elections" % FACTIONS)


# The list is every service of the game, read from the data.
func test_the_reformers_average_every_service_of_the_data() -> void:
	var loaded: DataLoadResult = _load()
	var services: Array[StringName] = []
	for building: BuildingDef in loaded.catalog.buildings.values():
		if building.service_attribute != &"" and building.service_attribute not in services:
			services.append(building.service_attribute)
	var listed: Array[StringName] = loaded.catalog.factions[&"reformers"].coverage.duplicate()
	services.sort()
	listed.sort()
	assert_eq(listed, services)


func test_the_coverage_must_name_service_attributes() -> void:
	_documents[FACTIONS]["factions"]["reformers"]["coverage"] = ["schools"]
	_assert_invalid("%s.factions.reformers.coverage: expected service attributes" % FACTIONS)


func test_the_names_go_by_ascending_year() -> void:
	_documents[FACTIONS]["factions"]["reformers"]["names"].reverse()
	_assert_invalid("%s.factions.reformers.names: expected a translation key from each year, by ascending year"
		% FACTIONS)


func test_every_class_needs_an_affinity_to_every_faction() -> void:
	_documents[FACTIONS]["affinity"].erase("artisan")
	_assert_invalid("%s.affinity.artisan: missing field" % FACTIONS)
	before_each()
	_documents[FACTIONS]["affinity"]["worker"].erase("vestrymen")
	_assert_invalid("%s.affinity.worker.vestrymen: missing field" % FACTIONS)


func test_a_class_with_no_affinity_at_all_is_rejected() -> void:
	_documents[FACTIONS]["affinity"]["worker"] = {"ratepayers": 0, "reformers": 0, "vestrymen": 0}
	_assert_invalid("%s.affinity.worker: expected an affinity above 0" % FACTIONS)
