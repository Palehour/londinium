class_name ChartTab
extends VBoxContainer

# A tab of the statistics screen with one large chart over a range of the chapter (issue #83, D-052): the history
# and the classes. The range is picked by buttons, the triggers or +/-; the cursor walks the buckets with the D-pad
# or the arrows and reads the one it is on. It follows the newest bucket until moved, and goes back to it on a new
# range. A tab builds its chart in refresh() and draws it in _show().

const SECONDS_PER_MINUTE: int = 60
const NARROWER_KEYS: Array[Key] = [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]
const WIDER_KEYS: Array[Key] = [KEY_MINUS, KEY_KP_SUBTRACT]

var session: GameSession
var presentation: StatsPresentation
var _range: int = 0
# Bucket of the chapter the cursor is on; -1 follows the newest.
var _cursor: int = -1
# Triggers held past the half-way mark, so a held pull changes the range once.
var _held: Dictionary[StringName, bool] = {}
# Has "lines", "first_bucket", "bucket_seconds" and "markers" (StatsTimeline.place).
var _chart: Dictionary = {}
var _range_buttons: Array[Button] = []
var _reading: Label
var _hint: Label


func refresh() -> void:
	pass


# The screen's events while this tab shows; it uses the ones it knows.
func handle(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left", true) or event.is_action_pressed(&"ui_right", true):
		_move_cursor(1 if event.is_action_pressed(&"ui_right", true) else -1)
	elif _pulled(event, &"map_zoom_in") or _is_key(event, NARROWER_KEYS):
		_pick_range(maxi(0, _range - 1))
	elif _pulled(event, &"map_zoom_out") or _is_key(event, WIDER_KEYS):
		_pick_range(mini(_range_buttons.size() - 1, _range + 1))
	else:
		_handle_other(event)


# The bucket the cursor is on, as an index in the chart's lines; -1 while there is none.
func cursor_index() -> int:
	var count: int = _bucket_count()
	if count == 0:
		return -1
	if _cursor < 0:
		return count - 1
	return clampi(_cursor - int(_chart["first_bucket"]), 0, count - 1)


func _show() -> void:
	pass


func _handle_other(_event: InputEvent) -> void:
	pass


func _add_range_buttons() -> void:
	_range_buttons = _choices(presentation.history_ranges.size(), _pick_range)


func _apply_range_texts() -> void:
	for index: int in _range_buttons.size():
		_range_buttons[index].text = Strings.label(Strings.STATS_SCREEN_RANGES, presentation.history_ranges[index]["id"])


func _range_entry() -> Dictionary:
	_range_buttons[_range].set_pressed_no_signal(true)
	return presentation.history_ranges[_range]


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


# Marks the chart's markers and its cursor on a plot; returns what the markers on the cursor's bucket say.
func _show_marks(plot: Sparkline) -> PackedStringArray:
	var index: int = cursor_index()
	var marks: PackedInt32Array = []
	var here: PackedStringArray = []
	for marker: Dictionary in _chart["markers"]:
		marks.append(marker["bucket"])
		if marker["bucket"] == index:
			here.append(marker["text"])
	plot.show_marks(marks, index, presentation.colors["marker"], presentation.colors["cursor"])
	return here


# The reading line under the chart: the cursor's time and what the tab reads there.
func _show_reading(value: String) -> void:
	_reading.text = Strings.text(Strings.STATS_SCREEN_HISTORY_READING) % [_time(cursor_index()),
		value if not value.is_empty() else Strings.text(Strings.STATS_SCREEN_NO_DATA)]


# Game time at the end of the cursor's bucket, as minutes:seconds since the chapter began.
func _time(index: int) -> String:
	var second: int = (int(_chart["first_bucket"]) + index + 1) * int(_chart["bucket_seconds"])
	@warning_ignore("integer_division")
	return "%d:%02d" % [second / SECONDS_PER_MINUTE, second % SECONDS_PER_MINUTE]


func _bucket_count() -> int:
	if _chart.is_empty() or _chart["lines"].is_empty():
		return 0
	return (_chart["lines"][0]["values"] as PackedFloat32Array).size()


# Strokes of a chart's lines, in order: {"lines", "colors", "dashes"} for Sparkline.show_lines().
func _strokes() -> Dictionary:
	var lines: Array[PackedFloat32Array] = []
	var colors: Array[Color] = []
	var dashes: PackedFloat32Array = []
	for line: int in _chart["lines"].size():
		lines.append(_chart["lines"][line]["values"])
		colors.append(presentation.stroke_color(line))
		dashes.append(presentation.stroke_dash(line))
	return {"lines": lines, "colors": colors, "dashes": dashes}


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
