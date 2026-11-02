class_name ChainsTab
extends ChartTab

# The chains tab (issue #315, D-173). One chain on screen. ←/→ switch chain and ↑/↓ walk its links, without wrapping
# and without a detail (that is #319). LT/RT or +/- change the window, as on the other chart tabs. The highlight is
# a border from stats.json; the focus tints the label when the same link is both.

var titles: Label
var readings: Array[Label] = []
var _rows: Array[PanelContainer] = []
var _legend: HBoxContainer
var _chain: int = 0
var _link: int = 0
var _built: Dictionary = {}


func setup(game_session: GameSession, look: StatsPresentation) -> void:
	session = game_session
	presentation = look
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_range_buttons()
	titles = Label.new()
	add_child(titles)
	_legend = HBoxContainer.new()
	add_child(_legend)
	_hint = _wrapped_label()
	apply_texts()


func apply_texts() -> void:
	_apply_range_texts()
	_hint.text = Strings.text(Strings.STATS_SCREEN_CHAINS_HINT)
	# Locale changed: the legend names have to be written again.
	_legend.set_meta(&"names", PackedStringArray())


# Back on the first chain and its first link, as when the tab is selected.
func reset_selection() -> void:
	_chain = 0
	_link = 0


func chain_index() -> int:
	return _chain


func link_index() -> int:
	return _link


func handle(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left", true):
		_move_chain(-1)
	elif event.is_action_pressed(&"ui_right", true):
		_move_chain(1)
	elif event.is_action_pressed(&"ui_up", true):
		_move_link(-1)
	elif event.is_action_pressed(&"ui_down", true):
		_move_link(1)
	elif event.is_action_pressed(&"ui_accept"):
		# The detail of a link is #319. A does nothing here, so it cannot open one ahead of that issue.
		return
	elif _pulled(event, &"map_zoom_in") or _is_key(event, NARROWER_KEYS):
		_pick_range(maxi(0, _range - 1))
	elif _pulled(event, &"map_zoom_out") or _is_key(event, WIDER_KEYS):
		_pick_range(mini(_range_buttons.size() - 1, _range + 1))


func refresh() -> void:
	var range_entry: Dictionary = _range_entry()
	_built = StatsChains.build(session.simulation, presentation.chains_order, _chain, range_entry["span_seconds"],
		range_entry["tier"])
	_show()


func _show() -> void:
	titles.text = Strings.label(Strings.STATS_SCREEN_CHAIN_NAMES, _built["id"])
	_show_legend()
	var links: Array = _built["links"]
	_ensure_rows(links.size())
	var columns: Array[StringName] = _column_ids()
	for index: int in _rows.size():
		var row: PanelContainer = _rows[index]
		row.visible = index < links.size()
		if index >= links.size():
			continue
		var link: Dictionary = links[index]
		readings[index].text = StatsChains.reading(link, columns)
		_paint(row, readings[index], link["highlighted"], index == _link)


func _move_chain(step: int) -> void:
	var next: int = _chain + step
	if next < 0 or next >= presentation.chains_order.size():
		return
	_chain = next
	_link = 0
	refresh()


func _move_link(step: int) -> void:
	var count: int = presentation.chains_order[_chain]["links"].size()
	var next: int = _link + step
	if next < 0 or next >= count:
		return
	_link = next
	refresh()


func _ensure_rows(count: int) -> void:
	while _rows.size() < count:
		var row: PanelContainer = PanelContainer.new()
		var label: Label = _one_line_label()
		row.add_child(label)
		add_child(row)
		move_child(row, _hint.get_index())
		_rows.append(row)
		readings.append(label)
	for index: int in _rows.size():
		_rows[index].visible = index < count


func _paint(row: PanelContainer, label: Label, highlighted: bool, focused: bool) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = presentation.colors["card"]
	style.set_content_margin_all(4)
	var width: int = 0
	if highlighted:
		style.border_color = presentation.chains_highlight_color
		width = int(presentation.chains_highlight_width)
	elif focused:
		style.border_color = presentation.colors["cursor"]
		width = int(presentation.layout["line_width"])
	style.set_border_width_all(width)
	row.add_theme_stylebox_override("panel", style)
	# The highlight keeps the border. Focus, when it shares the link, tints the text instead.
	if highlighted and focused:
		label.add_theme_color_override("font_color", presentation.colors["cursor"])
	else:
		label.remove_theme_color_override("font_color")


func _show_legend() -> void:
	var names: PackedStringArray = []
	for column: Dictionary in presentation.chains_columns:
		names.append(String(column["id"]))
	if _legend.get_meta(&"names", PackedStringArray()) == names:
		return
	_legend.set_meta(&"names", names)
	for child: Node in _legend.get_children():
		child.free()
	for column: Dictionary in presentation.chains_columns:
		var sample: Sparkline = Sparkline.new()
		sample.custom_minimum_size = Vector2(presentation.layout["legend_width"], 16)
		sample.show_lines([PackedFloat32Array([0.0, 1.0])], [column["color"]], PackedFloat32Array([column["dash"]]),
			presentation.layout["line_width"])
		var caption: Label = Label.new()
		caption.text = Strings.label(Strings.STATS_SCREEN_CHAIN_COLUMNS, column["id"])
		_legend.add_child(sample)
		_legend.add_child(caption)


func _column_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for column: Dictionary in presentation.chains_columns:
		ids.append(column["id"])
	return ids


func _one_line_label() -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
