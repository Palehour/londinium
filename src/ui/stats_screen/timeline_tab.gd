class_name TimelineTab
extends ChartTab

# The history tab (issue #316, D-168): one series at a time, in the order of data/ui/stats.json. LB/RB change the
# series; the D-pad walks the buckets. The range buttons and the district lessons stay. Fear and debt have no
# series, so the chart says there is no data instead of inventing a line.

var _series: int = 0
var _name: Label
var _plot: Sparkline
var _legend: HBoxContainer
var _markers: Label
var _lessons: Label


func setup(game_session: GameSession, look: StatsPresentation) -> void:
	session = game_session
	presentation = look
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name = _wrapped_label()
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
	_apply_range_texts()
	_hint.text = Strings.text(Strings.STATS_SCREEN_HISTORY_HINT)
	if not _chart.is_empty():
		_name.text = _chart["label"]


# Wraps. The cursor stays on its bucket: the series share the chapter's time.
func change_series(step: int) -> void:
	var count: int = presentation.history_series.size()
	if count == 0:
		return
	_series = posmod(_series + step, count)
	refresh()


func refresh() -> void:
	var count: int = presentation.history_series.size()
	if count == 0:
		return
	_series = posmod(_series, count)
	var range_entry: Dictionary = _range_entry()
	var series_id: StringName = presentation.history_series[_series]
	_chart = StatsTimeline.chart(session.simulation, series_id, range_entry["tier"], range_entry["span_seconds"],
		presentation.history_markers)
	_name.text = _chart["label"]
	_lessons.text = "\n".join(DistrictLessons.lines(session.get_snapshot()["incidents"], session.context.map.district_names))
	_lessons.visible = not _lessons.text.is_empty()
	_show()


func _show() -> void:
	var width: float = presentation.layout["line_width"]
	if _chart["lines"].is_empty():
		_plot.show_lines([] as Array[PackedFloat32Array], [] as Array[Color], PackedFloat32Array(), width)
		_markers.text = ""
		_reading.text = Strings.text(Strings.STATS_SCREEN_NO_DATA)
		StatsScreen.show_legend(_legend, [] as Array[Dictionary], presentation)
		return
	var values: PackedFloat32Array = _chart["lines"][0]["values"]
	var lines: Array[PackedFloat32Array] = [values]
	var colors: Array[Color] = [presentation.stroke_color(_series)]
	_plot.show_lines(lines, colors, PackedFloat32Array([presentation.stroke_dash(_series)]), width)
	_markers.text = " · ".join(_show_marks(_plot))
	var index: int = cursor_index()
	var value: String = ""
	if index >= 0 and index < values.size():
		value = StatsTimeline.format_value(values[index], _chart["unit"])
	_show_reading(value)
	StatsScreen.show_legend(_legend, _chart["lines"], presentation)
