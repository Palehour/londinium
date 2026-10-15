extends GutTest

# Mods (issue #70, D-049, D-065): folders under the mods root that overlay data/ before validation.
# Each test writes its mods to a scratch folder in user:// and removes it afterwards.

const ROOT: String = "user://test_mods"

var _base: DataCatalog


func before_each() -> void:
	_remove(ROOT)
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_base = loaded.catalog


func after_each() -> void:
	_remove(ROOT)


func _write(path: String, content: Variant) -> void:
	var full: String = ROOT.path_join(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var file: FileAccess = FileAccess.open(full, FileAccess.WRITE)
	file.store_string(content if content is String else JSON.stringify(content))
	file.close()


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(folder))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _load() -> DataLoadResult:
	return DataLoader.new().load_all("res://data", DataLoader.DEFAULT_ERA, ROOT)


func test_no_mods_equals_base() -> void:
	for loaded: DataLoadResult in [_load(), DataLoader.new().load_all("res://data", DataLoader.DEFAULT_ERA, "")]:
		assert_true(loaded.is_ok(), str(loaded.errors))
		assert_eq(loaded.catalog.base_values, _base.base_values)
		assert_true(loaded.mods.is_empty())
		assert_true(loaded.mod_conflicts.is_empty())


func test_mod_overrides_value_and_keeps_the_rest_of_the_file() -> void:
	_write("rich/data/economy/startup.json", {"money": 2000})
	_write("rich/data/economy/market.json", {"wheat": {"reversion": 0.4}})
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_eq(loaded.catalog.base_values[&"startup.money"], 2000)
	assert_eq(loaded.catalog.base_values[&"market.wheat.reversion"], 0.4)
	assert_eq(loaded.catalog.base_values[&"startup.population"], _base.base_values[&"startup.population"])
	assert_eq(loaded.catalog.base_values[&"market.wheat.max_price"], _base.base_values[&"market.wheat.max_price"])
	assert_eq(loaded.mods, [&"rich"] as Array[StringName])


func test_mod_reaches_buildings_and_era_files() -> void:
	_write("cheap/data/economy/buildings.json", {"mill": {"cost": 90}})
	_write("cheap/data/eras/victorian/needs.json", {"housing_bonus_per_category": 3})
	_write("cheap/data/eras/edwardian/needs.json", {"not": "loaded"})
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_eq(loaded.catalog.base_values[&"building.mill.cost"], 90)
	assert_eq(loaded.catalog.base_values[&"building.mill.jobs"], _base.base_values[&"building.mill.jobs"])
	assert_eq(loaded.catalog.buildings[&"mill"].tags, _base.buildings[&"mill"].tags)


func test_alphabetical_without_load_order() -> void:
	_write("b_poor/data/economy/startup.json", {"money": 600})
	_write("a_rich/data/economy/startup.json", {"money": 2000})
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_eq(loaded.mods, [&"a_rich", &"b_poor"] as Array[StringName])
	assert_eq(loaded.catalog.base_values[&"startup.money"], 600)


func test_load_order_last_wins_and_reports_conflict() -> void:
	_write("b_poor/data/economy/startup.json", {"money": 600, "population": 10})
	_write("a_rich/data/economy/startup.json", {"money": 2000})
	_write("load_order.json", ["b_poor", "a_rich"])
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_eq(loaded.mods, [&"b_poor", &"a_rich"] as Array[StringName])
	assert_eq(loaded.catalog.base_values[&"startup.money"], 2000)
	assert_eq(loaded.catalog.base_values[&"startup.population"], 10)
	assert_eq(loaded.mod_conflicts, [{"key": "economy/startup.json.money", "mods": ["b_poor", "a_rich"],
		"winner": "a_rich"}])


# D-065 only orders mods: a folder the list leaves out still loads, after the listed ones, alphabetically.
func test_mods_left_out_of_load_order_load_last_alphabetically() -> void:
	_write("z_listed/data/economy/startup.json", {"money": 600})
	_write("c_unlisted/data/economy/startup.json", {"money": 999})
	_write("b_unlisted/data/economy/startup.json", {"money": 2000})
	_write("load_order.json", ["z_listed"])
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_eq(loaded.mods, [&"z_listed", &"b_unlisted", &"c_unlisted"] as Array[StringName])
	assert_eq(loaded.catalog.base_values[&"startup.money"], 999)


func test_saved_load_order_is_the_order_of_the_next_load() -> void:
	_write("a/data/economy/startup.json", {"money": 2000})
	_write("b/data/economy/startup.json", {"money": 600})
	assert_eq(ModLayer.save_load_order(ROOT, [&"b", &"a"] as Array[StringName]), OK)
	var loaded: DataLoadResult = _load()
	assert_eq(loaded.mods, [&"b", &"a"] as Array[StringName])
	assert_eq(loaded.catalog.base_values[&"startup.money"], 2000)


func test_oversized_or_too_deep_mod_files_are_rejected() -> void:
	_write("huge/data/economy/startup.json", "{\"money\": 2000}" + " ".repeat(ModLayer.MAX_FILE_BYTES))
	var nested: Dictionary = {"wheat": {}}
	var inner: Dictionary = nested["wheat"]
	for level: int in range(ModLayer.MAX_DEPTH):
		inner["deeper"] = {}
		inner = inner["deeper"]
	_write("deep/data/economy/market.json", nested)
	var errors: Array[String] = _load().errors
	assert_has(errors, "mod 'huge': economy/startup.json: file larger than %d bytes" % ModLayer.MAX_FILE_BYTES)
	assert_has(errors, "mod 'deep': economy/market.json: nested deeper than %d levels" % ModLayer.MAX_DEPTH)


func test_a_file_at_the_size_limit_still_loads() -> void:
	_write("roomy/data/economy/startup.json", "{\"money\": 2000}" + " ".repeat(ModLayer.MAX_FILE_BYTES - 15))
	var loaded: DataLoadResult = _load()
	assert_true(loaded.is_ok(), str(loaded.errors))
	assert_eq(loaded.catalog.base_values[&"startup.money"], 2000)


func test_mod_value_out_of_range_is_rejected_naming_the_mod() -> void:
	_write("broken/data/economy/startup.json", {"money": -5})
	var loaded: DataLoadResult = _load()
	assert_false(loaded.is_ok())
	assert_eq(loaded.errors, ["mod 'broken': economy/startup.json.money: invalid money value -5.0"])


func test_mod_breaking_a_cross_rule_is_rejected_naming_the_mod() -> void:
	_write("fragile/data/economy/defeat.json", {"depopulation": {"defeat_fraction": 0.99}})
	var loaded: DataLoadResult = _load()
	assert_false(loaded.is_ok())
	assert_string_contains("\n".join(loaded.errors), "mod 'fragile': economy/defeat.json: defeat.depopulation")


func test_unknown_field_or_wrong_type_is_rejected() -> void:
	_write("typo/data/economy/demolish.json", {"refund_ratoi": 0.5})
	_write("typo/data/economy/startup.json", {"wheat_purchases_enabled": 1})
	var loaded: DataLoadResult = _load()
	assert_false(loaded.is_ok())
	assert_has(loaded.errors, "mod 'typo': economy/demolish.json.refund_ratoi: unknown field")
	assert_has(loaded.errors, "mod 'typo': economy/startup.json.wheat_purchases_enabled: expected a boolean")


func test_unknown_mod_path_is_rejected() -> void:
	_write("lost/data/economy/weather.json", {"rain": 1})
	_write("lost/data/ui/map.json", {})
	var loaded: DataLoadResult = _load()
	assert_false(loaded.is_ok())
	assert_eq(loaded.errors, ["mod 'lost': economy/weather.json: no such file in data/",
		"mod 'lost': ui/map.json: no such file in data/"])


func test_bad_mod_files_are_rejected_with_a_clear_error() -> void:
	_write("empty/readme.txt", "no data folder")
	_write("listy/data/economy/startup.json", [1, 2])
	_write("garbled/data/economy/startup.json", "{\"money\": ")
	var errors: String = "\n".join(_load().errors)
	assert_string_contains(errors, "mod 'empty': missing data/ folder")
	assert_string_contains(errors, "mod 'listy': economy/startup.json: expected an object")
	assert_string_contains(errors, "mod 'garbled': economy/startup.json:0: Expected value")


func test_bad_load_order_is_rejected() -> void:
	_write("real/data/economy/startup.json", {"money": 2000})
	_write("load_order.json", ["real", "ghost", "real"])
	assert_eq(_load().errors, ["mods/load_order.json: unknown mod 'ghost'",
		"mods/load_order.json: mod 'real' is listed twice"])
	_write("load_order.json", {"real": 1})
	assert_eq(_load().errors, ["mods/load_order.json: expected a list of mod names"])


func test_same_mods_load_the_same_catalog() -> void:
	_write("b/data/economy/market.json", {"barley": {"reversion": 0.3}})
	_write("a/data/economy/market.json", {"barley": {"reversion": 0.2}, "wheat": {"max_step": 2}})
	var first: DataLoadResult = _load()
	var second: DataLoadResult = _load()
	assert_true(first.is_ok(), str(first.errors))
	assert_eq(first.catalog.base_values, second.catalog.base_values)
	assert_eq(first.catalog.base_values[&"market.barley.reversion"], 0.3)
