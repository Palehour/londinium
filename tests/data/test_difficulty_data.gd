extends GutTest

# Difficulty presets and knobs in data/difficulty/ (issue #70, D-065): what loads and what is rejected.

const PRESETS: String = "difficulty/presets.json"
const KNOBS: String = "difficulty/knobs.json"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "difficulty"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _assert_invalid(message: String) -> void:
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_false(result.is_ok(), message)
	assert_null(result.catalog, "Invalid data must not expose a partial catalog")
	assert_string_contains("\n".join(result.errors), message)


func test_real_data_has_the_three_presets_and_every_knob() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), str(result.errors))
	assert_eq(result.catalog.difficulties.keys(), [&"easy", &"normal", &"hard"])
	assert_true(result.catalog.difficulties[&"normal"].modifiers.is_empty(), "Normal is data/ as it is")
	# events_enabled: the switch of the historic events (issue #202).
	assert_eq(result.catalog.knobs.keys(), [&"defeats_enabled", &"events_enabled", &"reaction_seconds", &"grace_seconds",
		&"starting_money", &"price_volatility", &"refund_ratio"])
	assert_eq(result.catalog.knobs[&"events_enabled"].keys, [&"events.enabled"])
	assert_eq(result.catalog.knobs[&"reaction_seconds"].keys, [&"defeat.bankruptcy.duration_seconds",
		&"defeat.hunger.duration_seconds", &"defeat.depopulation.duration_seconds"])
	assert_true(result.catalog.base_values[&"defeat.enabled"])


func test_hard_money_factor_is_exactly_16_21() -> void:
	# Bailey's review of #129: 0.762 gave 800.1 and only reached 800 by rounding; 16/21 lands on 800 for 1050 d.
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), str(result.errors))
	var money: Array = result.catalog.difficulties[&"hard"].modifiers.filter(
		func(modifier: Modifier) -> bool: return modifier.key == &"startup.money")
	assert_eq(money.size(), 1)
	assert_eq(money[0].value, 16.0 / 21.0)


func test_every_preset_label_has_a_translation_key() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	for preset_id: StringName in result.catalog.difficulties:
		assert_true(Strings.DIFFICULTY_LABELS.has(preset_id), str(preset_id))


func test_without_difficulty_files_the_base_data_still_loads() -> void:
	_documents.erase(PRESETS)
	_documents.erase(KNOBS)
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	assert_true(result.catalog.difficulties.is_empty())


func test_preset_with_set_op_is_rejected() -> void:
	_documents[PRESETS]["easy"]["modifiers"][0]["op"] = "set"
	_assert_invalid("difficulty/presets.json.easy.modifiers[0]: expected key string, op add|mul")


func test_preset_with_unknown_or_switch_key_is_rejected() -> void:
	_documents[PRESETS]["easy"]["modifiers"][0]["key"] = "startup.gold"
	_assert_invalid("unknown or non-numeric key 'startup.gold'")
	before_each()
	_documents[PRESETS]["easy"]["modifiers"][0]["key"] = "defeat.enabled"
	_assert_invalid("unknown or non-numeric key 'defeat.enabled'")


func test_preset_result_outside_parameter_range_is_rejected() -> void:
	# Easy already gives 0.5 × 1.5; × 2 more is 1.5, a refund above the whole cost.
	_documents[PRESETS]["easy"]["modifiers"].append({"key": "demolish.refund_ratio", "op": "mul", "value": 2})
	_assert_invalid("difficulty/presets.json.easy: difficulty 'easy': Params: invalid range for 'demolish.refund_ratio'")


func test_preset_events_are_reserved_and_must_stay_empty() -> void:
	_documents[PRESETS]["hard"]["events"] = ["cholera_1866"]
	_assert_invalid("events must be an empty array (reserved for #63)")


func test_knob_range_outside_its_keys_range_is_rejected() -> void:
	_documents[KNOBS]["refund_ratio"]["max"] = 1.5
	_assert_invalid("difficulty/knobs.json.refund_ratio: min and max must be valid values of 'demolish.refund_ratio'")


func test_knob_with_bad_kind_step_or_target_is_rejected() -> void:
	_documents[KNOBS]["grace_seconds"]["kind"] = "slider"
	_assert_invalid("difficulty/knobs.json.grace_seconds: kind must be one of")
	before_each()
	_documents[KNOBS]["grace_seconds"]["step"] = 0
	_assert_invalid("difficulty/knobs.json.grace_seconds: step must be positive and min <= max")
	before_each()
	_documents[KNOBS]["defeats_enabled"]["keys"] = ["startup.money"]
	_assert_invalid("difficulty/knobs.json.defeats_enabled.keys: 'startup.money' is not a switch")
	before_each()
	_documents[KNOBS]["price_volatility"]["keys"] = ["bread"]
	_assert_invalid("'bread' is not a traded grain")
