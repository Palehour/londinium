extends GutTest

# Issue #323 (D-172): debt_balance keeps the last value of a bucket; debt_payments sums what was paid.


var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = Params.new(_catalog, RoleDef.new())
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


func _history() -> StatsHistory:
	return StatsHistory.new(SeriesRegistry.build(_params, _context), _params, _context)


func _def(id: StringName) -> SeriesDef:
	for def: SeriesDef in SeriesRegistry.build(_params, _context):
		if def.id == id:
			return def
	return null


# A level: the bucket keeps the last sample, not the sum and not the average.
func test_debt_balance_keeps_the_last_value_of_the_bucket() -> void:
	var def: SeriesDef = _def(&"debt_balance")
	assert_not_null(def, "debt_balance is registered")
	if def == null:
		return
	assert_eq(def.unit, &"pence")
	assert_eq(def.aggregation, SeriesDef.AGGREGATION_LAST)
	assert_eq(def.dimensions, {})
	assert_eq(def.label_key, &"ui.stats.debt_balance")
	assert_has(Strings.all_keys(), def.label_key)
	var seconds: int = int(_params.get_value(&"stats.medium.bucket_seconds"))
	var history: StatsHistory = _history()
	var state: EconomyState = EconomyState.new()
	assert_eq(def.sampler.call(state), 0.0, "No loan is nothing owed")
	var last: int = 0
	var summed: int = 0
	for second: int in seconds:
		var balance: int = 1000 - second * 10
		last = balance
		summed += balance
		var loan: LoanState = LoanState.new()
		loan.total = balance
		loan.installments = 1
		state.loan = loan
		history.record(state)
	var series: Dictionary = history.series(&"debt_balance", StatsHistory.TIER_MEDIUM)
	assert_eq(series["total"].size(), 1)
	assert_eq(series["total"][0], float(last), "The bucket keeps the last balance")
	assert_ne(series["total"][0], float(summed), "A sum would be a different number")
	assert_ne(series["total"][0], series["mean"][0], "An average would be a different number")


# A flow: the bucket adds every tick's payment, it does not keep only the last one.
func test_debt_payments_sums_the_bucket() -> void:
	var def: SeriesDef = _def(&"debt_payments")
	assert_not_null(def, "debt_payments is registered")
	if def == null:
		return
	assert_eq(def.unit, &"pence")
	assert_eq(def.aggregation, SeriesDef.AGGREGATION_SUM)
	assert_eq(def.dimensions, {})
	assert_eq(def.label_key, &"ui.stats.debt_payments")
	assert_has(Strings.all_keys(), def.label_key)
	var seconds: int = int(_params.get_value(&"stats.medium.bucket_seconds"))
	var history: StatsHistory = _history()
	var state: EconomyState = EconomyState.new()
	assert_eq(def.sampler.call(state), 0.0, "Nothing paid yet")
	var last: int = 0
	var summed: int = 0
	for second: int in seconds:
		var paid: int = 7 if second % 2 == 0 else 3
		last = paid
		summed += paid
		state.loan_paid_tick = paid
		history.record(state)
	var series: Dictionary = history.series(&"debt_payments", StatsHistory.TIER_MEDIUM)
	assert_eq(series["total"].size(), 1)
	assert_eq(series["total"][0], float(summed), "The bucket adds the payments")
	assert_ne(series["total"][0], float(last), "The last payment alone is not the flow")
	assert_ne(series["total"][0], series["mean"][0], "An average would be a different number")
