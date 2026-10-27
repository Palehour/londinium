extends GutTest

# Issue #72: loans on the rates (D-127), fixed installments and early payoff (D-129), the receiver and the bankruptcy
# with a loan (D-128), with the values of D-138. The sanction and the rate read the legitimacy reserve of #84 (D-139,
# point 3). The unit tests run the loan rules on a bare state, which has no factions and so no legitimacy: the rate
# there is the base one unless a test sets the reserve. R there is the head tax of 10 employed workers.

const STRIP: StringName = &"riverside_strip"
const WORKERS: int = 10

var _catalog: DataCatalog
var _strip: EconomyContext
var _params: Params
var _game_params: Params
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_strip = EconomyContext.new(_catalog, _catalog.maps[STRIP])


func before_each() -> void:
	_params = _with({})


func _with(overrides: Dictionary[StringName, float]) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


func _value(key: StringName) -> float:
	return float(_params.get_value(key))


func _state(money: int) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = money
	state.tax_rate = _value(&"population.tax.rate")
	state.buildings.append({"definition_id": &"mill", "cell": [0, 0], "workers": WORKERS})
	return state


func _r() -> float:
	return WORKERS * _value(&"population.tax.rate") * _value(&"population.tax.base_per_employed_worker_per_minute")


func _cap() -> int:
	return floori(_value(&"loan.cap_multiple") * _r())


func _request(state: EconomyState, amount: int) -> SimulationCommand:
	var command: RequestLoanCommand = RequestLoanCommand.new(amount)
	command.execute(state, _params, _rng)
	return command


func _repay(state: EconomyState) -> SimulationCommand:
	var command: RepayLoanEarlyCommand = RepayLoanEarlyCommand.new()
	command.execute(state, _params, _rng)
	return command


func _ticks(state: EconomyState, count: int, taxes: int = 0) -> void:
	for index: int in range(count):
		state.reset_flows()
		state.taxes_tick = taxes
		state.money += taxes
		LoanSystem.tick(state, _params)


func test_the_values_are_those_of_d_138() -> void:
	var expected: Dictionary[StringName, float] = {&"loan.cap_multiple": 20, &"loan.base_interest": 0.10,
		&"loan.rate_by_rating": 0.10, &"loan.sanction_min_legitimacy": 30, &"loan.rate_full_legitimacy": 70,
		&"loan.rating_arrears_penalty": 10, &"loan.term_installments": 10, &"loan.installment_interval_s": 300,
		&"loan.early_payoff_surcharge": 0.05, &"loan.early_payoff_legitimacy_gain": 5, &"loan.default_after_s": 600,
		&"loan.receiver_window_s": 1500}
	for key: StringName in expected:
		assert_almost_eq(_value(key), expected[key], 0.000001, str(key))


# Criterion 1.
func test_a_loan_within_the_cap_adds_the_exact_principal() -> void:
	var state: EconomyState = _state(100)
	var command: SimulationCommand = _request(state, _cap())
	assert_true(command.accepted, str(command.reason))
	assert_eq(state.money, 100 + _cap())
	assert_eq(state.loan.principal, _cap())
	assert_eq(state.loan.total, _cap() + floori(_cap() * 0.10), "Base interest without legitimacy (#84)")


func test_a_loan_outside_the_cap_or_not_positive_is_refused_without_changes() -> void:
	for amount: int in [_cap() + 1, 0, -5]:
		var state: EconomyState = _state(100)
		var before: Dictionary = state.to_dict()
		var command: SimulationCommand = _request(state, amount)
		assert_false(command.accepted)
		assert_eq(command.reason, &"loan_over_cap" if amount > 0 else &"invalid_loan_amount")
		assert_eq(state.to_dict(), before)


func test_a_city_without_taxes_has_no_cap() -> void:
	var state: EconomyState = _state(100)
	state.tax_rate = 0.0
	assert_eq(_request(state, 1).reason, &"loan_over_cap")


func test_only_one_loan_at_a_time() -> void:
	var state: EconomyState = _state(100)
	assert_true(_request(state, 10).accepted)
	var command: SimulationCommand = _request(state, 10)
	assert_false(command.accepted)
	assert_eq(command.reason, &"loan_active")
	assert_eq(state.money, 110)


func test_the_rate_follows_the_rating_and_refuses_below_the_sanction() -> void:
	assert_almost_eq(LoanSystem.interest_rate(_params, LoanSystem.NO_LEGITIMACY, 5), 0.10, 0.000001)
	assert_almost_eq(LoanSystem.interest_rate(_params, 90.0, 0), 0.10, 0.000001)
	assert_almost_eq(LoanSystem.interest_rate(_params, 70.0, 0), 0.10, 0.000001)
	assert_almost_eq(LoanSystem.interest_rate(_params, 50.0, 0), 0.15, 0.000001, "Halfway between 70 and 30")
	assert_almost_eq(LoanSystem.interest_rate(_params, 30.0, 0), 0.20, 0.000001)
	assert_eq(LoanSystem.interest_rate(_params, 29.0, 0), LoanSystem.REFUSED)
	assert_almost_eq(LoanSystem.interest_rate(_params, 50.0, 2), 0.20, 0.000001, "Two late installments: 30")
	assert_eq(LoanSystem.interest_rate(_params, 50.0, 3), LoanSystem.REFUSED, "Three late installments: 20")


# Criterion 2: 601 pence in 10 installments are nine of 60 and a last one of 61.
# D-139, point 3: the reserve of #84 makes the loan dearer as it falls and refuses it below the sanction minimum.
func test_a_lower_legitimacy_makes_the_loan_dearer_and_then_refuses_it() -> void:
	var totals: Array[int] = []
	for legitimacy: float in [70.0, 50.0, 30.0]:
		var state: EconomyState = _state(100)
		state.legitimacy = legitimacy
		var command: SimulationCommand = _request(state, _cap())
		assert_true(command.accepted, str(command.reason))
		totals.append(state.loan.total)
	assert_eq(totals[0], _cap() + floori(_cap() * 0.10), "70: the base rate")
	assert_eq(totals[1], _cap() + floori(_cap() * 0.15), "50: halfway")
	assert_eq(totals[2], _cap() + floori(_cap() * 0.20), "30: the dearest rate")
	assert_lt(totals[0], totals[1])
	assert_lt(totals[1], totals[2])
	var refused: EconomyState = _state(100)
	refused.legitimacy = 29.0
	var before: Dictionary = refused.to_dict()
	var command: SimulationCommand = _request(refused, _cap())
	assert_false(command.accepted)
	assert_eq(command.reason, &"loan_not_sanctioned")
	assert_eq(refused.to_dict(), before, "Refused without changes")


func test_the_game_quotes_the_rate_of_its_reserve() -> void:
	var sim: Simulation = _game()
	sim.tick()
	var legitimacy: float = sim.snapshot()["factions"]["legitimacy"]
	assert_almost_eq(_loan(sim)["rate"], LoanSystem.interest_rate(_game_params, legitimacy, 0), 0.000001)
	assert_gt(_loan(sim)["rate"], _value(&"loan.base_interest"), "Below 70 the loan costs more than the base rate")


func test_the_installments_add_up_to_the_total_and_the_last_takes_the_remainder() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	var loan: LoanState = state.loan
	assert_eq(loan.total, 601)
	var sum: int = 0
	for index: int in range(loan.installments):
		sum += loan.installment(index)
	assert_eq(sum, loan.total)
	assert_eq(loan.installment(0), 60)
	assert_eq(loan.installment(9), 61)


# Criteria 2 and 3: every 300 s, the last one closes the loan with exactly the total paid.
func test_the_installments_are_charged_on_time_until_the_loan_is_paid() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 601
	_ticks(state, 299)
	assert_eq(state.money, 601, "Nothing due before 300 s")
	_ticks(state, 1)
	assert_eq(state.money, 541)
	assert_eq(state.loan_paid_tick, 60, "The installment counts as rates spending this tick")
	_ticks(state, 2400)
	assert_eq(state.money, 61)
	assert_not_null(state.loan)
	_ticks(state, 300)
	assert_eq(state.money, 0)
	assert_null(state.loan, "Paid off")
	assert_eq(state.loan_late_installments, 0)


func test_a_treasury_exactly_equal_to_the_installment_pays_it() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 60
	_ticks(state, 300)
	assert_eq(state.money, 0)
	assert_eq(state.loan.overdue, 0)


func test_an_overdue_installment_paid_before_the_default_ends_the_arrears() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 0
	_ticks(state, 300)
	assert_eq(state.loan.overdue, 1)
	assert_eq(state.loan_late_installments, 1, "Lowers the rating of the next loan")
	_ticks(state, 299)
	state.money = 60
	_ticks(state, 1)
	assert_eq(state.loan.overdue, 1, "The second one fell due with the first paid")
	state.money = 60
	_ticks(state, 1)
	assert_eq(state.loan.overdue, 0)
	assert_eq(state.loan.arrears_seconds, 0)
	# Past the 600 s the first installment would have needed for the receiver.
	_ticks(state, 299)
	assert_false(state.loan.receiver)


# Criterion 5: 600 s in arrears bring the receiver, who takes every tax.
func test_arrears_bring_the_receiver_who_takes_the_taxes() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 0
	_ticks(state, 300 + 599)
	assert_false(state.loan.receiver)
	_ticks(state, 1)
	assert_true(state.loan.receiver, "600 s after the installment fell due")
	assert_true(LoanSystem.in_default(state))
	_ticks(state, 10, 7)
	assert_eq(state.money, 0, "Every tax went to the debt")
	assert_eq(state.loan.balance(), 601 - 70)
	assert_eq(state.loan_paid_tick, 7)


# Criterion 6: paid within the window, no defeat and no receiver.
func test_a_debt_paid_within_the_receiver_window_ends_it_without_defeat() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 0
	_ticks(state, 900)
	_ticks(state, 1, 600)
	assert_eq(state.loan.balance(), 1)
	_ticks(state, 1, 600)
	assert_null(state.loan)
	assert_eq(state.money, 599, "Only the debt is taken")
	assert_true(state.defeat_causes.is_empty())


func test_a_debt_not_paid_within_the_receiver_window_is_a_bankruptcy_with_a_loan() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 0
	_ticks(state, 900)
	_ticks(state, 1499, 0)
	assert_true(state.defeat_causes.is_empty())
	_ticks(state, 1, 0)
	assert_eq(state.defeat_causes, [LoanSystem.DEFEAT_CAUSE])


func test_without_defeats_the_receiver_never_ends_the_game() -> void:
	_params = _with({&"defeat.enabled": 0})
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 0
	_ticks(state, 900 + 3000)
	assert_true(state.defeat_causes.is_empty())
	assert_true(state.loan.receiver)


# Criterion 4: balance plus 5% on it, and 5 points of legitimacy for #84.
func test_early_payoff_costs_the_balance_plus_the_surcharge_and_earns_legitimacy() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 60
	_ticks(state, 300)
	assert_eq(state.loan.balance(), 541)
	state.money = 541 + 27
	state.reset_flows()
	var command: SimulationCommand = _repay(state)
	assert_true(command.accepted, str(command.reason))
	assert_eq(state.money, 0, "541 + floor(541 x 0.05)")
	assert_null(state.loan)
	assert_eq(state.legitimacy_gain_tick, 5.0)
	assert_eq(state.loan_paid_tick, 568)


func test_early_payoff_without_the_money_is_refused_without_changes() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 601 + 29
	var before: Dictionary = state.to_dict()
	var command: SimulationCommand = _repay(state)
	assert_false(command.accepted)
	assert_eq(command.reason, &"insufficient_money")
	assert_eq(state.to_dict(), before)
	assert_eq(_repay(_state(1000)).reason, &"no_active_loan")


func test_early_payoff_ends_the_receiver_without_legitimacy() -> void:
	var state: EconomyState = _state(0)
	assert_true(_request(state, 547).accepted)
	state.money = 0
	_ticks(state, 900)
	assert_true(state.loan.receiver)
	state.money = 1000
	assert_true(_repay(state).accepted)
	assert_null(state.loan)
	assert_eq(state.legitimacy_gain_tick, 0.0)


# Criterion 7: with the loan in default only the receiver leads to bankruptcy.
func test_a_loan_in_default_holds_the_bankruptcy_without_a_loan() -> void:
	var params: Params = _with({&"defeat.grace_seconds": 0, &"defeat.bankruptcy.duration_seconds": 5})
	var defeat: DefeatSystem = DefeatSystem.new()
	var state: EconomyState = _state(0)
	state.population = 100
	assert_true(_request(state, 547).accepted)
	state.loan.overdue = 1
	state.money = -1000
	for index: int in range(10):
		defeat.tick(state, params)
	assert_eq(state.bankruptcy.elapsed_seconds, 0)
	assert_true(state.defeat_causes.is_empty())
	state.loan = null
	for index: int in range(5):
		defeat.tick(state, params)
	assert_eq(state.defeat_causes, [&"bankruptcy"], "Without the loan D-013 runs as before")


# D-013 and D-131: "con préstamo impago", so a loan up to date between installments holds it too (Bailey, PR #279).
func test_a_loan_up_to_date_holds_the_bankruptcy_without_a_loan() -> void:
	var params: Params = _with({&"defeat.grace_seconds": 0, &"defeat.bankruptcy.duration_seconds": 180})
	var defeat: DefeatSystem = DefeatSystem.new()
	var state: EconomyState = _state(0)
	state.population = 100
	assert_true(_request(state, 547).accepted)
	state.money = -1000
	for index: int in range(299):
		LoanSystem.tick(state, params)
		defeat.tick(state, params)
	assert_eq(state.loan.overdue, 0, "No installment fell due yet")
	assert_eq(state.bankruptcy.elapsed_seconds, 0)
	assert_true(state.defeat_causes.is_empty())


func test_a_saved_state_keeps_the_loan_and_a_game_without_one_saves_as_before() -> void:
	var state: EconomyState = _state(0)
	assert_false(state.to_dict().has("loan"))
	assert_false(state.to_dict().has("loan_late_installments"))
	assert_true(_request(state, 547).accepted)
	state.money = 0
	_ticks(state, 950)
	var loaded: EconomyState = EconomyState.from_dict(bytes_to_var(var_to_bytes(state.to_dict())))
	assert_eq(loaded.to_dict(), state.to_dict())
	assert_true(loaded.loan.receiver)


# The game itself: the taxes of the strip's start (R from the wharf workers) with nothing else spending or defeating.
func _game() -> Simulation:
	var role: RoleDef = RoleDef.new()
	for key: StringName in [&"population.bread_per_person_per_minute", &"population.growth.immigration_per_minute",
			&"population.growth.emigration_per_minute", &"population.satisfaction.overcrowding_weight",
			&"defeat.hunger.threshold", &"transport.cost_per_unit_per_m"]:
		role.modifiers.append(Modifier.new(key, &"set", 0))
	for id: StringName in _catalog.buildings:
		for suffix: String in ["wage_per_worker_per_minute", "upkeep_per_minute"]:
			role.modifiers.append(Modifier.new(StringName("building.%s.%s" % [id, suffix]), &"set", 0))
	_game_params = Params.new(_catalog, role)
	var state: EconomyState = EconomyState.new()
	state.money = 0
	state.wheat_purchases_enabled = false
	state.population = int(_game_params.get_value(&"startup.population"))
	return Simulation.create_new(_game_params, state, 42, _strip)


func _loan(sim: Simulation) -> Dictionary:
	return sim.snapshot()["loan"]


# Criterion 8: the same game saved twice mid-term plays on exactly as without the save (the receiver: unit test above).
func test_the_game_charges_the_loan_and_a_save_plays_on_the_same() -> void:
	var sim: Simulation = _game()
	sim.tick()
	var cap: int = _loan(sim)["cap"]
	assert_gt(cap, 0, "The strip starts with taxes")
	var command: RequestLoanCommand = RequestLoanCommand.new(cap)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))
	var played: int = 2
	for save_tick: int in [150, 1200]:
		var other: Simulation = Simulation.from_save(_game_params, _strip, [],
			bytes_to_var(var_to_bytes(_advance(sim, played, save_tick).to_save())))
		played = save_tick + 300
		for index: int in range(300):
			sim.tick()
			other.tick()
		assert_eq(other.snapshot()["loan"], sim.snapshot()["loan"], "Saved at %d" % save_tick)
		assert_eq(other.snapshot()["economy"], sim.snapshot()["economy"])


# Snapshots are slow, so the ticks are counted here: _game() has run `from_tick` of them.
func _advance(sim: Simulation, from_tick: int, to_tick: int) -> Simulation:
	for index: int in range(from_tick, to_tick):
		sim.tick()
	return sim


# Without taxes the principal pays eight installments and the ninth goes unpaid: arrears, receiver, defeat. The game
# starts its reserve at 50 (D-141), so the Board sanctions the loan at 0.15 (D-138): eight installments are 92% of
# the principal and nine would be 103.5%.
func test_the_game_stops_on_a_bankruptcy_with_a_loan_and_only_that_one() -> void:
	var sim: Simulation = _game()
	sim.tick()
	var cap: int = _loan(sim)["cap"]
	var rate: float = _loan(sim)["rate"]
	assert_almost_eq(rate, 0.15, 0.001, "The rate of a reserve of 50, after one tick of it moving")
	var command: RequestLoanCommand = RequestLoanCommand.new(cap)
	sim.apply_command(command)
	sim.apply_command(SetTaxCommand.new(0.0))
	sim.tick()
	assert_true(command.accepted, str(command.reason))
	assert_eq(_loan(sim)["total"], cap + floori(cap * rate), "Charged at the sanctioned rate")
	# Taken on tick 2, so the ninth installment falls due on tick 2701 and the receiver comes 600 s after it.
	var receiver_in: int = 2701 + 600
	_advance(sim, 2, receiver_in + 1500 - 1)
	assert_true(sim.snapshot()["loan"]["receiver"])
	assert_true(sim.snapshot()["defeat"]["causes"].is_empty())
	sim.tick()
	assert_eq(sim.snapshot()["defeat"]["causes"], [LoanSystem.DEFEAT_CAUSE])
