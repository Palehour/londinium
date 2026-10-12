extends GutTest


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SplashTimings.PATH))


func test_real_file_is_valid_and_loads_every_duration() -> void:
	var timings: SplashTimings = SplashTimings.new()
	timings.load_data()
	assert_true(timings.errors.is_empty(), str(timings.errors))
	assert_gt(timings.fade_seconds, 0.0)
	assert_gt(timings.fallback_seconds, 0.0)
	assert_gt(timings.watchdog_seconds, 0.0)


func test_invalid_durations_are_rejected() -> void:
	var timings: SplashTimings = SplashTimings.new()
	for key: String in SplashTimings.KEYS:
		for value: Variant in [NAN, INF, -INF, -1, 0, 0.0, "1", null, true, [1]]:
			var invalid: Dictionary = _raw()
			invalid[key] = value
			timings.validate(invalid)
			assert_eq(timings.errors.size(), 1, "%s: %s" % [key, value])


func test_missing_durations_are_rejected() -> void:
	var timings: SplashTimings = SplashTimings.new()
	for key: String in SplashTimings.KEYS:
		var missing: Dictionary = _raw()
		missing.erase(key)
		timings.validate(missing)
		assert_eq(timings.errors.size(), 1, key)
	timings.validate({})
	assert_eq(timings.errors.size(), SplashTimings.KEYS.size())


func test_non_object_documents_are_rejected() -> void:
	var timings: SplashTimings = SplashTimings.new()
	for value: Variant in [[], "text", 3, null]:
		timings.validate(value)
		assert_eq(timings.errors.size(), 1, str(value))


func test_a_rejected_document_does_not_overwrite_valid_values() -> void:
	var timings: SplashTimings = SplashTimings.new()
	timings.validate(_raw())
	var fade: float = timings.fade_seconds
	var invalid: Dictionary = _raw()
	invalid["fade_seconds"] = 7.0
	invalid["watchdog_seconds"] = -1
	timings.validate(invalid)
	assert_eq(timings.fade_seconds, fade)
