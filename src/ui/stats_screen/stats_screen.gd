class_name StatsScreen
extends PanelContainer

# The statistics screen (issue #83, D-052): views of the chapter's history over the whole window, one tab each.
# It only reads the history the simulation keeps (#82, D-066) and never sends a command. While it shows, the map
# gets no input: the map passes its events here. The shoulder buttons change tab and B or Esc goes back; the
# chart tabs (summary, chains, history and classes) take the rest.

signal closed

const SUMMARY_TAB: int = 0
const CHAINS_TAB: int = 1
const HISTORY_TAB: int = 2
const CLASSES_TAB: int = 3

var session: GameSession
var presentation: StatsPresentation
var _tabs: TabContainer
var _summary: SummaryTab
var _chains: ChainsTab
var _history: TimelineTab
var _classes: ClassesTab
var _hint: Label
var _back: Button
# The summary's no-data lines and charts, per card in StatsSummary.CARDS order (the same arrays SummaryTab fills).
var _values: Array[Label] = []
var _charts: Array[Sparkline] = []


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
	_summary = SummaryTab.new()
	_tabs.add_child(_summary)
	_summary.setup(session, look)
	_values = _summary.values
	_charts = _summary.charts
	_chains = ChainsTab.new()
	_tabs.add_child(_chains)
	_chains.setup(session, look)
	_history = TimelineTab.new()
	_tabs.add_child(_history)
	_history.setup(session, look)
	_classes = ClassesTab.new()
	_tabs.add_child(_classes)
	_classes.setup(session, look)
	_tabs.tab_changed.connect(_on_tab_changed)
	session.snapshot_changed.connect(func(_snapshot: Dictionary) -> void: refresh())
	hide()
	_apply_texts()


func open() -> void:
	# D-170: the summary opens on its newest bucket. Chains starts on its first link (D-173).
	_summary.reset_cursor()
	_chains.reset_selection()
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
		# On Historia, LB/RB change the series. The other tabs keep the shoulders for the tabs. Godot's
		# select_previous_available stays on the first tab, so the index wraps here: LB from the summary opens
		# Classes. B leaves Historia. There is no extra tab control.
		if _tabs.current_tab == HISTORY_TAB:
			_history.change_series(1)
		else:
			_tabs.current_tab = posmod(_tabs.current_tab + 1, _tabs.get_tab_count())
	elif event.is_action_pressed(&"map_build_prev"):
		if _tabs.current_tab == HISTORY_TAB:
			_history.change_series(-1)
		else:
			_tabs.current_tab = posmod(_tabs.current_tab - 1, _tabs.get_tab_count())
	elif _tabs.get_current_tab_control() is ChartTab:
		(_tabs.get_current_tab_control() as ChartTab).handle(event)


func refresh() -> void:
	if not visible:
		return
	(_tabs.get_current_tab_control() as ChartTab).refresh()


func _on_tab_changed(tab: int) -> void:
	if tab == SUMMARY_TAB:
		_summary.reset_cursor()
	elif tab == CHAINS_TAB:
		_chains.reset_selection()
	_apply_header()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _tabs != null:
		_apply_texts()
		refresh()


func _apply_texts() -> void:
	_apply_header()
	_back.text = Strings.text(Strings.STATS_SCREEN_BACK)
	_tabs.set_tab_title(SUMMARY_TAB, Strings.text(Strings.STATS_SCREEN_SUMMARY))
	_tabs.set_tab_title(CHAINS_TAB, Strings.text(Strings.STATS_SCREEN_CHAINS))
	_tabs.set_tab_title(HISTORY_TAB, Strings.text(Strings.STATS_SCREEN_HISTORY))
	_tabs.set_tab_title(CLASSES_TAB, Strings.text(Strings.STATS_SCREEN_CLASSES))
	_summary.apply_texts()
	_chains.apply_texts()
	_history.apply_texts()
	_classes.apply_texts()


func _apply_header() -> void:
	var on_history: bool = _tabs.current_tab == HISTORY_TAB
	_hint.text = Strings.text(Strings.STATS_SCREEN_HISTORY_HEADER if on_history else Strings.STATS_SCREEN_HINT)


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
