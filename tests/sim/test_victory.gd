extends GutTest

var _params: Params
var _stages: Array[Dictionary] = []
var _state: EconomyState


func before_each() -> void:
	var catalog: DataCatalog = DataLoader.new().load_all().catalog
	_stages = [
		{"id": &"population", "metric": &"population", "mode": &"mean", "prefix": "victory.victorian_demo.population"},
		{"id": &"artisans", "metric": &"class_population", "class_id": &"artisan", "mode": &"mean", "prefix": "victory.victorian_demo.artisans"},
		{"id": &"revenue", "metric": &"revenue", "mode": &"consecutive_minutes", "prefix": "victory.victorian_demo.revenue"},
	]
	var values: Dictionary = {"population.threshold": 60, "population.duration_seconds": 120,
		"artisans.threshold": 20, "artisans.duration_seconds": 300,
		"revenue.threshold": 250, "revenue.required_minutes": 30}
	for key: String in values:
		catalog.base_values[StringName("victory.victorian_demo." + key)] = values[key]
	_params = Params.new(catalog, catalog.roles[&"neutral_administrator"])
	_state = EconomyState.new()
	_state.class_states[&"artisan"] = ClassState.new()


func _ticks(system: VictorySystem, count: int) -> void:
	for index: int in range(count):
		system.tick(_state, _params)


func _minute(system: VictorySystem, revenue: int) -> void:
	_state.taxes_tick = 0
	_ticks(system, 59)
	_state.taxes_tick = revenue
	system.tick(_state, _params)
	_state.taxes_tick = 0


func test_population_requires_full_window_and_uses_its_mean() -> void:
	var system: VictorySystem = VictorySystem.new(_stages)
	_state.population = 120
	_ticks(system, 60)
	_state.population = 0
	_ticks(system, 59)
	assert_false(system.snapshot(_state, _params)["stages"][&"population"]["completed"])
	_ticks(system, 1)
	assert_true(system.snapshot(_state, _params)["stages"][&"population"]["completed"])


func test_artisans_require_their_own_full_window() -> void:
	var system: VictorySystem = VictorySystem.new(_stages)
	_state.class_states[&"artisan"].population = 20
	_ticks(system, 299)
	assert_false(system.snapshot(_state, _params)["stages"][&"artisans"]["completed"])
	_ticks(system, 1)
	assert_true(system.snapshot(_state, _params)["stages"][&"artisans"]["completed"])
	assert_false(system.snapshot(_state, _params)["won"])


func test_revenue_requires_thirty_complete_minutes_at_exact_threshold() -> void:
	var system: VictorySystem = VictorySystem.new(_stages)
	for minute: int in range(29):
		_minute(system, 250)
	assert_eq(system.snapshot(_state, _params)["stages"][&"revenue"]["streak_minutes"], 29)
	_ticks(system, 59)
	assert_false(system.snapshot(_state, _params)["stages"][&"revenue"]["completed"])
	_state.taxes_tick = 250
	system.tick(_state, _params)
	assert_true(system.snapshot(_state, _params)["stages"][&"revenue"]["completed"])
	assert_false(system.snapshot(_state, _params)["won"], "other stages are still missing")


func test_low_minute_resets_without_averaging_or_tolerance_and_explains_cut() -> void:
	var system: VictorySystem = VictorySystem.new(_stages)
	_minute(system, 1000)
	_minute(system, 249)
	var stage: Dictionary = system.snapshot(_state, _params)["stages"][&"revenue"]
	assert_eq(stage["streak_minutes"], 0)
	assert_eq(stage["last_break"], {"minute": 2, "revenue": 249, "threshold": 250, "reason": &"revenue_below_threshold"})
	stage["last_break"]["revenue"] = 0
	assert_eq(system.snapshot(_state, _params)["stages"][&"revenue"]["last_break"]["revenue"], 249)
	for minute: int in range(29):
		_minute(system, 250)
	assert_false(system.snapshot(_state, _params)["stages"][&"revenue"]["completed"])
	_minute(system, 250)
	assert_true(system.snapshot(_state, _params)["stages"][&"revenue"]["completed"])


func test_stages_complete_in_any_order_and_stay_completed() -> void:
	var system: VictorySystem = VictorySystem.new(_stages)
	for minute: int in range(30):
		_minute(system, 250)
	_state.class_states[&"artisan"].population = 20
	_ticks(system, 300)
	_state.class_states[&"artisan"].population = 0
	assert_false(system.snapshot(_state, _params)["won"])
	_state.population = 60
	_ticks(system, 120)
	assert_true(system.snapshot(_state, _params)["won"])
	_state.population = 0
	_ticks(system, 600)
	assert_true(system.snapshot(_state, _params)["won"])


func test_partial_minute_and_windows_survive_state_copy_without_aliases() -> void:
	var system: VictorySystem = VictorySystem.new(_stages)
	_state.population = 60
	_state.taxes_tick = 5
	_ticks(system, 50)
	var values: Dictionary = _state.to_dict()
	_state = EconomyState.from_dict(JSON.parse_string(JSON.stringify(values)))
	_state.taxes_tick = 0
	_ticks(system, 10)
	assert_eq(system.snapshot(_state, _params)["stages"][&"revenue"]["streak_minutes"], 1)
	assert_eq(values["victory"]["elapsed_seconds"], 50)
	assert_eq(values["victory"]["stages"][&"population"]["samples"].size(), 50)


func test_disabled_objectives_leave_economy_state_unchanged() -> void:
	var system: VictorySystem = VictorySystem.new()
	var before: Dictionary = _state.to_dict()
	_ticks(system, 1800)
	assert_eq(_state.to_dict(), before)
	assert_false(system.snapshot(_state, _params)["enabled"])


func test_defeat_has_priority_over_completing_the_final_stage() -> void:
	var system: VictorySystem = VictorySystem.new(_stages)
	_state.population = 60
	_state.class_states[&"artisan"].population = 20
	for minute: int in range(29):
		_minute(system, 250)
	_ticks(system, 59)
	_state.defeat_causes.append(&"bankruptcy")
	_state.taxes_tick = 250
	system.tick(_state, _params)
	assert_false(system.snapshot(_state, _params)["won"])
