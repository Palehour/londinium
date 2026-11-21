extends GutTest

# data/ui/narrator.json (issue #73): the knobs of D-145 (pause on what is critical), D-146 (anti-saturation) and the
# grace of a first cause (D-198), the attention cost Cristian approved in the plan (2026-10-28: high 2, normal 1,
# low 1), and the rules that map the cause log's events to notices. The narrator only announces kinds the log keeps
# today (D-147).


func after_each() -> void:
	Strings.use_default_locale()


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(NarratorConfig.PATH))


func _errors(raw: Dictionary) -> Array[String]:
	var config: NarratorConfig = NarratorConfig.new()
	config.validate(raw)
	return config.errors


func test_the_file_holds_the_values_of_d145_and_d146() -> void:
	var config: NarratorConfig = NarratorConfig.new()
	config.load_data()
	assert_eq(config.errors, [] as Array[String])
	assert_true(config.pause_on_critical, "D-145: pauses on what is critical, and data can turn it off")
	assert_eq(config.cooldown_s, {&"critical": 0, &"high": 30, &"normal": 60, &"low": 120} as Dictionary[StringName, int])
	assert_eq(config.group_window_s, 10)
	assert_eq(config.max_visible, 4)
	assert_eq(config.attention_budget_per_min, 6)
	assert_eq(config.attention_cost, {&"critical": 0, &"high": 2, &"normal": 1, &"low": 1} as Dictionary[StringName, int],
		"what is critical spends nothing")
	assert_eq(config.digest_interval_s, 60)
	assert_eq(config.toast_lifetime_s, {&"high": 12, &"normal": 8, &"low": 5} as Dictionary[StringName, int])
	assert_eq(config.threshold_hysteresis, 5)
	assert_eq(config.legitimacy_thresholds, [25, 10] as Array[int])
	assert_gte(config.min_button_px, 16, "buttons the gamepad reaches are at least 16 px")


# D-198: the grace a first cause waits before it is offered, a knob like the others: in the file, whole and 0 or more.
func test_the_file_holds_the_grace_of_a_first_cause() -> void:
	assert_true(_raw().has("first_cause_grace_s"), "the grace a first cause waits is in the file")
	var config: NarratorConfig = NarratorConfig.new()
	config.load_data()
	assert_eq(config.errors, [] as Array[String])
	assert_eq(config.first_cause_grace_s, 10, "a first cause waits ten seconds")


func test_the_rules_only_use_kinds_the_cause_log_keeps() -> void:
	var config: NarratorConfig = NarratorConfig.new()
	config.load_data()
	assert_false(config.rules.is_empty())
	for rule: Dictionary in config.rules:
		assert_has(StatsHistory.CAUSE_KINDS, rule["kind"], "D-147: no event outside the log")
	var raw: Dictionary = _raw()
	raw["rules"].append({"kind": "incident", "priority": "critical", "key": "narrator.defeat.warning"})
	assert_eq(_errors(raw).size(), 1, "a kind the log does not keep yet is refused")


func test_every_rule_key_is_translated_in_both_languages() -> void:
	var config: NarratorConfig = NarratorConfig.new()
	config.load_data()
	var keys: Array[StringName] = config.keys()
	assert_false(keys.is_empty())
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		for key: StringName in keys:
			assert_ne(Strings.text(key), String(key), "%s has a %s text" % [key, locale])


func test_bad_knobs_and_rules_are_errors() -> void:
	var cases: Dictionary[String, Callable] = {
		"missing knob": func(raw: Dictionary) -> void: raw.erase("max_visible"),
		"negative cooldown": func(raw: Dictionary) -> void: raw["cooldown_s"]["high"] = -1,
		"missing priority": func(raw: Dictionary) -> void: raw["cooldown_s"].erase("low"),
		"no slot": func(raw: Dictionary) -> void: raw["max_visible"] = 0,
		"switch not a boolean": func(raw: Dictionary) -> void: raw["pause_on_critical"] = 1,
		"unknown priority": func(raw: Dictionary) -> void: raw["rules"][0]["priority"] = "urgent",
		"rule without key": func(raw: Dictionary) -> void: raw["rules"][0].erase("key"),
		"rules not a list": func(raw: Dictionary) -> void: raw["rules"] = {},
		"missing lifetime": func(raw: Dictionary) -> void: raw["toast_lifetime_s"].erase("high"),
		"thresholds out of range": func(raw: Dictionary) -> void: raw["legitimacy_thresholds"] = [250],
		"unknown target": func(raw: Dictionary) -> void: raw["rules"][0]["target_from"] = "district",
		"missing grace": func(raw: Dictionary) -> void: raw.erase("first_cause_grace_s"),
		"negative grace": func(raw: Dictionary) -> void: raw["first_cause_grace_s"] = -1,
		"fractional grace": func(raw: Dictionary) -> void: raw["first_cause_grace_s"] = 2.5,
	}
	for name: String in cases:
		var raw: Dictionary = _raw()
		cases[name].call(raw)
		assert_false(_errors(raw).is_empty(), name)
	assert_eq(_errors(_raw()), [] as Array[String])


func test_the_first_matching_rule_wins() -> void:
	var config: NarratorConfig = NarratorConfig.new()
	config.load_data()
	assert_true(config.rule_for(&"building", &"ok")["silent"], "a building back to work says nothing")
	assert_eq(config.rule_for(&"building", &"no_workers")["key"], &"narrator.building.stopped")
	assert_eq(config.rule_for(&"defeat", &"warning")["priority"], &"critical")
	assert_true(config.rule_for(&"defeat", &"warning")["pause"])
	assert_eq(config.rule_for(&"command", &"accepted"), {}, "no rule, no notice")


# §12: no numbers in the narrator's code; every threshold, wait and size comes from data/ui/narrator.json.
func test_the_narrator_code_has_no_balance_numbers() -> void:
	var number: RegEx = RegEx.create_from_string("(?<![\\w.\"@%])\\d+(\\.\\d+)?(?![\\w\"])")
	var allowed: Array[String] = ["0", "1", "2"]
	for file: String in DirAccess.get_files_at("res://src/ui/narrator"):
		if not file.ends_with(".gd"):
			continue
		var lines: PackedStringArray = FileAccess.get_file_as_string("res://src/ui/narrator/" + file).split("\n")
		for index: int in lines.size():
			var line: String = lines[index].strip_edges()
			if line.begins_with("#") or line.begins_with("const "):
				continue
			for found: RegExMatch in number.search_all(line.get_slice(" #", 0)):
				assert_has(allowed, found.get_string(), "%s:%d has a number: %s" % [file, index + 1, line])
