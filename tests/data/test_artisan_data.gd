extends GutTest

# The artisan class in data/ (issue #52): its values, the ranges they are held to and the role modifiers.

var _documents: Dictionary[String, Dictionary] = {}
const CLASSES: String = "eras/victorian/classes.json"


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _load() -> DataLoadResult:
	return DataLoader.new().load_documents(_documents)


func _edit(path: Array, value: Variant) -> void:
	var target: Dictionary = _documents[CLASSES]
	for index: int in range(path.size() - 1):
		target = target[path[index]]
	target[path[path.size() - 1]] = value


func _validation_errors(changes: Array[Modifier]) -> Array[String]:
	var result: DataLoadResult = _load()
	assert_true(result.is_ok(), str(result.errors))
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(changes)
	return Params.new(result.catalog, role).validation_errors()


func test_the_artisan_values_are_the_approved_ones() -> void:
	var result: DataLoadResult = _load()
	assert_true(result.is_ok(), str(result.errors))
	var values: Dictionary[StringName, Variant] = result.catalog.base_values
	assert_eq(values[&"building.artisan_housing.capacity"], 10)
	assert_eq(values[&"building.artisan_housing.cost"], 120)
	assert_eq(values[&"building.artisan_housing.upkeep_per_minute"], 2)
	assert_eq(values[&"building.artisan_housing.jobs"], 0)
	assert_eq(values[&"class.artisan.housing_max_bonus"], 4)
	assert_eq(values[&"class.artisan.tax.base"], 20)
	assert_eq(values[&"class.artisan.need.bread.value"], 100.0)
	assert_eq(values[&"class.artisan.need.beer.value"], 100.0)
	assert_eq(values[&"class.artisan.need.bread.per_person_per_minute"], 1.0)
	assert_eq(values[&"class.artisan.need.beer.per_person_per_minute"], 0.4)
	assert_eq(values[&"class.artisan.need.bread.satisfaction_weight"], 60.0)
	assert_eq(values[&"class.artisan.need.beer.satisfaction_weight"], 40.0)
	assert_eq(values[&"class.artisan.satisfaction.tax_weight"], 50.0)
	assert_eq(values[&"class.artisan.satisfaction.overcrowding_weight"], 30.0)
	assert_eq(values[&"class.artisan.growth.immigration_threshold"], 75.0)
	assert_eq(values[&"class.artisan.growth.emigration_threshold"], 35.0)
	assert_eq(values[&"class.artisan.growth.immigration_per_minute"], 3.0)
	assert_eq(values[&"class.artisan.growth.emigration_per_minute"], 2.0)
	assert_eq(values[&"class.artisan.growth.hunger_emigration_threshold"], 0.6)
	assert_eq(values[&"class.artisan.growth.hunger_emigration_recovery"], 0.75)
	assert_eq(values[&"class.artisan.growth.hunger_emigration_multiplier"], 2.0)


func test_the_artisan_pays_more_per_head_than_the_worker_by_default() -> void:
	var values: Dictionary[StringName, Variant] = _load().catalog.base_values
	assert_gt(float(values[&"class.artisan.tax.base"]), float(values[&"population.tax.base_per_employed_worker_per_minute"]))


func test_artisan_values_out_of_range_are_rejected() -> void:
	var cases: Array[Array] = [
		[["artisan", "housing_max_bonus"], -1],
		[["artisan", "housing_max_bonus"], 21],
		[["artisan", "housing_max_bonus"], 2.5],
		[["artisan", "needs", "beer", "value"], 101],
		[["artisan", "needs", "beer", "value"], -1],
		[["artisan", "needs", "bread", "satisfaction_key"], -1],
		[["artisan", "needs", "beer", "consumption_key"], 0],
		[["artisan", "needs", "beer", "consumption_key"], -0.4],
		[["artisan", "satisfaction", "tax_weight"], -1],
		[["artisan", "satisfaction", "overcrowding_weight"], -1],
		[["artisan", "satisfaction", "smoothing_per_second"], 0],
		[["artisan", "satisfaction", "smoothing_per_second"], 1.5],
		[["artisan", "satisfaction", "snap_epsilon"], 0],
		[["artisan", "growth", "immigration_threshold"], 101],
		[["artisan", "growth", "immigration_threshold"], -1],
		[["artisan", "growth", "emigration_threshold"], 101],
		[["artisan", "growth", "immigration_per_minute"], -1],
		[["artisan", "growth", "emigration_per_minute"], -1],
		[["artisan", "growth", "hunger_emigration_threshold"], 1.1],
		[["artisan", "growth", "hunger_emigration_recovery"], 1.1],
		[["artisan", "growth", "hunger_emigration_multiplier"], 0.9],
		[["artisan", "tax", "base"], -1],
		[["artisan", "tax", "base"], 20.5],
	]
	for entry: Array in cases:
		before_each()
		_edit(entry[0], entry[1])
		assert_false(_load().is_ok(), "%s = %s" % [entry[0], entry[1]])


func test_artisan_hunger_recovery_cannot_be_below_its_threshold() -> void:
	_edit(["artisan", "growth", "hunger_emigration_recovery"], 0.5)
	assert_string_contains("\n".join(_load().errors), "hunger_emigration_recovery must be >=")


func test_the_housing_building_of_the_artisan_must_exist_and_have_the_housing_tag() -> void:
	_edit(["artisan", "housing_building"], "brewery")
	assert_string_contains("\n".join(_load().errors), "is not a housing building")
	before_each()
	_edit(["artisan", "housing_building"], "housing")
	assert_string_contains("\n".join(_load().errors), "already belongs to another class")


func test_there_must_be_exactly_one_base_class_and_it_must_take_jobs() -> void:
	_edit(["artisan", "base"], true)
	assert_string_contains("\n".join(_load().errors), "exactly one class must be the base class")
	before_each()
	_edit(["worker", "base"], false)
	assert_string_contains("\n".join(_load().errors), "exactly one class must be the base class")
	before_each()
	_edit(["worker", "takes_jobs"], false)
	assert_string_contains("\n".join(_load().errors), "the base class must take jobs")


func test_a_class_must_declare_every_field_of_its_blocks() -> void:
	_documents[CLASSES]["artisan"]["growth"].erase("immigration_per_minute")
	assert_string_contains("\n".join(_load().errors), "immigration_per_minute: missing field")
	before_each()
	_documents[CLASSES]["artisan"]["tax"]["basis"] = "everybody"
	assert_string_contains("\n".join(_load().errors), "tax.basis: expected employed or residents")
	before_each()
	_documents[CLASSES]["artisan"]["needs"]["bread"]["consumption_key"] = "population.nowhere"
	assert_string_contains("\n".join(_load().errors), "consumption_key: expected the key of a numeric parameter")


func test_artisan_role_modifiers_inside_the_ranges_are_valid() -> void:
	var errors: Array[String] = _validation_errors([
		Modifier.new(&"class.artisan.tax.base", &"mul", 1.5),
		Modifier.new(&"class.artisan.need.beer.per_person_per_minute", &"mul", 0.5),
		Modifier.new(&"class.artisan.growth.immigration_per_minute", &"add", 1),
		Modifier.new(&"class.artisan.housing_max_bonus", &"set", 6),
		Modifier.new(&"class.artisan.satisfaction.tax_weight", &"set", 0),
	])
	assert_eq(errors, [] as Array[String])


func test_artisan_role_modifiers_outside_the_ranges_are_rejected() -> void:
	var cases: Array[Modifier] = [
		Modifier.new(&"class.artisan.tax.base", &"set", -5),
		Modifier.new(&"class.artisan.need.beer.per_person_per_minute", &"mul", 0),
		Modifier.new(&"class.artisan.need.bread.value", &"set", 101),
		Modifier.new(&"class.artisan.housing_max_bonus", &"set", 25),
		Modifier.new(&"class.artisan.housing_max_bonus", &"set", 2.5),
		Modifier.new(&"class.artisan.satisfaction.tax_weight", &"set", -1),
		Modifier.new(&"class.artisan.growth.emigration_threshold", &"set", -1),
		Modifier.new(&"class.artisan.growth.immigration_threshold", &"set", 101),
		Modifier.new(&"class.artisan.growth.emigration_per_minute", &"add", -5),
		Modifier.new(&"class.artisan.growth.hunger_emigration_threshold", &"set", 2),
		Modifier.new(&"class.artisan.growth.hunger_emigration_multiplier", &"set", 0.5),
	]
	for modifier: Modifier in cases:
		var errors: Array[String] = _validation_errors([modifier])
		assert_false(errors.is_empty(), "%s %s %s" % [modifier.key, modifier.op, modifier.value])


func test_artisan_hunger_hysteresis_is_checked_on_either_read_after_modifiers() -> void:
	var lower_recovery: Array[String] = _validation_errors([
		Modifier.new(&"class.artisan.growth.hunger_emigration_recovery", &"set", 0.5)])
	assert_false(lower_recovery.is_empty())
	var higher_threshold: Array[String] = _validation_errors([
		Modifier.new(&"class.artisan.growth.hunger_emigration_threshold", &"set", 0.9)])
	assert_false(higher_threshold.is_empty())
	var both: Array[String] = _validation_errors([
		Modifier.new(&"class.artisan.growth.hunger_emigration_threshold", &"set", 0.3),
		Modifier.new(&"class.artisan.growth.hunger_emigration_recovery", &"set", 0.4)])
	assert_eq(both, [] as Array[String])


func test_a_role_may_not_target_an_artisan_key_that_does_not_exist() -> void:
	_documents["roles/neutral_administrator.json"]["modifiers"] = [
		{"key": "class.artisan.need.gin.value", "op": "set", "value": 10}]
	assert_string_contains("\n".join(_load().errors), "unknown key 'class.artisan.need.gin.value'")


# Mobility (issue #53, D-061): approved by Cristian on 2026-10-13; sustenance and demotion point at #86's thresholds.
func test_mobility_values_come_from_the_data() -> void:
	var result: DataLoadResult = _load()
	assert_true(result.is_ok(), str(result.errors))
	var values: Dictionary[StringName, Variant] = result.catalog.base_values
	var artisans: ClassDef = result.catalog.classes[&"artisan"]
	assert_eq(artisans.mobility_from, &"worker")
	assert_eq(values[artisans.promotion_min_score_keys[&"comunidad"]], 80.0)
	assert_eq(artisans.promotion_min_score_keys[&"sustento"], &"needs.sustento.threshold")
	assert_eq(values[artisans.promotion_min_score_keys[&"sustento"]], 75.0)
	assert_eq(values[&"class.artisan.mobility.promotion.source_satisfaction"], 70.0)
	assert_eq(values[&"class.artisan.mobility.promotion.per_minute"], 2.0)
	assert_eq(artisans.demotion_category, &"comunidad")
	assert_eq(artisans.demotion_below_key, &"needs.comunidad.threshold")
	assert_eq(values[artisans.demotion_below_key], 50.0)
	assert_eq(values[&"class.artisan.mobility.demotion.seconds"], 60)
	assert_eq(values[&"class.artisan.mobility.demotion.per_minute"], 2.0)
	assert_false(result.catalog.classes[&"worker"].has_mobility())


func test_mobility_values_out_of_range_are_rejected() -> void:
	var cases: Array[Array] = [
		[["artisan", "mobility", "promotion", "min_scores", "comunidad"], 101],
		[["artisan", "mobility", "promotion", "min_scores", "comunidad"], -1],
		[["artisan", "mobility", "promotion", "source_satisfaction"], 101],
		[["artisan", "mobility", "promotion", "per_minute"], -1],
		[["artisan", "mobility", "demotion", "below"], 101],
		[["artisan", "mobility", "demotion", "seconds"], 0],
		[["artisan", "mobility", "demotion", "seconds"], 1.5],
		[["artisan", "mobility", "demotion", "per_minute"], -1],
	]
	for entry: Array in cases:
		before_each()
		_edit(entry[0], entry[1])
		assert_false(_load().is_ok(), "%s = %s" % [entry[0], entry[1]])


func test_mobility_must_name_another_class_and_categories_of_its_needs() -> void:
	_edit(["artisan", "mobility", "from"], "artisan")
	assert_string_contains("\n".join(_load().errors), "mobility.from: expected another class")
	before_each()
	_edit(["artisan", "mobility", "from"], "noble")
	assert_string_contains("\n".join(_load().errors), "mobility.from: expected another class")
	before_each()
	_edit(["artisan", "mobility", "promotion", "min_scores", "estatus"], 10)
	assert_string_contains("\n".join(_load().errors), "not a category of this class's needs")
	before_each()
	_edit(["artisan", "mobility", "demotion", "category"], "salud")
	assert_string_contains("\n".join(_load().errors), "demotion.category: not a category of this class's needs")
	before_each()
	_edit(["artisan", "mobility", "speed"], 1)
	assert_string_contains("\n".join(_load().errors), "mobility.speed: unknown field")
	before_each()
	_documents[CLASSES]["artisan"]["mobility"]["demotion"].erase("seconds")
	assert_string_contains("\n".join(_load().errors), "demotion.seconds: missing field")


func test_mobility_role_modifiers_inside_the_ranges_are_valid() -> void:
	var errors: Array[String] = _validation_errors([
		Modifier.new(&"class.artisan.mobility.promotion.comunidad.min_score", &"set", 60),
		Modifier.new(&"class.artisan.mobility.promotion.per_minute", &"mul", 1.5),
		Modifier.new(&"class.artisan.mobility.demotion.seconds", &"add", 30),
	])
	assert_eq(errors, [] as Array[String])
