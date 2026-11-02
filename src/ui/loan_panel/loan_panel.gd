class_name LoanPanel
extends VBoxContainer

# The loan section of the stats panel (issue #281, quote in #334). It reads snapshot()["loan"] and
# GameSession.loan_quote, and sends RequestLoanCommand or RepayLoanEarlyCommand. It never computes a rate,
# a surcharge or an installment.

# Whole pence, the simulation's unit. Not a balance number. PERCENT only turns a ratio into a label.
const PENNY: float = 1.0
const PERCENT: float = 100.0
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
var _quote_rate: Label
var _quote_interest: Label
var _quote_term: Label
var _quote_surcharge: Label
var _quote_share: Label
var _quote_risk: Label
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


# Refresh from a snapshot. A command waits for the next tick; the quote also refreshes when the amount changes.
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
	_show_quote()
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
	_amount.value_changed.connect(_on_amount_changed)
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
	_quote_rate = _label("QuoteRate", "")
	_quote_interest = _label("QuoteInterest", "")
	_quote_term = _label("QuoteTerm", "")
	_quote_surcharge = _label("QuoteSurcharge", "")
	_quote_share = _label("QuoteShare", "")
	_quote_risk = _label("QuoteRisk", "")
	_hide_quote()
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


# The typed amount is the player's. Refreshing the quote does not ask.
func _on_amount_changed(_value: float) -> void:
	if session == null or _snapshot.is_empty():
		return
	_show_quote()


# Hidden unless a sanctioned amount can still be asked. Every figure is the simulation's quote.
func _show_quote() -> void:
	var asking: bool = not _snapshot.is_empty() and not bool(_snapshot["loan"]["active"])
	if not asking or session == null or int(_amount.value) < MIN_AMOUNT:
		_hide_quote()
		return
	var quoted: Dictionary = session.loan_quote(int(_amount.value))
	if bool(quoted["refused"]):
		_hide_quote()
		return
	_quote_rate.text = Strings.text(Strings.LOAN_QUOTE_RATE) % (float(quoted["rate"]) * PERCENT)
	_quote_interest.text = Strings.text(Strings.LOAN_QUOTE_INTEREST) % Strings.money(int(quoted["interest"]))
	_quote_term.text = Strings.text(Strings.LOAN_QUOTE_TERM) % int(quoted["term_installments"])
	_quote_surcharge.text = Strings.text(Strings.LOAN_QUOTE_SURCHARGE) % Strings.money(int(quoted["early_surcharge"]))
	var share: float = float(quoted["share_of_r"])
	if share < 0.0:
		_quote_share.text = Strings.text(Strings.LOAN_INSTALLMENT) % Strings.money(int(quoted["installment"]))
	else:
		_quote_share.text = Strings.text(Strings.LOAN_QUOTE_SHARE) % [Strings.money(int(quoted["installment"])), share * PERCENT]
	_quote_risk.text = Strings.text(Strings.LOAN_QUOTE_RISK) % int(quoted["arrears_penalty"])
	_set_quote_visible(true)


func _hide_quote() -> void:
	if _quote_rate == null:
		return
	_set_quote_visible(false)


func _set_quote_visible(on: bool) -> void:
	for label: Label in [_quote_rate, _quote_interest, _quote_term, _quote_surcharge, _quote_share, _quote_risk]:
		label.visible = on


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
