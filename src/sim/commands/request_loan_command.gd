class_name RequestLoanCommand
extends SimulationCommand

# Asks the Metropolitan Board for a loan on the rates (issue #72, D-127): whole pence, up to the cap, one at a time.

var _amount: int
var _context: EconomyContext


func _init(amount: int) -> void:
	_amount = amount


func use_context(context: EconomyContext) -> void:
	_context = context


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = false
	var rate: float = LoanSystem.interest_rate(params, LoanSystem.NO_LEGITIMACY, state.loan_late_installments)
	if state.loan != null:
		reason = &"loan_active"
	elif _amount <= 0:
		reason = &"invalid_loan_amount"
	elif _amount > LoanSystem.cap(state, params, _context):
		reason = &"loan_over_cap"
	elif rate == LoanSystem.REFUSED:
		reason = &"loan_not_sanctioned"
	else:
		reason = &""
		LoanSystem.open(state, params, _amount, rate)
		accepted = true
