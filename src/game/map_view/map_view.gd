extends Node2D

const TYPES: Array[StringName] = [&"wharf", &"mill", &"bakery", &"housing", &"wheat_field"]

var session: GameSession
var clock: SimClock
var geometry: MapGeometry
var presentation: MapPresentation = MapPresentation.new()
var _snapshot: Dictionary
var _building_type: StringName = &""
var _status: Label
var _mode: Label


func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var loaded: DataLoadResult = DataLoader.new().load_all()
	if not loaded.is_ok():
		_show_load_error(layer, loaded.errors)
		return
	var ids: Array[StringName] = []
	ids.assign(loaded.catalog.buildings.keys())
	presentation.load_data(ids)
	if not presentation.errors.is_empty():
		_show_load_error(layer, presentation.errors)
		return
	var background: ColorRect = ColorRect.new()
	background.color = presentation.ui_colors["header"]
	background.size = Vector2(get_viewport_rect().size.x, presentation.layout["header_height"])
	background.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	background.offset_bottom = presentation.layout["header_height"]
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(background)
	var help: VBoxContainer = VBoxContainer.new()
	help.position = Vector2(presentation.layout["help_x"], presentation.layout["help_y"])
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(help)
	for text: String in [Strings.LOADING, Strings.LEGEND, "", ""]:
		var label: Label = Label.new()
		label.text = text
		help.add_child(label)
	_mode = help.get_child(2) as Label
	_status = help.get_child(3) as Label
	# Mount last so issue #9 draws and receives input above the header and help.
	var panel_mount: Control = Control.new()
	panel_mount.name = "PanelMount"
	panel_mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel_mount)
	var labels: Array[String] = []
	for id: StringName in TYPES:
		labels.append(presentation.labels[id])
	(help.get_child(0) as Label).text = Strings.HELP % labels
	session = GameSession.new(loaded.catalog, Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"]))
	geometry = MapGeometry.new(Vector2i(session.context.map.width, session.context.map.height), presentation.layout["cell_size"], _map_viewport(), presentation.camera["max_zoom_factor"])
	_snapshot = session.get_snapshot()
	session.snapshot_changed.connect(_snapshot_received)
	session.command_resolved.connect(_command_resolved)
	clock = SimClock.new()
	clock.simulation = session.simulation
	clock.tick_advanced.connect(session.publish_tick)
	add_child(clock)
	get_viewport().size_changed.connect(_resized)
	_update_mode()
	queue_redraw()


func _show_load_error(layer: CanvasLayer, errors: Array[String]) -> void:
	var label: Label = Label.new()
	label.text = Strings.LOAD_ERROR % "\n".join(errors)
	layer.add_child(label)


func _map_viewport() -> Vector2:
	var size: Vector2 = get_viewport_rect().size
	return Vector2(maxf(size.x, 1.0), maxf(size.y - presentation.layout["header_height"], 1.0))


func _resized() -> void:
	if geometry.viewport_size == _map_viewport():
		return
	geometry.viewport_size = _map_viewport()
	geometry.constrain()
	queue_redraw()


func _process(delta: float) -> void:
	if geometry == null:
		return
	var direction: Vector2 = Vector2.ZERO
	# Poll only camera keys; commands use unhandled events so UI can consume them.
	if get_viewport().gui_get_focus_owner() == null:
		direction.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		direction.y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var previous_center: Vector2 = geometry.center
	geometry.center += direction.normalized() * presentation.camera["pan_speed"] * delta / geometry.zoom
	geometry.constrain()
	if geometry.center != previous_center:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if geometry == null:
		return
	var previous_center: Vector2 = geometry.center
	var previous_zoom: float = geometry.zoom
	var previous_selection: Vector2i = geometry.selected
	var previous_type: StringName = _building_type
	var header_offset: Vector2 = Vector2(0, presentation.layout["header_height"])
	var zoom_step: float = presentation.camera["zoom_step"]
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_building_type = TYPES[event.keycode - KEY_1]
		elif event.keycode == KEY_ESCAPE:
			_building_type = &""
		elif event.keycode == KEY_DELETE and geometry.selected != Vector2i(-1, -1):
			_submit(DemolishCommand.new(geometry.selected))
		elif event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
			geometry.zoom *= 1.0 / zoom_step if event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] else zoom_step
	if event is InputEventMouseButton:
		if event.pressed and event.position.y >= header_offset.y:
			if event.button_index == MOUSE_BUTTON_LEFT:
				geometry.select_cell(event.position - header_offset)
				if _building_type != &"":
					_submit(BuildCommand.new(session.context, _building_type, geometry.screen_to_cell(event.position - header_offset)))
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				geometry.zoom *= zoom_step if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_step
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		geometry.center -= event.relative / geometry.zoom
	geometry.constrain()
	if geometry.selected != previous_selection or _building_type != previous_type:
		_update_mode()
	if geometry.center != previous_center or geometry.zoom != previous_zoom or geometry.selected != previous_selection or _building_type != previous_type:
		queue_redraw()


func _submit(command: SimulationCommand) -> void:
	_status.text = Strings.PENDING
	session.submit_command(command)


func _command_resolved(accepted: bool, reason: StringName) -> void:
	_status.text = Strings.command_result(accepted, reason)


func _snapshot_received(snapshot: Dictionary) -> void:
	if snapshot == _snapshot:
		return
	_snapshot = snapshot
	queue_redraw()


func _update_mode() -> void:
	_mode.text = Strings.MODE % [presentation.labels.get(_building_type, Strings.SELECT), geometry.selected]


func _draw() -> void:
	if geometry == null:
		return
	var cell_size: float = presentation.layout["cell_size"]
	draw_set_transform(Vector2(0, presentation.layout["header_height"]) + geometry.viewport_size / 2.0 - geometry.center * geometry.zoom, 0.0, Vector2.ONE * geometry.zoom)
	var map: MapDef = session.context.map
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			draw_rect(Rect2(Vector2(cell) * cell_size, Vector2.ONE * cell_size).grow(-presentation.layout["grid_inset"]), presentation.terrain[geometry.terrain_at(cell, map)])
	var font: Font = ThemeDB.fallback_font
	for building: Dictionary in _snapshot["economy"]["buildings"]:
		var cell: Vector2 = Vector2(building["cell"][0], building["cell"][1])
		var id: StringName = StringName(building["definition_id"])
		var rect: Rect2 = Rect2(cell * cell_size, Vector2.ONE * cell_size).grow(-presentation.layout["building_inset"])
		draw_rect(rect, presentation.colors[id])
		var text: String = presentation.labels[id]
		var font_size: int = int(presentation.layout["font_size"])
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, rect.get_center() + Vector2(-width / 2.0, presentation.layout["label_offset_y"]), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, presentation.ui_colors["label"])
	if geometry.selected != Vector2i(-1, -1):
		draw_rect(Rect2(Vector2(geometry.selected) * cell_size, Vector2.ONE * cell_size).grow(-presentation.layout["selection_inset"]), presentation.ui_colors["selection"], false, presentation.layout["selection_width"])
