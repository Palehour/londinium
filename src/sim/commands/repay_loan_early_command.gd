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
	# FactionSystem adds this gain to the legitimacy reserve of #84 this very tick.
	if not state.loan.receiver:
		state.legitimacy_gain_tick += float(params.get_value(&"loan.early_payoff_legitimacy_gain"))
	state.loan = null
	reason = &""
	accepted = true
