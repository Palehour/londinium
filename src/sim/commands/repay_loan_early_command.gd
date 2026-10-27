class_name RepayLoanEarlyCommand
extends SimulationCommand

# Cancels the loan (issue #72, D-129): the balance plus the surcharge, only if the treasury covers it. It also ends the
# receiver, but only a loan cancelled outside the receiver earns legitimacy (D-138).


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = false
	if state.loan == null:
		reason = &"no_active_loan"
		return
	var cost: int = LoanSystem.payoff_cost(state.loan, params)
	if state.money < cost:
		reason = &"insufficient_money"
		return
	state.money -= cost
	state.loan_paid_tick += cost
	# The legitimacy of D-116 arrives with issue #84, which reads this gain.
	if not state.loan.receiver:
		state.legitimacy_gain_tick += float(params.get_value(&"loan.early_payoff_legitimacy_gain"))
	state.loan = null
	reason = &""
	accepted = true
