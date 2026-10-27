class_name LoanSystem
extends RefCounted

# Loans guaranteed by the rates (issue #72): one at a time, capped at a multiple of the head tax per minute (D-127),
# repaid in fixed installments or early with a surcharge (D-129). Installments in arrears for too long bring in the
# receiver, who takes every tax until the debt is paid or its window runs out and the game is lost (D-128).
const DEFEAT_CAUSE: StringName = &"loan_bankruptcy"
# A state without factions (a bare test state, an era without factions.json) has no legitimacy (D-116, issue #84):
# the sanction is not checked and the rate is the base one.
const NO_LEGITIMACY: float = -1.0
const REFUSED: float = -1.0


# R x loan.cap_multiple, in whole pence; R is the head tax the city pays per minute at its current rate.
static func cap(state: EconomyState, params: Params, context: EconomyContext) -> int:
	return floori(float(params.get_value(&"loan.cap_multiple")) * MoneySystem.tax_per_minute(state, params, context))


# The rate the Metropolitan Board sanctions (D-127), or REFUSED. The rating is the legitimacy less a penalty for each
# installment that ever fell due unpaid; below the sanction minimum the loan is refused, and from there up to the full
# legitimacy the rate falls linearly from base + rate_by_rating to base.
static func interest_rate(params: Params, legitimacy: float, late_installments: int) -> float:
	var base: float = float(params.get_value(&"loan.base_interest"))
	if legitimacy == NO_LEGITIMACY:
		return base
	var rating: float = legitimacy - late_installments * float(params.get_value(&"loan.rating_arrears_penalty"))
	var minimum: float = float(params.get_value(&"loan.sanction_min_legitimacy"))
	var full: float = float(params.get_value(&"loan.rate_full_legitimacy"))
	if rating < minimum:
		return REFUSED
	if rating >= full:
		return base
	return base + float(params.get_value(&"loan.rate_by_rating")) * (full - rating) / (full - minimum)


# The legitimacy reserve of #84 the sanction reads (D-139, point 3: low legitimacy makes the loan dearer or refuses it).
static func legitimacy_of(state: EconomyState) -> float:
	return state.legitimacy if state.legitimacy >= 0.0 else NO_LEGITIMACY


static func open(state: EconomyState, params: Params, principal: int, rate: float) -> void:
	var loan: LoanState = LoanState.new()
	loan.principal = principal
	loan.total = principal + floori(principal * rate)
	loan.installments = int(params.get_value(&"loan.term_installments"))
	loan.due_in_seconds = int(params.get_value(&"loan.installment_interval_s"))
	state.loan = loan
	state.money += principal


# What cancelling costs now (D-129): the balance, overdue installments included, plus the surcharge on it.
static func payoff_cost(loan: LoanState, params: Params) -> int:
	return loan.balance() + floori(loan.balance() * float(params.get_value(&"loan.early_payoff_surcharge")))


# Installments in arrears or the receiver in: the loan's default (D-128).
static func in_default(state: EconomyState) -> bool:
	return state.loan != null and (state.loan.overdue > 0 or state.loan.receiver)


# After MoneySystem, so the receiver takes the taxes of this very tick.
static func tick(state: EconomyState, params: Params) -> void:
	var loan: LoanState = state.loan
	if loan == null:
		return
	if loan.receiver:
		_run_receiver(state, params, loan)
		return
	var fell_due: bool = false
	if loan.installments_paid + loan.overdue < loan.installments:
		loan.due_in_seconds -= 1
		if loan.due_in_seconds <= 0:
			fell_due = true
			loan.overdue += 1
			loan.due_in_seconds = int(params.get_value(&"loan.installment_interval_s"))
	_pay_overdue(state, loan)
	if fell_due and loan.overdue > 0:
		state.loan_late_installments += 1
	if loan.installments_paid == loan.installments:
		state.loan = null
		return
	# Counted from the tick the installment fell due, so the receiver comes once default_after_s have passed.
	loan.arrears_seconds = loan.arrears_seconds + 1 if loan.overdue > 0 else 0
	if loan.arrears_seconds > int(params.get_value(&"loan.default_after_s")):
		loan.receiver = true


# Oldest first, each one whole: a treasury exactly equal to the installment pays it.
static func _pay_overdue(state: EconomyState, loan: LoanState) -> void:
	while loan.overdue > 0 and state.money >= loan.installment(loan.installments_paid):
		var amount: int = loan.installment(loan.installments_paid)
		state.money -= amount
		state.loan_paid_tick += amount
		loan.paid += amount
		loan.installments_paid += 1
		loan.overdue -= 1


# Every tax goes to the debt. Without taxes no decree upkeep can be paid (D-125): decrees arrive with issue #71.
static func _run_receiver(state: EconomyState, params: Params, loan: LoanState) -> void:
	var taken: int = clampi(state.taxes_tick, 0, loan.balance())
	state.money -= taken
	state.loan_paid_tick += taken
	loan.paid += taken
	if loan.balance() == 0:
		state.loan = null
		return
	loan.receiver_seconds += 1
	if loan.receiver_seconds >= int(params.get_value(&"loan.receiver_window_s")) \
			and params.get_value(&"defeat.enabled") and state.defeat_causes.is_empty():
		state.defeat_causes.append(DEFEAT_CAUSE)


static func snapshot(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary:
	var result: Dictionary = {"active": state.loan != null, "cap": cap(state, params, context),
		"rate": interest_rate(params, legitimacy_of(state), state.loan_late_installments),
		"late_installments": state.loan_late_installments, "paid_tick": state.loan_paid_tick,
		"legitimacy_gain_tick": state.legitimacy_gain_tick}
	var loan: LoanState = state.loan
	if loan != null:
		result.merge(loan.to_dict())
		result["balance"] = loan.balance()
		result["next_installment"] = loan.installment(loan.installments_paid)
		result["payoff_cost"] = payoff_cost(loan, params)
	return result
