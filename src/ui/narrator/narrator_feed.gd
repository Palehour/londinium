class_name NarratorFeed
extends VBoxContainer

# The narrator's notices on screen (issue #73, D-137): each one's words, and its buttons: "why?" opens its chain in
# the cause log, "see on the map" goes to its building, close takes it away. It only shows what the map view hands
# it; the buttons never take the focus, so the gamepad keeps the map.

signal why_requested(notice: Dictionary)
# The target is the resolved one (NarratorText.resolve_target): a building, or its tile once it is gone.
signal map_requested(notice: Dictionary, target: Dictionary)
signal graph_requested(notice: Dictionary)
signal dismissed(id: int)

# The face button each action has on the gamepad (issue #73, §8): A why, X map, Y graph, B close.
const PAD_LABELS: Dictionary[StringName, String] = {&"why": "A", &"map": "X", &"graph": "Y", &"close": "B"}

# The words of each notice shown, in order.
var texts: Array[String] = []
var _shown: Array = []
var _style: StyleBoxFlat
var _focus_style: StyleBoxFlat
var _alert: Color = Color.WHITE
var _min_button_px: int = 0


func setup(background: Color, alert: Color, margin: float, min_button_px: int) -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert = alert
	_min_button_px = min_button_px
	_style = StyleBoxFlat.new()
	_style.bg_color = background
	_style.set_content_margin_all(margin)
	# The notice the gamepad acts on: the same panel with the alert colour as its border.
	_focus_style = _style.duplicate() as StyleBoxFlat
	_focus_style.border_color = alert
	_focus_style.set_border_width_all(1)


# `building_labels`: the map's names by id. `resolve`: Callable(notice) -> its map target now. `has_graph`:
# Callable(notice) -> whether its series exists in the history. `focus_id`: the notice the gamepad acts on, 0 for none.
func show_notices(notices: Array[Dictionary], building_labels: Dictionary, resolve: Callable, has_graph: Callable,
		focus_id: int = 0, gamepad: bool = false) -> void:
	var targets: Array[Dictionary] = []
	var graphs: Array[bool] = []
	for notice: Dictionary in notices:
		targets.append(resolve.call(notice))
		graphs.append(has_graph.call(notice))
	var shown: Array = [notices, TranslationServer.get_locale(), targets, graphs, focus_id, gamepad]
	if shown == _shown:
		return
	_shown = shown
	# Queued: the close button that asked for this is still sending its signal.
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	texts.clear()
	for index: int in notices.size():
		var text: String = NarratorText.text(notices[index], building_labels)
		texts.append(text)
		add_child(_row(notices[index], text, targets[index], graphs[index], focus_id, gamepad))


func _row(notice: Dictionary, text: String, target: Dictionary, graph: bool, focus_id: int, gamepad: bool) -> PanelContainer:
	var row: PanelContainer = PanelContainer.new()
	row.name = "Notice%d" % notice["id"]
	row.add_theme_stylebox_override("panel", _focus_style if notice["id"] == focus_id else _style)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var rows: VBoxContainer = VBoxContainer.new()
	row.add_child(rows)
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	if notice["priority"] == NarratorConfig.CRITICAL:
		label.add_theme_color_override("font_color", _alert)
	rows.add_child(label)
	var buttons: HBoxContainer = HBoxContainer.new()
	rows.add_child(buttons)
	if notice["kind"] != Narrator.DIGEST_KIND:
		buttons.add_child(_button("Why", &"why", Strings.NARRATOR_WHY, gamepad, func() -> void: why_requested.emit(notice)))
	if target.get("type", NarratorText.TYPE_NONE) != NarratorText.TYPE_NONE:
		buttons.add_child(_button("Map", &"map", Strings.NARRATOR_MAP, gamepad, func() -> void: map_requested.emit(notice, target)))
	if graph:
		buttons.add_child(_button("Graph", &"graph", Strings.NARRATOR_GRAPH, gamepad, func() -> void: graph_requested.emit(notice)))
	buttons.add_child(_button("Close", &"close", Strings.NARRATOR_CLOSE, gamepad, func() -> void: dismissed.emit(int(notice["id"]))))
	return row


func _button(name_: String, action: StringName, key: StringName, gamepad: bool, pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.name = name_
	button.text = Strings.text(key)
	if gamepad:
		button.text = Strings.text(Strings.NARRATOR_PAD_BUTTON) % [button.text, PAD_LABELS[action]]
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(_min_button_px, _min_button_px)
	button.pressed.connect(pressed)
	return button
