extends Node2D

const CELL_SIZE: float = 112.0
const HELP_HEIGHT: float = 176.0
const PAN_SPEED: float = 500.0
const ZOOM_STEP: float = 1.15
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
	# Issue #9 attaches its panel here and consumes input before _unhandled_input.
	var panel_mount: Control = Control.new()
	panel_mount.name = "PanelMount"
	panel_mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel_mount)
	var background: ColorRect = ColorRect.new()
	background.color = Color("#20242b")
	background.size = Vector2(get_viewport_rect().size.x, HELP_HEIGHT)
	background.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	background.offset_bottom = HELP_HEIGHT
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(background)
	var help: VBoxContainer = VBoxContainer.new()
	help.position = Vector2(16, 8)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(help)
	for text: String in [Strings.LOADING, Strings.LEGEND, "", ""]:
		var label: Label = Label.new()
		label.text = text
		help.add_child(label)
	_mode = help.get_child(2) as Label
	_status = help.get_child(3) as Label
	var loaded: DataLoadResult = DataLoader.new().load_all()
	if not loaded.is_ok():
		_status.text = Strings.LOAD_ERROR % "\n".join(loaded.errors)
		return
	var ids: Array[StringName] = []
	ids.assign(loaded.catalog.buildings.keys())
	presentation.load_data(ids)
	if not presentation.errors.is_empty():
		_status.text = Strings.LOAD_ERROR % "\n".join(presentation.errors)
		return
	var labels: Array[String] = []
	for id: StringName in TYPES:
		labels.append(presentation.labels[id])
	(help.get_child(0) as Label).text = Strings.HELP % labels
	session = GameSession.new(loaded.catalog, Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"]))
	geometry = MapGeometry.new(Vector2i(session.context.map.width, session.context.map.height), CELL_SIZE, _map_viewport())
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


func _map_viewport() -> Vector2:
	var size: Vector2 = get_viewport_rect().size
	return Vector2(maxf(size.x, 1.0), maxf(size.y - HELP_HEIGHT, 1.0))


func _resized() -> void:
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
	geometry.center += direction.normalized() * PAN_SPEED * delta / geometry.zoom
	geometry.constrain()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if geometry == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_building_type = TYPES[event.keycode - KEY_1]
		elif event.keycode == KEY_ESCAPE:
			_building_type = &""
		elif event.keycode == KEY_DELETE and geometry.selected != Vector2i(-1, -1):
			_submit(DemolishCommand.new(geometry.selected))
		elif event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
			geometry.zoom *= 1.0 / ZOOM_STEP if event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] else ZOOM_STEP
	if event is InputEventMouseButton:
		if event.pressed and event.position.y >= HELP_HEIGHT:
			if event.button_index == MOUSE_BUTTON_LEFT:
				geometry.select_cell(event.position - Vector2(0, HELP_HEIGHT))
				if _building_type != &"":
					_submit(BuildCommand.new(session.context, _building_type, geometry.screen_to_cell(event.position - Vector2(0, HELP_HEIGHT))))
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				geometry.zoom *= ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		geometry.center -= event.relative / geometry.zoom
	geometry.constrain()
	_update_mode()
	queue_redraw()


func _submit(command: SimulationCommand) -> void:
	_status.text = Strings.PENDING
	session.submit_command(command)


func _command_resolved(accepted: bool, reason: StringName) -> void:
	_status.text = Strings.command_result(accepted, reason)


func _snapshot_received(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	queue_redraw()


func _update_mode() -> void:
	_mode.text = Strings.MODE % [presentation.labels.get(_building_type, Strings.SELECT), geometry.selected]


func _draw() -> void:
	if geometry == null:
		return
	draw_set_transform(Vector2(0, HELP_HEIGHT) + geometry.viewport_size / 2.0 - geometry.center * geometry.zoom, 0.0, Vector2.ONE * geometry.zoom)
	var map: MapDef = session.context.map
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			draw_rect(Rect2(Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE).grow(-1), presentation.terrain[geometry.terrain_at(cell, map)])
	var font: Font = ThemeDB.fallback_font
	for building: Dictionary in _snapshot["economy"]["buildings"]:
		var cell: Vector2 = Vector2(building["cell"][0], building["cell"][1])
		var id: StringName = StringName(building["definition_id"])
		var rect: Rect2 = Rect2(cell * CELL_SIZE, Vector2.ONE * CELL_SIZE).grow(-6)
		draw_rect(rect, presentation.colors[id])
		var text: String = presentation.labels[id]
		var font_size: int = 14
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, rect.get_center() + Vector2(-width / 2.0, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	if geometry.selected != Vector2i(-1, -1):
		draw_rect(Rect2(Vector2(geometry.selected) * CELL_SIZE, Vector2.ONE * CELL_SIZE).grow(-2), Color.WHITE, false, 3.0)
