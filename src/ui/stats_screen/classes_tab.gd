class_name ClassesTab
extends ChartTab

# The classes tab of the statistics screen (issue #83, D-052): the city's satisfaction stacked by class over a
# range (StatsClasses), with the history's markers, so a policy change shows next to the layer it moved. The range
# and the cursor work like every chart tab (ChartTab).

var _plot: StackedChart
var _legend: HBoxContainer
var _markers: Label


func setup(game_session: GameSession, look: StatsPresentation) -> void:
	session = game_session
	presentation = look
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_range_buttons()
	_plot = StackedChart.new()
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
	_apply_range_texts()
	_hint.text = Strings.text(Strings.STATS_SCREEN_CLASSES_HINT)


func refresh() -> void:
	var range_entry: Dictionary = _range_entry()
	_chart = StatsClasses.build(session.simulation, range_entry["tier"], range_entry["span_seconds"])
	_show()


func _show() -> void:
	var strokes: Dictionary = _strokes()
	_plot.show_layers(strokes["lines"], strokes["colors"], strokes["dashes"], presentation.layout["line_width"],
		presentation.fill_alpha)
	_markers.text = " · ".join(_show_marks(_plot))
	_show_reading(StatsClasses.reading(_chart, cursor_index()))
	StatsScreen.show_legend(_legend, _chart["lines"], presentation)
