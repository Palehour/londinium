extends GutTest

var _documents: Dictionary[String, Dictionary] = {}

func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		var dir: DirAccess = DirAccess.open("res://data/" + folder)
		if dir == null:
			continue
		for file_name: String in dir.get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))

func test_chain_pending_literal_sin_dato_only_for_pending_keys() -> void:
	_documents["economy/ui.json"]["chains"]["bottleneck_margin"] = "sin dato"
	_documents["economy/ui.json"]["chains"]["min_samples"] = "sin dato"
	_documents["economy/ui.json"]["chains"]["tie_break"] = "sin dato"
	var res: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(res.is_ok())
	# non literal for pending rejects
	_documents["economy/ui.json"]["chains"]["bottleneck_margin"] = "foo"
	res = DataLoader.new().load_documents(_documents)
	assert_false(res.is_ok())
	# non pending key with sin dato rejects
	_documents["economy/population.json"]["initial_bread"] = "sin dato"
	res = DataLoader.new().load_documents(_documents)
	assert_false(res.is_ok())
	assert_true(str(res.errors).find("initial_bread") >= 0)

func test_chain_pending_hasvalue_false_when_sin_dato() -> void:
	_documents["economy/ui.json"]["chains"]["bottleneck_margin"] = "sin dato"
	_documents["economy/ui.json"]["chains"]["min_samples"] = "sin dato"
	_documents["economy/ui.json"]["chains"]["tie_break"] = "sin dato"
	var res: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(res.is_ok())
	var p: Params = Params.new(res.catalog, res.catalog.roles[&"neutral_administrator"])
	assert_false(p.has_value(&"ui.chains.bottleneck_margin"))
	assert_false(p.has_value(&"ui.chains.min_samples"))
	assert_false(p.has_value(&"ui.chains.tie_break"))

func test_chain_pending_populated_margin01_min2_tie_getvalue_works() -> void:
	_documents["economy/ui.json"]["chains"] = {
		"bottleneck_margin": 0.1,
		"min_samples": 2,
		"tie_break": "upstream"
	}
	var res: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(res.is_ok())
	var p: Params = Params.new(res.catalog, res.catalog.roles[&"neutral_administrator"])
	assert_true(p.has_value(&"ui.chains.bottleneck_margin"))
	assert_eq(p.get_value(&"ui.chains.bottleneck_margin"), 0.1)
	assert_eq(p.get_value(&"ui.chains.min_samples"), 2)
	assert_eq(p.get_value(&"ui.chains.tie_break"), "upstream")

func test_chain_pending_invalid_margin_minfraction_min0_tie_unknown_reject() -> void:
	_documents["economy/ui.json"]["chains"]["bottleneck_margin"] = 1.1
	var res: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_false(res.is_ok())

	_documents["economy/ui.json"]["chains"]["bottleneck_margin"] = 0.05
	_documents["economy/ui.json"]["chains"]["min_samples"] = 0
	res = DataLoader.new().load_documents(_documents)
	assert_false(res.is_ok())
	_documents["economy/ui.json"]["chains"]["min_samples"] = 1.5
	res = DataLoader.new().load_documents(_documents)
	assert_false(res.is_ok())
	_documents["economy/ui.json"]["chains"]["min_samples"] = 1
	_documents["economy/ui.json"]["chains"]["tie_break"] = "downstream"
	res = DataLoader.new().load_documents(_documents)
	assert_false(res.is_ok())


func test_changing_margin_in_documents_changes_the_real_window_result() -> void:
	assert_eq(_window_result(0.0)["limiting_link"], &"wharf")
	assert_eq(_window_result(0.6)["status"], &"no_bottleneck")


func _window_result(margin: float) -> Dictionary:
	_documents["economy/ui.json"]["chains"] = {
		"bottleneck_margin": margin, "min_samples": 1, "tie_break": "upstream"}
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	var context: EconomyContext = EconomyContext.new(loaded.catalog, loaded.catalog.maps[&"whitechapel_1850s"])
	var state: EconomyState = EconomyState.new()
	state.money = 10000
	state.buildings.assign([
		{"definition_id": &"wharf", "cell": [0, 0], "workers": 1},
		{"definition_id": &"mill", "cell": [1, 1], "workers": 3},
		{"definition_id": &"bakery", "cell": [2, 2], "workers": 3},
	])
	var history: StatsHistory = StatsHistory.new(SeriesRegistry.build(params, context), params, context)
	history.capture_opening(state)
	for tick: int in 60:
		state.bread_demand_tick = 0.2
		history.record(state)
	var ranges: Array[Dictionary] = [{"id": &"fixture", "tier": StatsHistory.TIER_CHAPTER, "span_seconds": 0}]
	return ChainBottleneck.snapshot(history, params, context, state, ranges)[&"fixture"]
