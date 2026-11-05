extends GutTest


func _copy_data_documents() -> Dictionary[String, Dictionary]:
	var docs: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		var dir: DirAccess = DirAccess.open("res://data/" + folder)
		if dir == null:
			continue
		for file_name: String in dir.get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				var content: String = FileAccess.get_file_as_string("res://data/" + path)
				var parsed: Variant = JSON.parse_string(content)
				if parsed is Dictionary:
					docs[path] = parsed
	return docs


func test_pending_ui_mobility_keys_have_has_value_and_return_sin_dato_literal() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), "load_all must succeed: " + str(result.errors))
	var catalog: DataCatalog = result.catalog
	var params: Params = Params.new(catalog, catalog.roles[&"neutral_administrator"])
	var pending_keys: Array[StringName] = [
		&"ui.mobility.labor_notice_window_seconds",
		&"ui.mobility.demotion_warning_seconds",
		&"ui.mobility.max_buildings_listed"
	]
	for key: StringName in pending_keys:
		assert_true(params.has_value(key), "has_value(%s) must be true for pending UI key" % key)
		var v: Variant = params.get_value(key)
		assert_eq(v, "sin dato", "get_value(%s) must return literal 'sin dato' string from data" % key)
		assert_typeof(v, TYPE_STRING)
	# ensure no spurious errors for these
	assert_push_error_count(0)


func test_fixtures_can_provide_non_production_numbers_for_pending_keys() -> void:
	var docs: Dictionary[String, Dictionary] = _copy_data_documents()
	docs["economy/ui.json"] = {
		"mobility": {
			"labor_notice_window_seconds": 90,
			"demotion_warning_seconds": 45,
			"max_buildings_listed": 8
		}
	}
	var result: DataLoadResult = DataLoader.new().load_documents(docs)
	assert_true(result.is_ok(), "fixture with valid ui numbers must load: " + str(result.errors))
	var catalog: DataCatalog = result.catalog
	var params: Params = Params.new(catalog, catalog.roles[&"neutral_administrator"])
	assert_eq(params.get_value(&"ui.mobility.labor_notice_window_seconds"), 90)
	assert_typeof(params.get_value(&"ui.mobility.labor_notice_window_seconds"), TYPE_INT)
	assert_eq(params.get_value(&"ui.mobility.demotion_warning_seconds"), 45)
	assert_eq(params.get_value(&"ui.mobility.max_buildings_listed"), 8)
	assert_true(params.has_value(&"ui.mobility.labor_notice_window_seconds"))


func test_ui_mobility_fixtures_must_provide_finite_semantic_integers() -> void:
	var docs: Dictionary[String, Dictionary] = _copy_data_documents()
	docs["economy/ui.json"] = {
		"mobility": {
			"labor_notice_window_seconds": 0,  # not positive
			"demotion_warning_seconds": 10.5,  # not integer
			"max_buildings_listed": -1
		}
	}
	var result: DataLoadResult = DataLoader.new().load_documents(docs)
	assert_false(result.is_ok(), "invalid fixture numbers must fail load")
	# errors should mention the bad values or keys, without turning into 'sin dato' silently
	var has_relevant_error: bool = false
	for e: String in result.errors:
		if "labor_notice" in e or "demotion" in e or "max_buildings" in e or "invalid" in e or "positive" in e:
			has_relevant_error = true
			break
	assert_true(has_relevant_error, "load error must report the ui mobility numeric problem")


func test_ui_mobility_block_requires_all_fields_when_present() -> void:
	var docs: Dictionary[String, Dictionary] = _copy_data_documents()
	docs["economy/ui.json"] = {
		"mobility": {
			"labor_notice_window_seconds": "sin dato"
			# missing the other two required fields
		}
	}
	var result: DataLoadResult = DataLoader.new().load_documents(docs)
	assert_false(result.is_ok())
	var has_missing: bool = false
	for e: String in result.errors:
		if "missing field" in e and "ui.mobility" in e:
			has_missing = true
	assert_true(has_missing)


func test_ui_mobility_rejects_malformed_or_invalid_literal() -> void:
	var docs: Dictionary[String, Dictionary] = _copy_data_documents()
	docs["economy/ui.json"] = {
		"mobility": {
			"labor_notice_window_seconds": "foo",  # invalid literal
			"demotion_warning_seconds": true,
			"max_buildings_listed": "sin dato"
		}
	}
	var result: DataLoadResult = DataLoader.new().load_documents(docs)
	assert_false(result.is_ok())
	var has_bad_literal: bool = false
	for e: String in result.errors:
		if "expected 'sin dato' or finite" in e or "foo" in e:
			has_bad_literal = true
	assert_true(has_bad_literal)


func test_validation_errors_ignores_sin_dato_keys() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok())
	var catalog: DataCatalog = result.catalog
	var params: Params = Params.new(catalog, catalog.roles[&"neutral_administrator"])
	var errs: Array[String] = params.validation_errors()
	for e: String in errs:
		assert_false("ui.mobility" in e, "validation_errors must not report error for 'sin dato' keys: " + e)


func test_ui_mobility_set_modifier_on_sin_dato_replaces_and_validates() -> void:
	var docs: Dictionary[String, Dictionary] = _copy_data_documents()
	# base sin dato
	var role: RoleDef = RoleDef.new()
	role.id = &"test_set"
	role.modifiers.append(Modifier.new(&"ui.mobility.labor_notice_window_seconds", &"set", 60))
	var result: DataLoadResult = DataLoader.new().load_documents(docs)
	assert_true(result.is_ok())
	var catalog: DataCatalog = result.catalog
	var params: Params = Params.new(catalog, role)
	var got: Variant = params.get_value(&"ui.mobility.labor_notice_window_seconds")
	assert_true(got == 60 or got == 60.0)
	assert_true(params.validation_errors().is_empty())


func test_numeric_set_then_role_modifier_keeps_existing_parameter_order() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok())
	var key: StringName = &"ui.mobility.labor_notice_window_seconds"
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(key, &"mul", 2.0))
	var layers: Array[Modifier] = [Modifier.new(key, &"set", 30.0)]
	var params: Params = Params.new(result.catalog, role, layers)
	assert_eq(float(params.get_value(key)), 60.0)
	assert_true(params.validation_errors().is_empty())


func test_ui_mobility_arithmetic_modifier_on_sin_dato_rejected() -> void:
	var docs: Dictionary[String, Dictionary] = _copy_data_documents()
	var role: RoleDef = RoleDef.new()
	role.id = &"test_arith"
	role.modifiers.append(Modifier.new(&"ui.mobility.demotion_warning_seconds", &"add", 10))
	var result: DataLoadResult = DataLoader.new().load_documents(docs)
	assert_true(result.is_ok())
	var catalog: DataCatalog = result.catalog
	var params: Params = Params.new(catalog, role)
	# validation_errors collects the reject
	var verrs: Array[String] = params.validation_errors()
	var has_reject: bool = false
	for e: String in verrs:
		if "arithmetic modifier on 'sin dato'" in e:
			has_reject = true
	assert_true(has_reject)
	# get_value also reports (fresh instance to control pushes)
	var p2: Params = Params.new(catalog, role)
	var v: Variant = p2.get_value(&"ui.mobility.demotion_warning_seconds")
	assert_null(v)
	assert_push_error("arithmetic modifier on 'sin dato' key")


func test_ui_mobility_numeric_base_accepts_modifiers() -> void:
	var docs: Dictionary[String, Dictionary] = _copy_data_documents()
	docs["economy/ui.json"] = {
		"mobility": {
			"labor_notice_window_seconds": 30,
			"demotion_warning_seconds": "sin dato",
			"max_buildings_listed": 5
		}
	}
	var role: RoleDef = RoleDef.new()
	role.id = &"test_num_base"
	role.modifiers.append(Modifier.new(&"ui.mobility.labor_notice_window_seconds", &"mul", 2))
	var result: DataLoadResult = DataLoader.new().load_documents(docs)
	assert_true(result.is_ok())
	var catalog: DataCatalog = result.catalog
	var params: Params = Params.new(catalog, role)
	assert_eq(int(params.get_value(&"ui.mobility.labor_notice_window_seconds")), 60)


func test_ui_mobility_malformed_not_dict() -> void:
	var docs: Dictionary[String, Dictionary] = _copy_data_documents()
	docs["economy/ui.json"] = { "mobility": "not a dictionary" }
	var result: DataLoadResult = DataLoader.new().load_documents(docs)
	assert_false(result.is_ok())
	var has_obj_err: bool = false
	for e: String in result.errors:
		if "expected an object" in e and "mobility" in e:
			has_obj_err = true
	assert_true(has_obj_err)
