extends GutTest


func test_preset_is_relative_and_role_is_last() -> void:
	var normal: DataLoadResult = DataLoader.new().load_all()
	var easy: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {"preset": "easy", "mods": []})
	assert_true(easy.is_ok(), str(easy.errors))
	if not easy.is_ok():
		return
	assert_eq(easy.catalog.base_values[&"startup.money"], 1470)
	assert_eq(easy.catalog.base_values[&"defeat.hunger.duration_seconds"], 300)
	assert_eq(normal.catalog.base_values[&"startup.money"], 1050)
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"startup.money", &"mul", 2))
	assert_eq(Params.new(easy.catalog, role).get_value(&"startup.money"), 2940)


func test_knobs_override_preset_and_reaction_changes_all_conditions() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {
		"preset": "easy", "mods": [], "knobs": {"reaction_seconds": 120, "startup_money": 800}})
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	assert_eq(loaded.catalog.base_values[&"startup.money"], 800)
	for cause: String in ["bankruptcy", "hunger", "depopulation"]:
		assert_eq(loaded.catalog.base_values[StringName("defeat.%s.duration_seconds" % cause)], 120)


func test_invalid_knob_is_rejected() -> void:
	for knobs: Dictionary in [{"reaction_seconds": 61}, {"startup_money": 400},
			{"volatility": 1.6}, {"defeat_enabled": 1}, {"unknown": 10}]:
		var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {"mods": [], "knobs": knobs})
		assert_false(loaded.is_ok(), str(knobs))
		assert_false(loaded.errors.is_empty())


func test_disabled_defeat_preserves_hunger_calculation() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {
		"mods": [], "knobs": {"defeat_enabled": false, "grace_seconds": 0}})
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	var params: Params = Params.new(loaded.catalog, RoleDef.new())
	var state: EconomyState = EconomyState.new()
	state.money = -100
	state.population = 0
	state.bread_coverage = 0.0
	var system: DefeatSystem = DefeatSystem.new()
	for tick: int in range(900):
		system.update_hunger_coverage(state, params)
		system.tick(state, params, false)
	assert_true(state.defeat_causes.is_empty())
	assert_almost_eq(state.hunger_smoothed_coverage, 0.0, 0.001)


const MOD_ROOT: String = "user://issue70_mod_tests"


func _mod(name: String, money: int) -> void:
	var path: String = MOD_ROOT.path_join(name).path_join("data/economy")
	DirAccess.make_dir_recursive_absolute(path)
	var file: FileAccess = FileAccess.open(path.path_join("startup.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"money": money}))


func _order(names: Array) -> void:
	var file: FileAccess = FileAccess.open(MOD_ROOT.path_join("load_order.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(names))


func test_mod_order_conflicts_and_precedence() -> void:
	_mod("alpha", 1000)
	_mod("beta", 2000)
	_order(["alpha", "beta"])
	var config: Dictionary = {"mods_root": MOD_ROOT, "preset": "easy", "knobs": {"startup_money": 900}}
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", config)
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	assert_eq(loaded.catalog.base_values[&"startup.money"], 900)
	assert_eq(loaded.conflicts.size(), 1)
	assert_eq(loaded.conflicts[0]["winner"], "beta")
	config.erase("knobs")
	loaded = DataLoader.new().load_all("res://data", "victorian", config)
	assert_eq(loaded.catalog.base_values[&"startup.money"], 2800)
	_order(["beta", "alpha"])
	loaded = DataLoader.new().load_all("res://data", "victorian", config)
	assert_eq(loaded.catalog.base_values[&"startup.money"], 1400)
	DirAccess.remove_absolute(MOD_ROOT.path_join("load_order.json"))
	assert_eq(DataLayers.new().mod_order(MOD_ROOT), ["alpha", "beta"])


func test_invalid_mod_cannot_be_hidden_by_later_layer() -> void:
	_mod("alpha", -10)
	_mod("beta", 2000)
	_order(["alpha", "beta"])
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {"mods_root": MOD_ROOT})
	assert_false(loaded.is_ok())
	assert_null(loaded.catalog)
	assert_string_contains("; ".join(loaded.errors), "mod alpha: economy/startup.json.money")
	_mod("alpha", 1000)


func test_invalid_load_order_and_path_are_rejected() -> void:
	_mod("alpha", 1000)
	_order(["alpha", "alpha"])
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {"mods_root": MOD_ROOT})
	assert_false(loaded.is_ok())
	loaded = DataLoader.new().load_all("res://data", "victorian", {"mods": ["../escape"]})
	assert_false(loaded.is_ok())


func test_volatility_scales_both_grains_and_hard_has_approved_values() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {"preset": "hard", "mods": []})
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	assert_eq(loaded.catalog.base_values[&"startup.money"], 800)
	assert_almost_eq(loaded.catalog.base_values[&"market.wheat.reversion"], 0.35, 0.00001)
	assert_almost_eq(loaded.catalog.base_values[&"market.barley.reversion"], 0.25, 0.00001)
	loaded = DataLoader.new().load_all("res://data", "victorian", {"mods": [], "knobs": {"volatility": 1.5}})
	for grain: String in ["wheat", "barley"]:
		assert_eq(loaded.catalog.base_values[StringName("market.%s.max_price" % grain)], 4)
		assert_eq(loaded.catalog.base_values[StringName("market.%s.max_step" % grain)], 2)


func test_invalid_preset_has_clear_error() -> void:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps", "eras/victorian"]:
		var directory: DirAccess = DirAccess.open("res://data/" + folder)
		for file: String in directory.get_files():
			if file.ends_with(".json"):
				var path: String = folder.path_join(file)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	var loaded: DataLoadResult = DataLayers.new().load_layers(documents,
		{"preset": "invalid", "mods": []}, "victorian", {"invalid": {"modifiers": [
			{"key": "market.wheat.reversion", "op": "add", "value": 2}]}})
	assert_false(loaded.is_ok())
	assert_null(loaded.catalog)
	assert_string_contains("; ".join(loaded.errors), "preset invalid: economy/market.json.wheat.reversion")


func test_layered_simulation_is_deterministic_and_restart_retains_configuration() -> void:
	var config: Dictionary = {"preset": "hard", "mods": [], "knobs": {"defeat_enabled": false}}
	var first: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", config)
	var second: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", config)
	assert_true(first.is_ok(), str(first.errors))
	if not first.is_ok():
		return
	var a: GameSession = GameSession.new(first.catalog, Params.new(first.catalog, RoleDef.new()))
	var b: GameSession = GameSession.new(second.catalog, Params.new(second.catalog, RoleDef.new()))
	var initial: Dictionary = a.get_snapshot()
	for tick: int in range(900):
		a.simulation.tick()
		b.simulation.tick()
	assert_eq(a.get_snapshot(), b.get_snapshot())
	a.restart()
	assert_eq(a.get_snapshot(), initial)


func test_money_rounds_once_after_role_even_with_fractional_preset_result() -> void:
	_mod("alpha", 1001)
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {
		"mods_root": MOD_ROOT, "mods": ["alpha"], "preset": "easy"})
	assert_true(loaded.is_ok(), str(loaded.errors))
	if not loaded.is_ok():
		return
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"startup.money", &"mul", 2))
	assert_eq(Params.new(loaded.catalog, role).get_value(&"startup.money"), 2803)


func test_all_knob_endpoints_and_intermediate_steps_validate() -> void:
	var definitions: Dictionary = DataLayers.new().read_object("res://data/difficulty/knobs.json")
	for name: String in definitions:
		var definition: Dictionary = definitions[name]
		var values: Array = [false, true] if definition.get("boolean", false) else [definition["min"], definition["max"], float(definition["min"]) + float(definition["step"])]
		for value: Variant in values:
			var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {"mods": [], "knobs": {name: value}})
			assert_true(loaded.is_ok(), "%s=%s: %s" % [name, value, loaded.errors])


func test_normal_configuration_matches_original_catalog() -> void:
	var original: DataLoadResult = DataLoader.new().load_all()
	var normal: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", {"preset": "normal", "mods": []})
	assert_true(normal.is_ok(), str(normal.errors))
	assert_eq(normal.catalog.base_values, original.catalog.base_values)
	assert_eq(normal.catalog.money_keys, original.catalog.money_keys)
	assert_eq(normal.catalog.boolean_keys, original.catalog.boolean_keys)


func test_defeat_boolean_accepts_role_switch_and_rejects_arithmetic() -> void:
	var catalog: DataCatalog = DataLoader.new().load_all().catalog
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"defeat.enabled", &"set", 0))
	assert_eq(Params.new(catalog, role).get_value(&"defeat.enabled"), false)
	role.modifiers.assign([Modifier.new(&"defeat.enabled", &"mul", 0)])
	assert_false(Params.new(catalog, role).validation_errors().is_empty())
