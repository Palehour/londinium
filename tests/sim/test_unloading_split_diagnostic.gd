extends GutTest

# Issue #106: the mill is told why it gets less wheat than it grinds when the wharf gives part of its
# unloading to the barley. Only the two conditions together raise it: wheat short of the mill's need and a
# barley share above 0. The rates come from the data (a staffed wharf unloads 10 per minute, a staffed mill
# grinds 10), so every number here follows from the split and the staffing the test sets.

var _catalog: DataCatalog
var _context: EconomyContext
var _params: Params


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_params = Params.new(_catalog, RoleDef.new())


func _jobs(id: StringName) -> int:
	return WorkersSystem.job_capacity(_params, id)


# Fully staffed wharves and mills unless the test gives a building fewer workers.
func _state(barley_percent: int, wharves: int, mills: int, wharf_workers: int = -1,
		mill_workers: int = -1) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.unloading_barley_percent = barley_percent
	for index: int in range(wharves):
		state.buildings.append({"definition_id": &"wharf", "cell": [index, 7],
			"workers": _jobs(&"wharf") if wharf_workers < 0 else wharf_workers})
	for index: int in range(mills):
		state.buildings.append({"definition_id": &"mill", "cell": [index, 5],
			"workers": _jobs(&"mill") if mill_workers < 0 else mill_workers})
	return state


func _split(state: EconomyState) -> Dictionary:
	return BreadDiagnostics.build(state, _params, _context)["unloading_split"]


func test_warns_when_the_barley_share_leaves_the_mill_short() -> void:
	var split: Dictionary = _split(_state(30, 1, 1))
	assert_true(split["active"])
	assert_almost_eq(float(split["received_per_minute"]), 7.0, 1e-9)
	assert_almost_eq(float(split["needed_per_minute"]), 10.0, 1e-9)


func test_silent_with_no_barley_share_even_if_the_wheat_is_short() -> void:
	# Two mills grind 20 and one wharf brings 10: short, but the barley is not the reason.
	var split: Dictionary = _split(_state(0, 1, 2))
	assert_lt(float(split["received_per_minute"]), float(split["needed_per_minute"]))
	assert_false(split["active"])


func test_silent_when_the_wheat_is_enough() -> void:
	var split: Dictionary = _split(_state(30, 2, 1))
	assert_almost_eq(float(split["received_per_minute"]), 14.0, 1e-9)
	assert_false(split["active"])


func test_silent_at_exactly_what_the_mill_needs() -> void:
	var split: Dictionary = _split(_state(50, 2, 1))
	assert_almost_eq(float(split["received_per_minute"]), 10.0, 1e-9)
	assert_false(split["active"])


func test_silent_without_a_staffed_mill() -> void:
	assert_false(_split(_state(30, 1, 1, -1, 0))["active"])
	assert_false(_split(_state(30, 1, 0))["active"])


func test_received_and_needed_follow_the_split_and_staffing() -> void:
	var split: Dictionary = _split(_state(15, 1, 1))
	assert_almost_eq(float(split["received_per_minute"]), 8.5, 1e-9)
	# A mill with 2 of its 3 workers grinds 6.67: the 7 a 30 % split leaves is enough, the 5 of a 50 % one is not.
	split = _split(_state(30, 1, 1, -1, 2))
	assert_almost_eq(float(split["needed_per_minute"]), 10.0 * 2.0 / 3.0, 1e-9)
	assert_false(split["active"])
	assert_true(_split(_state(50, 1, 1, -1, 2))["active"])
	split = _split(_state(30, 1, 1, 2))
	assert_almost_eq(float(split["received_per_minute"]), 3.5, 1e-9)
	assert_true(split["active"])


func test_all_barley_leaves_no_wheat_for_the_mill() -> void:
	var split: Dictionary = _split(_state(100, 1, 1))
	assert_almost_eq(float(split["received_per_minute"]), 0.0, 1e-9)
	assert_true(split["active"])


func test_the_diagnostic_does_not_change_the_state() -> void:
	var state: EconomyState = _state(30, 1, 1)
	var before: String = var_to_str(state.buildings)
	_split(state)
	assert_eq(var_to_str(state.buildings), before)
