extends GutTest

# Issue #87, task 1 (D-118): each service building of economy/buildings.json (tag `service`) has its numbers in
# services/<id>.json: the attribute it covers, its radius along the streets (the service_radius_m of D-086), the top
# and the recovery of its availability, and what it costs to build and keep. Every value has a range.

const FIRE: String = "services/fire_station.json"

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


func test_one_service_building_for_each_attribute() -> void:
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var attributes: Array[StringName] = []
	for building: BuildingDef in loaded.catalog.buildings.values():
		if ServiceSystem.SERVICE_TAG in building.tags:
			attributes.append(building.service_attribute)
	attributes.sort()
	var expected: Array[StringName] = ServiceSystem.ATTRIBUTES.duplicate()
	expected.sort()
	assert_eq(attributes, expected)


# The health post of D-106 is the health service: one building, as that decision asks.
func test_the_health_post_is_the_health_service() -> void:
	var building: BuildingDef = _load().catalog.buildings[&"health_post"]
	assert_eq(building.service_attribute, ServiceSystem.HEALTH)
	assert_has(building.tags, CrisisSystem.POST_TAG)


func test_the_service_file_prices_the_building() -> void:
	var catalog: DataCatalog = _load().catalog
	var params: Params = Params.new(catalog, catalog.roles[&"neutral_administrator"])
	var raw: Dictionary = _documents[FIRE]
	assert_eq(int(params.get_value(&"building.fire_station.cost")), int(raw["cost_build_p"]))
	assert_eq(int(params.get_value(&"building.fire_station.upkeep_per_minute")), int(raw["upkeep_p_per_min"]))
	assert_eq(int(params.get_value(&"building.fire_station.service_radius_m")), int(raw["service_radius_m"]))
	assert_eq(float(params.get_value(&"service.fire_station.availability_max")), float(raw["availability_max"]))
	assert_eq(float(params.get_value(&"service.fire_station.recovery_per_min")), float(raw["recovery_per_min"]))


func test_a_service_building_without_its_file_is_rejected() -> void:
	_documents.erase(FIRE)
	_assert_invalid("economy/buildings.json.fire_station: expected services/fire_station.json")


func test_a_file_for_a_building_that_is_not_a_service_is_rejected() -> void:
	_documents["services/bakery.json"] = _documents[FIRE].duplicate(true)
	_assert_invalid("services/bakery.json: expected a building of economy/buildings.json tagged service")


func test_an_unknown_attribute_is_rejected() -> void:
	_documents[FIRE]["attribute"] = "fire"
	_assert_invalid("%s.attribute: expected safety, health or order" % FIRE)


func test_an_unknown_field_is_rejected() -> void:
	_documents[FIRE]["radius_m"] = 300
	_assert_invalid("%s.radius_m: unknown field" % FIRE)


func test_a_missing_field_is_rejected() -> void:
	_documents[FIRE].erase("recovery_per_min")
	_assert_invalid("%s.recovery_per_min: missing field" % FIRE)


func test_an_availability_top_of_0_or_over_100_is_rejected() -> void:
	_documents[FIRE]["availability_max"] = 0
	_assert_invalid("%s.availability_max: invalid percent value 0" % FIRE)
	_documents[FIRE]["availability_max"] = 101
	_assert_invalid("%s.availability_max: invalid percent value 101" % FIRE)


func test_a_recovery_of_0_or_over_the_top_is_rejected() -> void:
	_documents[FIRE]["recovery_per_min"] = 0
	_assert_invalid("%s.recovery_per_min: invalid positive value 0" % FIRE)
	_documents[FIRE]["recovery_per_min"] = 101
	_assert_invalid("%s.recovery_per_min: invalid positive value 101" % FIRE)


func test_the_radius_keeps_the_range_of_d086() -> void:
	_documents[FIRE]["service_radius_m"] = 1600
	_assert_invalid("%s.service_radius_m: invalid integer value 1600" % FIRE)


func test_a_price_out_of_its_range_is_rejected() -> void:
	_documents[FIRE]["cost_build_p"] = 5000
	_assert_invalid("%s.cost_build_p: invalid money value 5000" % FIRE)
	_documents[FIRE]["cost_build_p"] = 400
	_documents[FIRE]["upkeep_p_per_min"] = 50
	_assert_invalid("%s.upkeep_p_per_min: invalid money value 50" % FIRE)
