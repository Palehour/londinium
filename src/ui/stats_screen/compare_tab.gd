class_name CompareTab
extends ChartTab

# The compare tab of the statistics screen (issue #318, D-168; controls of #83): two moments of the chapter, A and B,
# and a table of what changed between them (StatsCompare). One chart at a time, as everywhere: ↑/↓ pick which card
# it draws, the D-pad or ←/→ walk its buckets, LT/RT or +/- change the range, and Y (or M) puts the next marker, A
# then B then A again, on the bucket the cursor is on. A marker is a second of the chapter, so it stays when the
# range changes and reads "—" while that range does not show it. By moments only: no series is kept per district.

const MARKER_KEYS: Array[Key] = [KEY_M]
const NO_MARKER: int = -1

var _card: int = 0
# Second of the chapter each marker is on, NO_MARKER while unset, and which one Y sets next (0 = A, 1 = B).
var _second_a: int = NO_MARKER
var _second_b: int = NO_MARKER
var _next: int = 0
var _cards: Array[Dictionary] = []
var _title: Label
var _plot: Sparkline
var _legend: HBoxContainer
var _table: GridContainer
var _markers: Label


func setup(game_session: GameSession, look: StatsPresentation) -> void:
	session = game_session
	presentation = look
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_range_buttons()
	_title = _wrapped_label()
	_plot = Sparkline.new()
	_plot.custom_minimum_size.y = look.layout["chart_height"]
	_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_plot)
	_legend = HBoxContainer.new()
	add_child(_legend)
	_reading = _wrapped_label()
	_table = GridContainer.new()
	_table.columns = 4
	add_child(_table)
	_markers = _wrapped_label()
	_hint = _wrapped_label()
	apply_texts()


func apply_texts() -> void:
	_apply_range_texts()
	_hint.text = Strings.text(Strings.STATS_SCREEN_COMPARE_HINT)


# A new visit starts with no moments chosen and the cursor on the newest bucket.
func reset() -> void:
	_second_a = NO_MARKER
	_second_b = NO_MARKER
	_next = 0
	_card = 0
	_cursor = -1


func marker_seconds() -> Array[int]:
	return [_second_a, _second_b]


func refresh() -> void:
	var range_entry: Dictionary = _range_entry()
	_cards = StatsSummary.build(session.simulation, range_entry["span_seconds"], range_entry["tier"])
	_chart = StatsTimeline.place(session.simulation, range_entry["tier"], range_entry["span_seconds"])
	# Every series of a level shares its buckets, so the population card counts them for all the cards.
	_chart["lines"] = _cards[StatsSummary.CARDS.find(&"population")]["lines"]
	_chart["markers"] = [] as Array[Dictionary]
	_show()


# Puts the next marker (A, then B) on the bucket the cursor is on; false when there is no bucket yet.
func mark() -> bool:
	if cursor_index() < 0:
		return false
	if _next == 0:
		_second_a = cursor_second()
	else:
		_second_b = cursor_second()
	_next = 1 - _next
	_show()
	return true


# The rows of the table as they are now, for the screen's tests.
func rows() -> Array[Dictionary]:
	return StatsCompare.rows(_cards, _index_of(_second_a), _index_of(_second_b))


func _handle_other(event: InputEvent) -> void:
	if event.is_action_pressed(&"map_repair") or _is_key(event, MARKER_KEYS):
		mark()
	elif event.is_action_pressed(&"ui_up", true) or event.is_action_pressed(&"ui_down", true):
		_card = clampi(_card + (1 if event.is_action_pressed(&"ui_down", true) else -1), 0, StatsCompare.CARDS.size() - 1)
		_show()


func _show() -> void:
	if _cards.is_empty():
		return
	var card: Dictionary = _cards[StatsSummary.CARDS.find(StatsCompare.CARDS[_card])]
	_title.text = Strings.text(Strings.STATS_SCREEN_CARDS[card["id"]])
	var strokes: Dictionary = _strokes_of(card["lines"])
	_plot.show_lines(strokes["lines"], strokes["colors"], strokes["dashes"], presentation.layout["line_width"])
	_plot.show_marks(_mark_buckets(), cursor_index(), presentation.colors["marker"], presentation.colors["cursor"])
	var cursor: int = cursor_index()
	_show_reading(StatsSummary.reading(card["id"], card["lines"], cursor) if cursor >= 0 else "")
	StatsScreen.show_legend(_legend, card["lines"], presentation)
	_show_table()


func _show_table() -> void:
	var index_a: int = _index_of(_second_a)
	var index_b: int = _index_of(_second_b)
	var data: Array[Dictionary] = StatsCompare.rows(_cards, index_a, index_b)
	for child: Node in _table.get_children():
		child.free()
	for heading: String in [Strings.text(Strings.STATS_SCREEN_COMPARE_METRIC), _moment_heading("A", _second_a, index_a),
			_moment_heading("B", _second_b, index_b), Strings.text(Strings.STATS_SCREEN_COMPARE_DIFF)]:
		# Same widths as the rows below, so each heading sits over its column.
		_cell(heading, _table.get_child_count() == 0)
	for row: Dictionary in data:
		_cell(row["label"], true)
		_cell(StatsCompare.format(row["card"], row["a"]), false)
		_cell(StatsCompare.format(row["card"], row["b"]), false)
		_cell(StatsCompare.format_diff(row["card"], row["diff"]), false)
	_markers.text = Strings.text(Strings.STATS_SCREEN_COMPARE_NEXT) % ("A" if _next == 0 else "B")


# "A · 1:40", or "A · —" when the marker is unset or the range does not show it.
func _moment_heading(letter: String, second: int, index: int) -> String:
	var when: String = _clock(second) if index >= 0 else Strings.text(Strings.STATS_SCREEN_NO_READING)
	return Strings.text(Strings.STATS_SCREEN_COMPARE_MOMENT) % [letter, when]


func _cell(text: String, first_column: bool) -> void:
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if first_column else Control.SIZE_SHRINK_BEGIN
	label.custom_minimum_size.x = 0.0 if first_column else presentation.layout["compare_column_width"]
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_table.add_child(label)


func _index_of(second: int) -> int:
	return StatsCompare.bucket_of(_chart, second, _bucket_count()) if not _chart.is_empty() else -1


# The buckets of both markers in this range, for the chart's rules.
func _mark_buckets() -> PackedInt32Array:
	var marks: PackedInt32Array = []
	for second: int in [_second_a, _second_b]:
		var index: int = _index_of(second)
		if index >= 0:
			marks.append(index)
	return marks


func _clock(second: int) -> String:
	@warning_ignore("integer_division")
	return "%d:%02d" % [second / SECONDS_PER_MINUTE, second % SECONDS_PER_MINUTE]
