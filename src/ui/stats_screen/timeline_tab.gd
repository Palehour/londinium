class_name TimelineTab
extends ChartTab

# The history tab of the statistics screen (issue #83, D-052): one metric over a range, picked by buttons or with
# the D-pad or the arrows ↑/↓, with a marker on each bucket where something happened. The range and the cursor
# work like every chart tab (ChartTab). With the incidents on, the lessons of each district and the severity the cholera
# had there go under the chart (issue #87, D-120), read from the snapshot.

var _metric: int = 0
var _metric_buttons: Array[Button] = []
var _plot: Sparkline
var _legend: HBoxContainer
var _markers: Label
var _lessons: Label


func setup(game_session: GameSession, look: StatsPresentation) -> void:
	session = game_session
	presentation = look
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_metric_buttons = _choices(StatsTimeline.METRICS.size(), _pick_metric)
	_add_range_buttons()
	_plot = Sparkline.new()
	_plot.custom_minimum_size.y = look.layout["history_chart_height"]
	_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_plot)
	_legend = HBoxContainer.new()
	add_child(_legend)
	_reading = _wrapped_label()
	_markers = _wrapped_label()
	_lessons = _wrapped_label()
	_hint = _wrapped_label()
	apply_texts()


func apply_texts() -> void:
	for index: int in _metric_buttons.size():
		_metric_buttons[index].text = Strings.text(Strings.STATS_SCREEN_CARDS[StatsTimeline.METRICS[index]])
	_apply_range_texts()
	_hint.text = Strings.text(Strings.STATS_SCREEN_HISTORY_HINT)


func refresh() -> void:
	var range_entry: Dictionary = _range_entry()
	_chart = StatsTimeline.build(session.simulation, StatsTimeline.METRICS[_metric], range_entry["tier"],
		range_entry["span_seconds"])
	_metric_buttons[_metric].set_pressed_no_signal(true)
	_lessons.text = "\n".join(DistrictLessons.lines(session.get_snapshot()["incidents"], session.context.map.district_names))
	_lessons.visible = not _lessons.text.is_empty()
	_show()


func _handle_other(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down"):
		_pick_metric(posmod(_metric + (1 if event.is_action_pressed(&"ui_down") else -1), _metric_buttons.size()))


func _pick_metric(index: int) -> void:
	_metric = index
	refresh()


func _show() -> void:
	var strokes: Dictionary = _strokes()
	_plot.show_lines(strokes["lines"], strokes["colors"], strokes["dashes"], presentation.layout["line_width"])
	_markers.text = " · ".join(_show_marks(_plot))
	var index: int = cursor_index()
	_show_reading(StatsSummary.reading(_chart["id"], _chart["lines"], index) if index >= 0 else "")
	StatsScreen.show_legend(_legend, _chart["lines"], presentation)
