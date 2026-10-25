class_name StatsScreen
extends PanelContainer

# The statistics screen (issue #83, D-052): views of the chapter's history over the whole window, one tab each.
# It only reads the history the simulation keeps (#82, D-066) and never sends a command. While it shows, the map
# gets no input: the map passes its events here. The shoulder buttons change tab and B or Esc goes back; the
# chart tabs (history and classes) take the rest.

signal closed

const SUMMARY_TAB: int = 0
const HISTORY_TAB: int = 1
const CLASSES_TAB: int = 2

var session: GameSession
var presentation: StatsPresentation
var _tabs: TabContainer
var _summary: GridContainer
var _history: TimelineTab
var _classes: ClassesTab
var _hint: Label
var _back: Button
# Per summary card, in StatsSummary.CARDS order: its title, reading, chart and legend row.
var _titles: Array[Label] = []
var _values: Array[Label] = []
var _charts: Array[Sparkline] = []
var _legends: Array[HBoxContainer] = []


func setup(game_session: GameSession, look: StatsPresentation) -> void:
	session = game_session
	presentation = look
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	theme = Theme.new()
	theme.default_font_size = int(look.layout["font_size"])
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = look.colors["background"]
	style.set_content_margin_all(look.layout["margin"])
	add_theme_stylebox_override("panel", style)
	var root: VBoxContainer = VBoxContainer.new()
	add_child(root)
	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)
	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_hint)
	_back = Button.new()
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(close)
	header.add_child(_back)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.focus_mode = Control.FOCUS_NONE
	root.add_child(_tabs)
	_summary = GridContainer.new()
	_summary.columns = int(look.layout["card_columns"])
	_tabs.add_child(_summary)
	for id: StringName in StatsSummary.CARDS:
		_summary.add_child(_card())
	_history = TimelineTab.new()
	_tabs.add_child(_history)
	_history.setup(session, look)
	_classes = ClassesTab.new()
	_tabs.add_child(_classes)
	_classes.setup(session, look)
	_tabs.tab_changed.connect(func(_tab: int) -> void: refresh())
	session.snapshot_changed.connect(func(_snapshot: Dictionary) -> void: refresh())
	hide()
	_apply_texts()


func open() -> void:
	show()
	refresh()


func close() -> void:
	hide()
	closed.emit()


# The map's events while the screen shows; it uses what it needs and swallows the rest.
func handle(event: InputEvent) -> void:
	# ui_cancel is Esc on the keyboard and B on the gamepad (GamepadBindings).
	if event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"map_build_next"):
		_tabs.select_next_available()
	elif event.is_action_pressed(&"map_build_prev"):
		_tabs.select_previous_available()
	elif _tabs.get_current_tab_control() is ChartTab:
		(_tabs.get_current_tab_control() as ChartTab).handle(event)


func refresh() -> void:
	if not visible:
		return
	if _tabs.get_current_tab_control() is ChartTab:
		(_tabs.get_current_tab_control() as ChartTab).refresh()
		return
	var cards: Array[Dictionary] = StatsSummary.build(session.simulation, presentation.summary_span_seconds)
	for index: int in cards.size():
		_show_card(index, cards[index])


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _tabs != null:
		_apply_texts()
		refresh()


func _apply_texts() -> void:
	_hint.text = Strings.text(Strings.STATS_SCREEN_HINT)
	_back.text = Strings.text(Strings.STATS_SCREEN_BACK)
	_tabs.set_tab_title(SUMMARY_TAB, Strings.text(Strings.STATS_SCREEN_SUMMARY))
	_tabs.set_tab_title(HISTORY_TAB, Strings.text(Strings.STATS_SCREEN_HISTORY))
	_tabs.set_tab_title(CLASSES_TAB, Strings.text(Strings.STATS_SCREEN_CLASSES))
	_history.apply_texts()
	_classes.apply_texts()
	for index: int in StatsSummary.CARDS.size():
		_titles[index].text = Strings.text(Strings.STATS_SCREEN_CARDS[StatsSummary.CARDS[index]])


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
	_titles.append(Label.new())
	_values.append(_wrapped_label())
	var chart: Sparkline = Sparkline.new()
	chart.custom_minimum_size.y = presentation.layout["chart_height"]
	_charts.append(chart)
	_legends.append(HBoxContainer.new())
	for part: Control in [_titles[-1], _values[-1], chart, _legends[-1]]:
		column.add_child(part)
	return card


func _show_card(index: int, card: Dictionary) -> void:
	var lines: Array[PackedFloat32Array] = []
	var colors: Array[Color] = []
	var dashes: PackedFloat32Array = []
	for line: int in card["lines"].size():
		lines.append(card["lines"][line]["values"])
		colors.append(presentation.stroke_color(line))
		dashes.append(presentation.stroke_dash(line))
	_charts[index].show_lines(lines, colors, dashes, presentation.layout["line_width"])
	var no_data: bool = card["lines"].is_empty()
	_charts[index].visible = not no_data
	_values[index].text = Strings.text(Strings.STATS_SCREEN_NO_DATA) if no_data else card["value"]
	show_legend(_legends[index], card["lines"], presentation)


# Only a chart with more than one line needs a legend: a short sample of each stroke beside its name.
static func show_legend(row: HBoxContainer, lines: Array[Dictionary], look: StatsPresentation) -> void:
	var names: PackedStringArray = []
	for line: Dictionary in lines:
		names.append(line["label"])
	# Rebuilt only when its names change, not on every tick.
	if row.get_meta(&"names", PackedStringArray()) == names:
		return
	row.set_meta(&"names", names)
	for child: Node in row.get_children():
		child.free()
	if lines.size() < 2:
		return
	for line: int in lines.size():
		var sample: Sparkline = Sparkline.new()
		sample.custom_minimum_size = Vector2(look.layout["legend_width"], look.layout["font_size"])
		sample.show_lines([PackedFloat32Array([0.0, 0.0])] as Array[PackedFloat32Array],
			[look.stroke_color(line)] as Array[Color], PackedFloat32Array([look.stroke_dash(line)]),
			look.layout["line_width"])
		row.add_child(sample)
		var name_label: Label = Label.new()
		name_label.text = lines[line]["label"]
		row.add_child(name_label)


func _wrapped_label() -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
