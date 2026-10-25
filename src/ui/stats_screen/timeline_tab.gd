class_name TimelineTab
extends VBoxContainer

# The history tab of the statistics screen (issue #83, D-052): one chart a screen, the metric and range picked by
# buttons, the D-pad or the arrows, and the triggers or +/-. The cursor walks the buckets and reads the one it is
# on, with what happened there; it follows the newest bucket until moved, and goes back to it on a new range.

const SECONDS_PER_MINUTE: int = 60
const NARROWER_KEYS: Array[Key] = [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]
const WIDER_KEYS: Array[Key] = [KEY_MINUS, KEY_KP_SUBTRACT]

var session: GameSession
var presentation: StatsPresentation
var _metric: int = 0
var _range: int = 0
# Bucket of the chapter the cursor is on; -1 follows the newest.
var _cursor: int = -1
# Triggers held past the half-way mark, so a held pull changes the range once.
var _held: Dictionary[StringName, bool] = {}
var _chart: Dictionary = {}
var _metric_buttons: Array[Button] = []
var _range_buttons: Array[Button] = []
var _plot: Sparkline
var _legend: HBoxContainer
var _reading: Label
var _markers: Label
var _hint: Label


func setup(game_session: GameSession, look: StatsPresentation) -> void:
	session = game_session
	presentation = look
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_metric_buttons = _choices(StatsTimeline.METRICS.size(), _pick_metric)
	_range_buttons = _choices(look.history_ranges.size(), _pick_range)
	_plot = Sparkline.new()
	_plot.custom_minimum_size.y = look.layout["history_chart_height"]
	_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_plot)
	_legend = HBoxContainer.new()
	add_child(_legend)
	_reading = _wrapped_label()
	_markers = _wrapped_label()
	_hint = _wrapped_label()
	apply_texts()


func apply_texts() -> void:
	for index: int in _metric_buttons.size():
		_metric_buttons[index].text = Strings.text(Strings.STATS_SCREEN_CARDS[StatsTimeline.METRICS[index]])
	for index: int in _range_buttons.size():
		_range_buttons[index].text = Strings.label(Strings.STATS_SCREEN_RANGES, presentation.history_ranges[index]["id"])
	_hint.text = Strings.text(Strings.STATS_SCREEN_HISTORY_HINT)


func refresh() -> void:
	var range_entry: Dictionary = presentation.history_ranges[_range]
	_chart = StatsTimeline.build(session.simulation, StatsTimeline.METRICS[_metric], range_entry["tier"],
		range_entry["span_seconds"])
	_metric_buttons[_metric].set_pressed_no_signal(true)
	_range_buttons[_range].set_pressed_no_signal(true)
	_show()


# The screen's events while this tab shows; it uses the ones it knows.
func handle(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left", true) or event.is_action_pressed(&"ui_right", true):
		_move_cursor(1 if event.is_action_pressed(&"ui_right", true) else -1)
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down"):
		_pick_metric(posmod(_metric + (1 if event.is_action_pressed(&"ui_down") else -1), _metric_buttons.size()))
	elif _pulled(event, &"map_zoom_in") or _is_key(event, NARROWER_KEYS):
		_pick_range(maxi(0, _range - 1))
	elif _pulled(event, &"map_zoom_out") or _is_key(event, WIDER_KEYS):
		_pick_range(mini(_range_buttons.size() - 1, _range + 1))


# The bucket the cursor is on, as an index in the chart's lines; -1 while there is none.
func cursor_index() -> int:
	var count: int = _bucket_count()
	if count == 0:
		return -1
	if _cursor < 0:
		return count - 1
	return clampi(_cursor - int(_chart["first_bucket"]), 0, count - 1)


func _pick_metric(index: int) -> void:
	_metric = index
	refresh()


func _pick_range(index: int) -> void:
	if index != _range:
		_cursor = -1
	_range = index
	refresh()


func _move_cursor(step: int) -> void:
	var count: int = _bucket_count()
	if count == 0:
		return
	var index: int = clampi(cursor_index() + step, 0, count - 1)
	# Back on the newest bucket it follows the new ones again.
	_cursor = -1 if index == count - 1 else int(_chart["first_bucket"]) + index
	_show()


func _show() -> void:
	var lines: Array[PackedFloat32Array] = []
	var colors: Array[Color] = []
	var dashes: PackedFloat32Array = []
	for line: int in _chart["lines"].size():
		lines.append(_chart["lines"][line]["values"])
		colors.append(presentation.stroke_color(line))
		dashes.append(presentation.stroke_dash(line))
	_plot.show_lines(lines, colors, dashes, presentation.layout["line_width"])
	var index: int = cursor_index()
	var marks: PackedInt32Array = []
	var here: PackedStringArray = []
	for marker: Dictionary in _chart["markers"]:
		marks.append(marker["bucket"])
		if marker["bucket"] == index:
			here.append(marker["text"])
	_plot.show_marks(marks, index, presentation.colors["marker"], presentation.colors["cursor"])
	_markers.text = " · ".join(here)
	var value: String = StatsSummary.reading(_chart["id"], _chart["lines"], index) if index >= 0 else ""
	_reading.text = Strings.text(Strings.STATS_SCREEN_HISTORY_READING) % [_time(index),
		value if not value.is_empty() else Strings.text(Strings.STATS_SCREEN_NO_DATA)]
	StatsScreen.show_legend(_legend, _chart["lines"], presentation)


# Game time at the end of the cursor's bucket, as minutes:seconds since the chapter began.
func _time(index: int) -> String:
	var second: int = (int(_chart["first_bucket"]) + index + 1) * int(_chart["bucket_seconds"])
	@warning_ignore("integer_division")
	return "%d:%02d" % [second / SECONDS_PER_MINUTE, second % SECONDS_PER_MINUTE]


func _bucket_count() -> int:
	if _chart.is_empty() or _chart["lines"].is_empty():
		return 0
	return (_chart["lines"][0]["values"] as PackedFloat32Array).size()


# A row of toggle buttons, one pressed at a time; a click picks its index.
func _choices(count: int, picked: Callable) -> Array[Button]:
	var row: HBoxContainer = HBoxContainer.new()
	add_child(row)
	var group: ButtonGroup = ButtonGroup.new()
	var buttons: Array[Button] = []
	for index: int in count:
		var button: Button = Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(picked.bind(index))
		row.add_child(button)
		buttons.append(button)
	return buttons


# A trigger sends motions all the while it is held: only the pull past the half-way mark counts, like a key press.
func _pulled(event: InputEvent, action: StringName) -> bool:
	if event is not InputEventJoypadMotion or not event.is_action(action):
		return false
	var down: bool = event.is_action_pressed(action, true)
	var pulled: bool = down and not _held.get(action, false)
	_held[action] = down
	return pulled


func _is_key(event: InputEvent, keys: Array[Key]) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode in keys


func _wrapped_label() -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label
