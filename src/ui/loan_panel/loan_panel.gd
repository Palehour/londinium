class_name LoanPanel
extends VBoxContainer

# The loan section of the stats panel (issue #281). It reads snapshot()["loan"] and the treasury, and sends
# RequestLoanCommand or RepayLoanEarlyCommand. The installment, the balance and the payoff cost are the snapshot's;
# this panel never computes a rate, a surcharge or an installment.

# Whole pence, the simulation's unit. Not a balance number.
const PENNY: float = 1.0
const MIN_AMOUNT: int = 1

var session: GameSession
var _amount: SpinBox
var _request: Button
var _maximum: Button
var _cancel: Button
var _title: Label
var _cap: Label
var _installment: Label
var _balance: Label
var _reason: Label
var _snapshot: Dictionary = {}


func _init() -> void:
	name = "LoanPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_type_size()
	_build()
	# After the children exist: setting this notifies translation changed, and a handler that
	# runs before the buttons exist would assign text on null.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


func setup(game_session: GameSession) -> void:
	session = game_session


# The only refresh. A command waits for the next tick; nothing here pretends the loan is already open.
func show_loan(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	var loan: Dictionary = snapshot["loan"]
	var active: bool = bool(loan["active"])
	var cap: int = int(loan["cap"])
	var defeated: bool = not snapshot["defeat"]["causes"].is_empty()
	_apply_static_texts()
	_cap.text = Strings.text(Strings.LOAN_CAP) % Strings.money(cap)
	_sync_amount(cap)
	var reason: String = _reason_text(loan)
	_reason.text = reason
	_reason.visible = not reason.is_empty()
	var asking: bool = not active
	_amount.visible = asking
	_request.visible = asking
	_request.disabled = defeated or not reason.is_empty()
	_maximum.visible = asking
	_maximum.disabled = defeated or cap < MIN_AMOUNT
	_installment.visible = active
	_balance.visible = active
	_cancel.visible = active
	if not active:
		return
	var cost: int = int(loan["payoff_cost"])
	_installment.text = Strings.text(Strings.LOAN_INSTALLMENT) % Strings.money(int(loan["next_installment"]))
	_balance.text = Strings.text(Strings.LOAN_BALANCE) % Strings.money(int(loan["balance"]))
	_cancel.text = Strings.text(Strings.LOAN_CANCEL) % Strings.money(cost)
	_cancel.disabled = defeated or int(snapshot["economy"]["money"]) < cost


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or _request == null:
		return
	# A locale change does not publish a snapshot. The buttons still have to follow the language.
	if _snapshot.is_empty():
		_apply_static_texts()
		return
	show_loan(_snapshot)


func _apply_type_size() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	if not look.errors.is_empty() or not look.layout.has("font_size"):
		return
	var type_size: Theme = Theme.new()
	type_size.default_font_size = int(look.layout["font_size"])
	theme = type_size


func _build() -> void:
	_title = _label("Title", Strings.text(Strings.LOAN_TITLE))
	_cap = _label("Cap", "")
	_amount = SpinBox.new()
	_amount.name = "Amount"
	_amount.step = PENNY
	_amount.min_value = 0.0
	_amount.max_value = 0.0
	_amount.allow_greater = false
	_amount.allow_lesser = false
	_amount.suffix = Strings.PENCE_SUFFIX
	_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Left and right on the gamepad step a penny instead of leaving the field (issue #68).
	_amount.get_line_edit().gui_input.connect(func(event: InputEvent) -> void:
		if not GamepadBindings.is_gamepad(event) or not _amount.editable:
			return
		if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
			_amount.value += _amount.step if event.is_action_pressed(&"ui_right") else -_amount.step
			_amount.get_line_edit().accept_event())
	add_child(_amount)
	_request = _button("Request", _on_request)
	_maximum = _button("Maximum", _on_maximum)
	_reason = _label("Reason", "")
	_reason.visible = false
	_installment = _label("Installment", "")
	_installment.visible = false
	_balance = _label("Balance", "")
	_balance.visible = false
	_cancel = _button("Cancel", _on_cancel)
	_cancel.visible = false
	_apply_static_texts()


func _apply_static_texts() -> void:
	_title.text = Strings.text(Strings.LOAN_TITLE)
	_request.text = Strings.text(Strings.LOAN_REQUEST)
	_maximum.text = Strings.text(Strings.LOAN_MAXIMUM)


# Refused before an empty cap: a sanctioned city with no taxes is over the cap, an unsanctioned one with a cap is not.
func _reason_text(loan: Dictionary) -> String:
	if bool(loan["active"]):
		return Strings.reason(&"loan_active")
	if float(loan["rate"]) == LoanSystem.REFUSED:
		return Strings.reason(&"loan_not_sanctioned")
	if int(loan["cap"]) < MIN_AMOUNT:
		return Strings.reason(&"loan_over_cap")
	return ""


# The typed amount is the player's, not the snapshot's. A refresh must not replace it while the field has focus,
# and it never sends a command.
func _sync_amount(cap: int) -> void:
	_amount.step = PENNY
	if cap >= MIN_AMOUNT:
		_amount.max_value = float(cap)
		_amount.min_value = float(MIN_AMOUNT)
		return
	_amount.min_value = 0.0
	_amount.max_value = 0.0


func _on_request() -> void:
	if _request.disabled or session == null:
		return
	session.submit_command(RequestLoanCommand.new(int(_amount.value)))


func _on_maximum() -> void:
	if _maximum.disabled:
		return
	_amount.value = _amount.max_value


func _on_cancel() -> void:
	if _cancel.disabled or session == null:
		return
	session.submit_command(RepayLoanEarlyCommand.new())


func _label(node_name: String, text: String) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	return label


func _button(node_name: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	add_child(button)
	return button
