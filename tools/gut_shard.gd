extends GutHookScript

# GUT pre-run hook that keeps one CI shard of the collected tests (#287, D-144). GUT can only filter by script or by
# one test-name substring, so the slow suite is split here instead. Two environment variables drive it:
#   GUT_SHARD_TESTS  comma-separated test names (func names, exact match)
#   GUT_SHARD_MODE   "only" keeps just those tests; "except" keeps every other test
# With the same list, an "only" shard plus an "except" shard run each test exactly once, and a test nobody listed
# (a new one) lands in the "except" shard. Scripts left with no tests are dropped, so their before_all does not run.
# A listed name that matches no test aborts the run: the shard then writes no report and the CI gate fails.

const MODE_ONLY: String = "only"
const MODE_EXCEPT: String = "except"


func run() -> void:
	var mode: String = OS.get_environment("GUT_SHARD_MODE")
	if mode.is_empty():
		return
	if mode != MODE_ONLY and mode != MODE_EXCEPT:
		_fail("GUT_SHARD_MODE must be '%s' or '%s', got '%s'" % [MODE_ONLY, MODE_EXCEPT, mode])
		return
	var names: PackedStringArray = _listed_names()
	var unmatched: Dictionary[String, bool] = {}
	for test_name: String in names:
		unmatched[test_name] = true
	var collector: Object = gut.get_test_collector()
	var kept_scripts: Array = []
	for collected: Object in collector.scripts:
		var kept_tests: Array = []
		for test: Object in collected.tests:
			var listed: bool = names.has(test.name)
			unmatched.erase(test.name)
			if listed == (mode == MODE_ONLY):
				kept_tests.append(test)
		collected.tests = kept_tests
		if not kept_tests.is_empty():
			kept_scripts.append(collected)
	collector.scripts = kept_scripts
	if not unmatched.is_empty():
		_fail("GUT_SHARD_TESTS names no collected test: %s" % ", ".join(unmatched.keys()))


func _listed_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for raw: String in OS.get_environment("GUT_SHARD_TESTS").split(",", false):
		names.append(raw.strip_edges())
	return names


func _fail(message: String) -> void:
	gut.logger.error(message)
	abort()
