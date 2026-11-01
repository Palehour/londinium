extends GutTest

# Issue #281: the stats panel asks for a loan up to the snapshot cap, then shows the installment, the balance and the
# early-payoff cost the simulation already computed. Nothing here is a balance number: every figure is read back from
# snapshot()["loan"] after the tick that applied the command.

const CAP_KEY: StringName = &"ui.loan.cap"
const REQUEST_KEY: StringName = &"ui.loan.request"
const MAXIMUM_KEY: StringName = &"ui.loan.maximum"
const INSTALLMENT_KEY: StringName = &"ui.loan.installment"
const BALANCE_KEY: StringName = &"ui.loan.balance"
const CANCEL_KEY: StringName = &"ui.loan.cancel"


var _catalog: DataCatalog
var _session: GameSession
var _clock: SimClock
var _panel: StatsPanel


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_session = _new_session([])
	_clock = SimClock.new()
	_clock.simulation = _session.simulation
	add_child_autofree(_clock)
	_clock.set_process(false)
	_panel = _new_panel(_session)


func after_each() -> void:
	Strings.use_default_locale()


func _new_panel(session: GameSession) -> StatsPanel:
	var panel: StatsPanel = StatsPanel.new()
	panel.setup(session, _clock)
	add_child_autofree(panel)
	return panel


func _new_session(modifiers: Array[Modifier]) -> GameSession:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return GameSession.new(_catalog, Params.new(_catalog, role))


func _tick() -> void:
	_session.simulation.tick()
	_panel.update_snapshot(_session.get_snapshot())


func _has_loan_section() -> bool:
	var loan: Node = _loan()
	assert_not_null(loan, "The stats panel has a loan section")
	return loan != null


func _loan() -> Node:
	return _panel.find_child("LoanPanel", true, false)


func _control(node_name: String) -> Control:
	var loan: Node = _loan()
	assert_not_null(loan, "The stats panel has a loan section")
	if loan == null:
		return null
	var control: Control = loan.find_child(node_name, true, false) as Control
	assert_not_null(control, "Loan panel is missing %s" % node_name)
	return control


func _amount() -> SpinBox:
	return _control("Amount") as SpinBox


func _request() -> Button:
	return _control("Request") as Button


func _maximum() -> Button:
	return _control("Maximum") as Button


func _cancel() -> Button:
	return _control("Cancel") as Button


func _label(node_name: String) -> Label:
	return _control(node_name) as Label


# Criterion 1: asking, then reading the installment and the balance the snapshot just published.
func test_requesting_up_to_the_cap_shows_the_snapshot_installment_and_balance() -> void:
	if not _has_loan_section():
		return
	_tick()
	var loan: Dictionary = _session.get_snapshot()["loan"]
	var cap: int = int(loan["cap"])
	assert_gt(cap, 0, "The strip starts with taxes, so there is a cap to ask up to")
	assert_false(_cancel().visible, "Nothing to cancel yet")
	assert_eq(_label("Cap").text, Strings.text(CAP_KEY) % Strings.money(cap))
	assert_eq(_amount().max_value, float(cap))
	assert_eq(_amount().step, 1.0, "A penny, the simulation's unit, not a new step")
	_amount().value = 1.0
	_maximum().pressed.emit()
	assert_eq(_amount().value, float(cap), "Maximum fills the cap and does not ask")
	assert_false(loan["active"])
	_request().pressed.emit()
	_tick()
	loan = _session.get_snapshot()["loan"]
	assert_true(loan["active"])
	assert_eq(int(loan["principal"]), cap)
	assert_eq(_label("Installment").text, Strings.text(INSTALLMENT_KEY) % Strings.money(int(loan["next_installment"])))
	assert_eq(_label("Balance").text, Strings.text(BALANCE_KEY) % Strings.money(int(loan["balance"])))
	assert_false(_request().visible, "A second ask is not a second control")
	assert_eq(_label("Reason").text, Strings.reason(&"loan_active"))


# Criterion 1: cancelling charges the payoff cost the panel was already showing, then the loan is gone.
func test_early_cancel_charges_the_snapshot_payoff_cost() -> void:
	if not _has_loan_section():
		return
	_tick()
	assert_gt(int(_session.get_snapshot()["loan"]["cap"]), 0)
	_amount().value = 1.0
	_request().pressed.emit()
	_tick()
	var loan: Dictionary = _session.get_snapshot()["loan"]
	var cost: int = int(loan["payoff_cost"])
	assert_gt(cost, 0)
	assert_eq(_cancel().text, Strings.text(CANCEL_KEY) % Strings.money(cost))
	assert_false(_cancel().disabled, "A penny's payoff fits the starting treasury")
	_cancel().pressed.emit()
	_tick()
	loan = _session.get_snapshot()["loan"]
	assert_false(loan["active"])
	assert_eq(int(loan["paid_tick"]), cost, "The tick charged the cost the panel showed, not a hardcoded surcharge")
	assert_false(_cancel().visible)


# Criterion 2: the amount cannot pass the cap, and a blocked ask says why, from the snapshot.
func test_the_panel_refuses_another_loan_and_says_why() -> void:
	if not _has_loan_section():
		return
	_tick()
	var cap: int = int(_session.get_snapshot()["loan"]["cap"])
	assert_gt(cap, 0)
	_amount().value = float(cap) + 1000.0
	assert_eq(_amount().value, float(cap), "The control stops at the cap")
	_amount().value = float(cap)
	_request().pressed.emit()
	_tick()
	assert_true(_session.get_snapshot()["loan"]["active"])
	assert_eq(_label("Reason").text, Strings.reason(&"loan_active"))
	assert_false(_request().visible)
	# A fresh game with the tax cut to 0: the cap is 0 and that is why nothing can be asked.
	var bare: StatsPanel = _panel_after_tax_cut()
	var bare_loan: Node = bare.find_child("LoanPanel", true, false)
	assert_not_null(bare_loan)
	if bare_loan == null:
		return
	var bare_cap: Label = bare_loan.find_child("Cap", true, false) as Label
	var bare_request: Button = bare_loan.find_child("Request", true, false) as Button
	var bare_reason: Label = bare_loan.find_child("Reason", true, false) as Label
	assert_eq(bare_cap.text, Strings.text(CAP_KEY) % Strings.money(0))
	assert_true(bare_request.disabled)
	assert_eq(bare_reason.text, Strings.reason(&"loan_over_cap"))
	_assert_unsanctioned()


func _panel_after_tax_cut() -> StatsPanel:
	var session: GameSession = _new_session([])
	session.submit_command(SetTaxCommand.new(0.0))
	session.simulation.tick()
	var panel: StatsPanel = _new_panel(session)
	panel.update_snapshot(session.get_snapshot())
	assert_eq(int(session.get_snapshot()["loan"]["cap"]), 0)
	return panel


func _assert_unsanctioned() -> void:
	var session: GameSession = _new_session([Modifier.new(&"factions.legitimacy_start", &"set", 20.0)])
	session.simulation.tick()
	var snapshot: Dictionary = session.get_snapshot()
	assert_gt(int(snapshot["loan"]["cap"]), 0, "Refused by the Board, not by an empty cap")
	assert_eq(snapshot["loan"]["rate"], LoanSystem.REFUSED)
	var panel: StatsPanel = _new_panel(session)
	panel.update_snapshot(snapshot)
	var loan: Node = panel.find_child("LoanPanel", true, false)
	assert_not_null(loan)
	if loan == null:
		return
	var request: Button = loan.find_child("Request", true, false) as Button
	var reason: Label = loan.find_child("Reason", true, false) as Label
	assert_true(request.disabled)
	assert_eq(reason.text, Strings.reason(&"loan_not_sanctioned"))
	assert_false(snapshot["loan"]["active"])


# Criterion 3: d-pad reaches the ask, the maximum and the amount, at the Steam Deck size, in both languages.
func test_loan_controls_are_reachable_at_1280x800() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	var panel: StatsPanel = view.get("_stats_panel") as StatsPanel
	var session: GameSession = view.get("session") as GameSession
	session.simulation.tick()
	session.publish_tick()
	await get_tree().process_frame
	panel.call("enter_focus")
	var start: Control = viewport.gui_get_focus_owner()
	assert_not_null(start)
	var reached: Array[Control] = _reachable(start)
	var loan: Node = panel.find_child("LoanPanel", true, false)
	assert_not_null(loan, "The stats panel has a loan section")
	if loan == null:
		return
	var amount: SpinBox = loan.find_child("Amount", true, false) as SpinBox
	var request: Button = loan.find_child("Request", true, false) as Button
	var maximum: Button = loan.find_child("Maximum", true, false) as Button
	assert_true(amount.get_line_edit() in reached, "The d-pad reaches the amount")
	assert_true(request in reached, "The d-pad reaches Pedir")
	assert_true(maximum in reached, "The d-pad reaches Máximo")
	assert_eq(viewport.gui_get_focus_owner(), panel.get("_locale_es"), "The loan section does not steal the first focus")
	var cap: float = amount.max_value
	assert_gt(cap, amount.value, "There is room to step a penny under the cap")
	var before: float = amount.value
	amount.get_line_edit().grab_focus()
	_pad(viewport, JOY_BUTTON_DPAD_RIGHT)
	assert_eq(amount.value, before + 1.0, "Right steps a penny instead of leaving the field")
	assert_lte(amount.value, cap, "The d-pad does not walk past the cap")
	assert_eq(request.text, Strings.text(REQUEST_KEY))
	assert_eq(maximum.text, Strings.text(MAXIMUM_KEY))
	Strings.set_locale("en")
	await get_tree().process_frame
	assert_true(request.visible, "English keeps the same button, it does not hide it behind another")
	assert_true(maximum.visible)
	assert_eq(request.text, Strings.text(REQUEST_KEY))
	assert_ne(request.text, String(REQUEST_KEY), "The label is translated, not the raw key")
	assert_true(request in _reachable(viewport.gui_get_focus_owner()), "The d-pad still reaches Request")


# Criterion 3: loan text is at least 16 px and the block fits the panel in both languages.
func test_loan_text_is_at_least_16px_and_fits_both_languages() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	assert_true(look.errors.is_empty(), str(look.errors))
	var font_size: int = int(look.layout["font_size"])
	assert_gte(font_size, 16, "data/ui/stats.json is the Steam Deck size")
	var ids: Array[StringName] = []
	ids.assign(_catalog.buildings.keys())
	var presentation: MapPresentation = MapPresentation.new()
	presentation.load_data(ids)
	assert_true(presentation.errors.is_empty(), str(presentation.errors))
	var room: float = presentation.layout["panel_width"] - 2.0 * presentation.layout["panel_margin"]
	_tick()
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		_panel.update_snapshot(_session.get_snapshot())
		await get_tree().process_frame
		var loan: Control = _loan() as Control
		assert_not_null(loan, "The stats panel has a loan section")
		if loan == null:
			return
		for node: Node in loan.find_children("*", "Label", true, false) + loan.find_children("*", "Button", true, false):
			var control: Control = node as Control
			var line: String = str(control.get("text"))
			if not control.visible or line.is_empty():
				continue
			assert_gte(control.get_theme_font_size(&"font_size"), 16, "%s (%s)" % [control.name, locale])
			assert_eq(control.get_theme_font_size(&"font_size"), font_size, "Size comes from data/ui/stats.json")
			assert_false(line.begins_with("ui."), "%s shows a raw key (%s)" % [control.name, locale])
		assert_lte(loan.get_combined_minimum_size().x, room, "Fits the panel (%s)" % locale)


func _reachable(start: Control) -> Array[Control]:
	var seen: Array[Control] = [start]
	var index: int = 0
	while index < seen.size():
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var next: Control = seen[index].find_valid_focus_neighbor(side)
			if next != null and next not in seen:
				seen.append(next)
		index += 1
	return seen


func _pad(viewport: SubViewport, button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	viewport.push_input(event)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	viewport.push_input(event)
