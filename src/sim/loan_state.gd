class_name LoanState
extends RefCounted

# The one active loan (issue #72, D-127, D-129): principal plus interest, paid in equal whole-penny installments.
var principal: int = 0
var total: int = 0
var installments: int = 0
var installments_paid: int = 0
var paid: int = 0
# Ticks left before the next installment falls due, the current one included.
var due_in_seconds: int = 0
# Installments that fell due and are still unpaid, and for how long the oldest one has been (D-128).
var overdue: int = 0
var arrears_seconds: int = 0
# The receiver of D-128: once in, every tax goes to the debt and the window runs.
var receiver: bool = false
var receiver_seconds: int = 0


func balance() -> int:
	return total - paid


# Whole pence, so the last installment takes the remainder and they all add up to the total exactly.
func installment(index: int) -> int:
	var base: int = total / installments
	return base if index < installments - 1 else total - base * (installments - 1)


func to_dict() -> Dictionary:
	return {"principal": principal, "total": total, "installments": installments,
		"installments_paid": installments_paid, "paid": paid, "due_in_seconds": due_in_seconds,
		"overdue": overdue, "arrears_seconds": arrears_seconds, "receiver": receiver,
		"receiver_seconds": receiver_seconds}


static func from_dict(values: Dictionary) -> LoanState:
	var result: LoanState = LoanState.new()
	result.principal = int(values.get("principal", 0))
	result.total = int(values.get("total", 0))
	result.installments = int(values.get("installments", 1))
	result.installments_paid = int(values.get("installments_paid", 0))
	result.paid = int(values.get("paid", 0))
	result.due_in_seconds = int(values.get("due_in_seconds", 0))
	result.overdue = int(values.get("overdue", 0))
	result.arrears_seconds = int(values.get("arrears_seconds", 0))
	result.receiver = bool(values.get("receiver", false))
	result.receiver_seconds = int(values.get("receiver_seconds", 0))
	return result
