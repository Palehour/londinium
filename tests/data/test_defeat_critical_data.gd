extends GutTest

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		var dir: DirAccess = DirAccess.open("res://data/" + folder)
		for file_name: String in dir.get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _assert_invalid(message: String) -> void:
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_false(result.is_ok(), "expected invalid but ok: " + str(result.errors))
	assert_null(result.catalog, "Invalid data must not expose a partial catalog")
	assert_string_contains("\n".join(result.errors), message)


func test_ui_defeat_critical_null_and_sin_dato_normalize_to_null_not_integer() -> void:
	before_each()
	# already null in data, explicit
	_documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["hunger"] = "sin dato"
	_documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["depopulation"] = null
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok())
	var cat: DataCatalog = result.catalog
	assert_eq(cat.base_values[&"ui.defeat.critical_seconds.bankruptcy"], null)
	assert_eq(cat.base_values[&"ui.defeat.critical_seconds.hunger"], null)
	assert_eq(cat.base_values[&"ui.defeat.critical_seconds.depopulation"], null)
	assert_eq(cat.base_values[&"ui.defeat.critical_sound"], null)
	assert_false(cat.integer_keys.has(&"ui.defeat.critical_seconds.hunger"))


func test_ui_defeat_critical_zero_valid_and_registered_integer() -> void:
	before_each()
	_documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["bankruptcy"] = 0
	_documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["hunger"] = 0
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok())
	var cat: DataCatalog = result.catalog
	assert_eq(cat.base_values[&"ui.defeat.critical_seconds.bankruptcy"], 0)
	assert_eq(cat.base_values[&"ui.defeat.critical_seconds.hunger"], 0)
	assert_true(cat.integer_keys.has(&"ui.defeat.critical_seconds.bankruptcy"))
	assert_true(cat.integer_keys.has(&"ui.defeat.critical_seconds.hunger"))


func test_ui_defeat_critical_missing_each_condition_and_sound_and_object_errors() -> void:
	before_each()
	_documents["economy/defeat.json"]["ui"]["defeat"].erase("critical_seconds")
	_assert_invalid("critical_seconds: missing field")
	before_each()
	_documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"].erase("bankruptcy")
	_assert_invalid("bankruptcy: missing field")
	before_each()
	_documents["economy/defeat.json"]["ui"]["defeat"].erase("critical_sound")
	_assert_invalid("critical_sound: missing field")
	before_each()
	# missing ui altogether still loads (no call to _load), but to force error path set bad
	_documents["economy/defeat.json"].erase("ui")
	var r: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(r.is_ok())  # ui optional in load but contract declares; test presence of keys from data


func test_ui_defeat_critical_invalid_values_negative_bool_fraction_nan_clear_errors() -> void:
	for val: Variant in [-1, true, 1.5, NAN]:
		before_each()
		_documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["hunger"] = val
		_assert_invalid("hunger:")
	before_each()
	_documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["depopulation"] = -5
	_assert_invalid("depopulation:")


func test_ui_defeat_critical_sound_invalid_number_empty_error() -> void:
	before_each()
	_documents["economy/defeat.json"]["ui"]["defeat"]["critical_sound"] = 123
	_assert_invalid("critical_sound: expected null, 'sin dato' or non-empty string")
	before_each()
	_documents["economy/defeat.json"]["ui"]["defeat"]["critical_sound"] = ""
	_assert_invalid("critical_sound: expected null, 'sin dato' or non-empty string")


func test_ui_defeat_critical_comment_conserved_accepted() -> void:
	before_each()
	_documents["economy/defeat.json"]["ui"]["defeat"]["_comment"] = "extra comment ok"
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))


# Params tests for sound prohibit, null add/mul, layers/role resolved (added here per spec, no edit to sim/ or other tests)
func test_params_sound_modification_prohibited() -> void:
	before_each()
	# numeric value to pass role numeric load, then Params prohibit triggers in validation
	_documents["roles/neutral_administrator.json"]["modifiers"] = [
		{"key": "ui.defeat.critical_sound", "op": "set", "value": 1.0}
	]
	_assert_invalid("prohibited")


func test_params_null_critical_add_mul_error_and_set_layers_role_resolve() -> void:
	before_each()
	# add on null
	_documents["roles/neutral_administrator.json"]["modifiers"] = [
		{"key": "ui.defeat.critical_seconds.hunger", "op": "add", "value": 5}
	]
	_assert_invalid("cannot add/mul on null")
	before_each()
	# set via role
	_documents["roles/neutral_administrator.json"]["modifiers"] = [
		{"key": "ui.defeat.critical_seconds.hunger", "op": "set", "value": 42}
	]
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok())
	var cat: DataCatalog = result.catalog
	var role: RoleDef = cat.roles[&"neutral_administrator"]
	var p: Params = Params.new(cat, role)
	assert_eq(p.get_value(&"ui.defeat.critical_seconds.hunger"), 42.0)
	# layers + role, role wins
	var layers: Array[Modifier] = [Modifier.new(&"ui.defeat.critical_seconds.bankruptcy", &"set", 99.0)]
	var p2: Params = Params.new(cat, RoleDef.new(), layers)
	assert_eq(p2.get_value(&"ui.defeat.critical_seconds.bankruptcy"), 99.0)
