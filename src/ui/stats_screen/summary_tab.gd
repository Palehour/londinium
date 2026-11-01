class_name SummaryTab
extends ChartTab

# The summary tab of the statistics screen (issue #83, D-052; controls D-170): the six cards of StatsSummary, each
# with a small chart and a one-line reading. One cursor is shared by every card: the D-pad or the arrows ←/→ walk
# the buckets and every card reads the one the cursor is on, so the series compare bucket by bucket. The triggers
# or +/- change the window among the history ranges of data/ui/stats.json. The range and the cursor work like every
# chart tab (ChartTab): the cursor starts on the newest bucket, goes back to it on a new window, and stops at the
# edges. Fear and debt have no series yet (#323): their cards say there is no data and read "—".

# Per card, in StatsSummary.CARDS order: its title, its no-data line, chart, reading and legend row.
var titles: Array[Label] = []
var values: Array[Label] = []
var charts: Array[Sparkline] = []
var readings: Array[Label] = []
var legends: Array[HBoxContainer] = []
# StatsSummary cards over the window shown.
var _cards: Array[Dictionary] = []


func setup(game_session: GameSession, look: StatsPresentation) -> void:
	session = game_session
	presentation = look
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_range_buttons()
	_range = _starting_range()
	var grid: GridContainer = GridContainer.new()
	grid.columns = int(look.layout["card_columns"])
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(grid)
	for id: StringName in StatsSummary.CARDS:
		grid.add_child(_card())
	_reading = _wrapped_label()
	_hint = _wrapped_label()
	apply_texts()


func apply_texts() -> void:
	_apply_range_texts()
	_hint.text = Strings.text(Strings.STATS_SCREEN_SUMMARY_HINT)
	for index: int in StatsSummary.CARDS.size():
		titles[index].text = Strings.text(Strings.STATS_SCREEN_CARDS[StatsSummary.CARDS[index]])
		values[index].text = Strings.text(Strings.STATS_SCREEN_NO_DATA)


# Back on the newest bucket, as when the summary opens.
func reset_cursor() -> void:
	_cursor = -1


func refresh() -> void:
	var range_entry: Dictionary = _range_entry()
	_cards = StatsSummary.build(session.simulation, range_entry["span_seconds"], range_entry["tier"])
	_chart = StatsTimeline.place(session.simulation, range_entry["tier"], range_entry["span_seconds"])
	# Every series of a level shares its buckets, so the population card counts them for all six.
	_chart["lines"] = _cards[StatsSummary.CARDS.find(&"population")]["lines"]
	_chart["markers"] = [] as Array[Dictionary]
	_show()


func _show() -> void:
	var cursor: int = cursor_index()
	for index: int in _cards.size():
		var card: Dictionary = _cards[index]
		var strokes: Dictionary = _strokes_of(card["lines"])
		charts[index].show_lines(strokes["lines"], strokes["colors"], strokes["dashes"], presentation.layout["line_width"])
		_show_marks(charts[index])
		var no_data: bool = card["lines"].is_empty()
		charts[index].visible = not no_data
		values[index].visible = no_data
		var text: String = StatsSummary.reading(card["id"], card["lines"], cursor) if cursor >= 0 else ""
		readings[index].text = text if not text.is_empty() else Strings.text(Strings.STATS_SCREEN_NO_READING)
		StatsScreen.show_legend(legends[index], card["lines"], presentation)
	_reading.text = Strings.text(Strings.STATS_SCREEN_SUMMARY_CURSOR) % _time(cursor) if cursor >= 0 \
		else Strings.text(Strings.STATS_SCREEN_NO_DATA)


# The window the summary opens on: the range of the medium level as long as summary.span_seconds, else the first.
func _starting_range() -> int:
	for index: int in presentation.history_ranges.size():
		var entry: Dictionary = presentation.history_ranges[index]
		if entry["tier"] == StatsHistory.TIER_MEDIUM and entry["span_seconds"] == presentation.summary_span_seconds:
			return index
	return 0


func _card() -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = presentation.colors["card"]
	style.set_content_margin_all(presentation.layout["margin"])
	card.add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	card.add_child(column)
	titles.append(Label.new())
	values.append(Label.new())
	var chart: Sparkline = Sparkline.new()
	chart.custom_minimum_size.y = presentation.layout["chart_height"]
	charts.append(chart)
	readings.append(_one_line_label())
	legends.append(HBoxContainer.new())
	for part: Control in [titles[-1], values[-1], chart, readings[-1], legends[-1]]:
		column.add_child(part)
	return card


# D-170: the reading is a single line; the card's width, not the text, sets how wide it is.
func _one_line_label() -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label
