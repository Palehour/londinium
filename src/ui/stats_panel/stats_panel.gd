class_name StatsPanel
extends PanelContainer

signal restart_requested

const PERCENT: float = 100.0
const CONDITIONS: Array[StringName] = [&"bankruptcy", &"hunger", &"depopulation"]

var session: GameSession
var clock: SimClock
var _speed: int = 1
var _syncing: bool = false
var _alert: Label
var _restart: Button
var _tax: SpinBox
var _wheat: CheckButton
var _accumulate: OptionButton
var _max_price: OptionButton
var _target: HSlider
var _target_label: Label
var _reserve: HSlider
var _reserve_label: Label
var _wheat_row: Label
# Option index -> price (0 = off / no limit), rebuilt when the market's price range changes.
var _accumulate_prices: Array[int] = []
var _max_prices: Array[int] = []
var _price_range: Vector2i = Vector2i(-1, -1)
var _dragging_target: bool = false
var _dragging_reserve: bool = false
var _pause: Button
var _speed_buttons: Dictionary[int, Button] = {}
var _bread: Label
var _economy: Label
var _buildings: Label
var _crises: Label


func setup(game_session: GameSession, game_clock: SimClock) -> void:
	session = game_session
	clock = game_clock
	# The panel owns every click and wheel event over it, so none reach the map.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Godot forwards unhandled wheel events to the parent by default, which would zoom the map.
	mouse_force_pass_scroll_events = false
	var root: VBoxContainer = VBoxContainer.new()
	add_child(root)
	root.add_child(_label(Strings.PANEL_TITLE))
	_alert = _label("")
	_alert.visible = false
	root.add_child(_alert)
	_restart = _button(Strings.RESTART, func() -> void: restart_requested.emit())
	_restart.visible = false
	root.add_child(_restart)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_build_controls(content)
	_bread = _label("")
	_economy = _label("")
	_buildings = _label("")
	_crises = _label("")
	for label: Label in [_bread, _economy, _buildings, _crises]:
		content.add_child(label)


func apply_style(background: Color, alert: Color, margin: float) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.set_content_margin_all(margin)
	add_theme_stylebox_override("panel", style)
	_alert.add_theme_color_override("font_color", alert)


func update_snapshot(snapshot: Dictionary) -> void:
	var economy: Dictionary = snapshot["economy"]
	var stats: Dictionary = snapshot["stats"]
	var defeat: Dictionary = snapshot["defeat"]
	var defeated: bool = not defeat["causes"].is_empty()
	var market: Dictionary = snapshot["market"]["wheat"]
	_update_controls(economy, defeated)
	_update_wheat_policy(market, defeated)
	_wheat_row.text = _wheat_text(market)
	_update_alert(defeat)
	_restart.visible = defeated
	_bread.text = _bread_text(economy, stats, snapshot["diagnostics"])
	_economy.text = _economy_text(economy, stats)
	_buildings.text = _buildings_text(snapshot["diagnostics"]["buildings"])
	_crises.text = _crises_text(defeat)


func _build_controls(content: VBoxContainer) -> void:
	var tax_row: HBoxContainer = HBoxContainer.new()
	var tax_label: Label = Label.new()
	tax_label.text = Strings.TAX_LABEL
	tax_row.add_child(tax_label)
	_tax = SpinBox.new()
	_tax.max_value = PERCENT
	_tax.value_changed.connect(_tax_changed)
	tax_row.add_child(_tax)
	content.add_child(tax_row)
	_wheat = CheckButton.new()
	_wheat.text = Strings.WHEAT_PURCHASES
	_wheat.focus_mode = Control.FOCUS_NONE
	_wheat.toggled.connect(_wheat_toggled)
	content.add_child(_wheat)
	_wheat_row = _label("")
	content.add_child(_wheat_row)
	_accumulate = _price_selector(content, Strings.ACCUMULATE_LABEL)
	_max_price = _price_selector(content, Strings.MAX_PRICE_LABEL)
	_target_label = _label("")
	content.add_child(_target_label)
	_target = HSlider.new()
	_target.step = 1.0
	# The wheel would change the value without a drag end, and the panel would put the old one back.
	_target.scrollable = false
	_target.focus_mode = Control.FOCUS_NONE
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.drag_started.connect(func() -> void: _dragging_target = true)
	_target.drag_ended.connect(_target_released)
	_target.value_changed.connect(func(value: float) -> void: _target_label.text = Strings.TARGET_LABEL % int(value))
	content.add_child(_target)
	_reserve_label = _label("")
	content.add_child(_reserve_label)
	_reserve = HSlider.new()
	_reserve.step = 1.0
	_reserve.scrollable = false
	_reserve.focus_mode = Control.FOCUS_NONE
	_reserve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reserve.drag_started.connect(func() -> void: _dragging_reserve = true)
	_reserve.drag_ended.connect(_reserve_released)
	_reserve.value_changed.connect(func(value: float) -> void: _reserve_label.text = Strings.RESERVE_LABEL % int(value))
	content.add_child(_reserve)
	var speed_row: HBoxContainer = HBoxContainer.new()
	_pause = _button(Strings.PAUSE, _toggle_pause)
	speed_row.add_child(_pause)
	for speed: int in Strings.SPEED_LABELS:
		var button: Button = _button(Strings.SPEED_LABELS[speed], _select_speed.bind(speed))
		button.toggle_mode = true
		_speed_buttons[speed] = button
		speed_row.add_child(button)
	content.add_child(speed_row)
	_update_clock_controls()


func _update_controls(economy: Dictionary, defeated: bool) -> void:
	_syncing = true
	# Never overwrite a value the player is still typing.
	if not _tax.get_line_edit().has_focus():
		_tax.value = roundf(float(economy.get("tax_rate", 0.0)) * PERCENT)
	_wheat.button_pressed = bool(economy["wheat_purchases_enabled"])
	_syncing = false
	_tax.editable = not defeated
	_wheat.disabled = defeated
	if clock.speed != 0:
		_speed = clock.speed
	_update_clock_controls()


func _price_selector(content: VBoxContainer, title: String) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_label(title))
	var selector: OptionButton = OptionButton.new()
	selector.focus_mode = Control.FOCUS_NONE
	selector.item_selected.connect(func(_index: int) -> void: _submit_policy())
	row.add_child(selector)
	content.add_child(row)
	return selector


# The player picks among the market's own prices: a price above the top one could never be paid.
func _rebuild_price_options(market: Dictionary) -> void:
	var range_now: Vector2i = Vector2i(market["min_price"], market["top_price"])
	if range_now == _price_range:
		return
	_price_range = range_now
	_accumulate.clear()
	_max_price.clear()
	_accumulate_prices = [WheatPolicy.OFF]
	_max_prices = []
	_accumulate.add_item(Strings.ACCUMULATE_OFF)
	# Accumulating at the market's top price is a valid policy (always stockpile), so it is listed;
	# a maximum at the top price never stops anything, so "no limit" stands for it.
	for price: int in range(range_now.x, range_now.y + 1):
		_accumulate_prices.append(price)
		_accumulate.add_item(Strings.money(price))
		if price < range_now.y:
			_max_prices.append(price)
			_max_price.add_item(Strings.money(price))
	_max_prices.append(WheatPolicy.NO_LIMIT)
	_max_price.add_item(Strings.NO_LIMIT)


func _update_wheat_policy(market: Dictionary, defeated: bool) -> void:
	_rebuild_price_options(market)
	_syncing = true
	# An unlisted maximum is the market's top price: nothing can exceed it, so it reads as no limit.
	_accumulate.select(maxi(0, _accumulate_prices.find(int(market["accumulate_price"]))))
	var max_index: int = _max_prices.find(int(market["max_price"]))
	_max_price.select(max_index if max_index >= 0 else _max_prices.size() - 1)
	_target.max_value = market["capacity"]
	if not _dragging_target:
		_target.value = market["target_stock"]
		_target_label.text = Strings.TARGET_LABEL % int(market["target_stock"])
	_syncing = false
	for control: Control in [_accumulate, _max_price]:
		(control as OptionButton).disabled = defeated
	_reserve.max_value = market["max_reserve_minutes"]
	if not _dragging_reserve:
		_reserve.value = market["reserve_minutes"]
		_reserve_label.text = Strings.RESERVE_LABEL % int(market["reserve_minutes"])
	_reserve.editable = not defeated
	_target.editable = not defeated


func _wheat_text(market: Dictionary) -> String:
	var price: int = market["price"]
	var previous: int = market["previous_price"]
	var trend: String = Strings.TREND_UP if price > previous else Strings.TREND_DOWN if price < previous else Strings.TREND_FLAT
	var covered: String = Strings.MINUTES_COVERED % market["minutes_covered"] if market["minutes_covered"] >= 0.0 \
		else Strings.NO_MILL_COVERAGE
	var text: String = Strings.WHEAT_ROW % [market["stock"], market["capacity"], Strings.money(price), trend, covered]
	return text + "\n" + Strings.WHEAT_BLOCKED_NOTE if market["blocked_by_price"] else text


func _submit_policy() -> void:
	if _syncing:
		return
	session.submit_command(SetWheatPolicyCommand.new(_accumulate_prices[_accumulate.selected],
		_max_prices[_max_price.selected], int(_target.value), int(_reserve.value)))


func _reserve_released(_changed: bool) -> void:
	_dragging_reserve = false
	_submit_policy()


func _target_released(_changed: bool) -> void:
	_dragging_target = false
	_submit_policy()


func _update_clock_controls() -> void:
	_pause.text = Strings.RESUME if clock.speed == 0 else Strings.PAUSE
	for speed: int in _speed_buttons:
		_speed_buttons[speed].set_pressed_no_signal(speed == _speed)


func _update_alert(defeat: Dictionary) -> void:
	var names: Array[String] = []
	if not defeat["causes"].is_empty():
		for cause: StringName in defeat["causes"]:
			names.append(Strings.CONDITION_LABELS[cause])
		_alert.text = Strings.ALERT_DEFEAT % ", ".join(names)
	else:
		for key: StringName in CONDITIONS:
			if defeat[key]["status"] == &"warning":
				names.append(Strings.CONDITION_LABELS[key] + _timer_text(defeat[key]))
		_alert.text = Strings.ALERT_WARNING % ", ".join(names) if not names.is_empty() else ""
	_alert.visible = not _alert.text.is_empty()


func _bread_text(economy: Dictionary, stats: Dictionary, diagnostics: Dictionary) -> String:
	var lines: Array[String] = [Strings.BREAD_RATE % [stats["bread_produced_per_minute"],
		stats["bread_consumed_per_minute"], stats["bread_demand_per_minute"]]]
	var stocks: Dictionary = economy["stocks"]
	lines.append(Strings.STOCKS % [stocks.get(&"wheat", 0), stocks.get(&"flour", 0), stocks.get(&"bread", 0)])
	if not diagnostics["bread_short"]:
		lines.append(Strings.BREAD_OK)
		return "\n".join(lines)
	lines.append(Strings.BREAD_SHORT)
	for cause: Dictionary in diagnostics["bread_causes"]:
		var label: String = Strings.building_label(String(cause["definition_id"]))
		# Chain-wide causes have no single building to blame.
		if label.is_empty():
			lines.append(Strings.BREAD_CHAIN_CAUSE % Strings.reason(cause["reason"]))
		else:
			lines.append(Strings.BREAD_CAUSE % [label, Strings.reason(cause["reason"])])
	return "\n".join(lines)


func _economy_text(economy: Dictionary, stats: Dictionary) -> String:
	var breakdown: Dictionary = economy["satisfaction_breakdown"]
	var lines: Array[String] = [
		Strings.POPULATION % [economy["population"], economy["employed"], economy["unemployed"]],
		Strings.SATISFACTION % [economy["satisfaction"], breakdown.get("bread", 0.0),
			breakdown.get("tax", 0.0), breakdown.get("overcrowding", 0.0)],
		Strings.TREASURY % Strings.money(economy["money"]),
		Strings.OPERATING_BALANCE % _money(stats["operating_balance_per_minute"]),
		Strings.BALANCE_BREAKDOWN % [_money(stats["taxes_per_minute"]), _money(stats["wages_per_minute"]),
			_money(stats["upkeep_per_minute"]), _money(stats["wheat_spent_per_minute"])],
		Strings.CONSTRUCTION % _money(stats["construction_spent_per_minute"]),
		Strings.WHEAT_PRICE % Strings.money(economy.get("wheat_price", 0)),
	]
	if not stats["complete"]:
		lines.append(Strings.WINDOW_PARTIAL % [stats["window_seconds"], stats["window_size"]])
	return "\n".join(lines)


func _buildings_text(buildings: Array) -> String:
	var lines: Array[String] = [Strings.BUILDINGS]
	for building: Dictionary in buildings:
		lines.append(Strings.BUILDING_STATUS % [Strings.building_label(String(building["definition_id"])),
			building["cell"][0], building["cell"][1], building["workers"], building["jobs"], Strings.reason(building["reason"])])
	if buildings.is_empty():
		lines.append(Strings.NO_BUILDINGS)
	return "\n".join(lines)


func _crises_text(defeat: Dictionary) -> String:
	var lines: Array[String] = [Strings.CRISES]
	if defeat["grace_active"]:
		lines.append(Strings.GRACE % defeat["grace_remaining_seconds"])
	var bankruptcy: Dictionary = defeat[&"bankruptcy"]
	var hunger: Dictionary = defeat[&"hunger"]
	var depopulation: Dictionary = defeat[&"depopulation"]
	var metrics: Dictionary[StringName, String] = {
		&"bankruptcy": Strings.METRIC_BANKRUPTCY % [Strings.money(bankruptcy["money"]), Strings.money(bankruptcy["threshold"])],
		&"hunger": Strings.METRIC_HUNGER % [hunger["coverage"] * PERCENT, hunger["threshold"] * PERCENT],
		&"depopulation": Strings.METRIC_DEPOPULATION % [depopulation["population"], depopulation["peak"]],
	}
	for key: StringName in CONDITIONS:
		var condition: Dictionary = defeat[key]
		lines.append(Strings.CONDITION % [Strings.CONDITION_LABELS[key], Strings.STATUS_LABELS[condition["status"]],
			metrics[key]] + _timer_text(condition))
	return "\n".join(lines)


func _timer_text(condition: Dictionary) -> String:
	if not condition["timer_running"]:
		return ""
	return Strings.TIMER % [condition["elapsed_seconds"], condition["duration_seconds"], condition["remaining_seconds"]]


func _tax_changed(value: float) -> void:
	if not _syncing:
		session.submit_command(SetTaxCommand.new(value / PERCENT))


func _wheat_toggled(enabled: bool) -> void:
	if not _syncing:
		session.submit_command(SetWheatPurchasesCommand.new(enabled))


func _toggle_pause() -> void:
	clock.speed = _speed if clock.speed == 0 else 0
	_update_clock_controls()


# Choosing a speed while paused only arms it; the clock resumes at that speed.
func _select_speed(speed: int) -> void:
	_speed = speed
	if clock.speed != 0:
		clock.speed = speed
	_update_clock_controls()


func _money(per_minute: float) -> String:
	return Strings.money(roundi(per_minute))


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# Buttons never keep focus, so map shortcuts (1–5, WASD) keep working after a click.
func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button
