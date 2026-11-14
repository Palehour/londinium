class_name StatsWhyView
extends VBoxContainer

# The "why?" of one bucket of a chart (issue #319, D-052, D-168): it takes the screen's place while it shows, so there
# is still one chart per screen. The chart tab keeps the cursor: the D-pad moves it, and this view reads the bucket
# it is on. The causes are listed by the "why?" panel of #73 (WhyPanel). "See on the map" only asks: the map moves.

signal map_requested(cell: Vector2i)

var tab: ChartTab
var simulation: Simulation
var cell: Vector2i = StatsWhy.NO_CELL
var _title: Label
var _breakdown: Label
var _causes: WhyPanel
var _no_causes: Label
var _map: Button
var _hint: Label


func setup(look: StatsPresentation) -> void:
	visible = false
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	add_child(_title)
	_breakdown = Label.new()
	_breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_breakdown)
	_causes = WhyPanel.new()
	_causes.setup()
	_causes.apply_style(look.colors["card"], look.layout["margin"])
	add_child(_causes)
	_no_causes = Label.new()
	_no_causes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_no_causes)
	_map = Button.new()
	# Never the focus, so the gamepad keeps the screen.
	_map.focus_mode = Control.FOCUS_NONE
	_map.pressed.connect(request_map)
	add_child(_map)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)


func open(from_tab: ChartTab, from_simulation: Simulation) -> void:
	tab = from_tab
	simulation = from_simulation
	show()
	refresh()


func close() -> void:
	hide()


# Walks to the neighbouring bucket of the tab's chart, with no wrap and stopping at the edges, like D-170.
func walk(step: int) -> void:
	tab.walk(step)
	refresh()


func request_map() -> void:
	if cell != StatsWhy.NO_CELL:
		map_requested.emit(cell)


func refresh() -> void:
	if not visible or tab == null:
		return
	var composed: Dictionary = StatsWhy.compose(simulation, tab.why_chart(), tab.cursor_index(), tab.why_parts())
	var events: Array[Dictionary] = composed["events"]
	cell = composed["cell"]
	_title.text = Strings.text(Strings.WHY_TITLE) % tab.bucket_time()
	var lines: Array[String] = composed["lines"]
	_breakdown.text = "\n".join(lines) if composed["available"] else Strings.text(Strings.STATS_SCREEN_NO_DATA)
	_causes.show_chain(&"stats_bucket", Strings.text(Strings.STATS_SCREEN_WHY_CAUSES), events, composed["pruned"], true, true)
	if _causes.visible and not _causes.expanded:
		_causes.toggle()
	_no_causes.text = Strings.text(Strings.STATS_SCREEN_WHY_NO_CAUSES)
	_no_causes.visible = events.is_empty()
	_map.text = Strings.text(Strings.STATS_SCREEN_WHY_MAP)
	_map.visible = cell != StatsWhy.NO_CELL
	_hint.text = Strings.text(Strings.STATS_SCREEN_WHY_HINT)
