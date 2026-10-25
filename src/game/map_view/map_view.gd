class_name MapView
extends Node2D

# The 2D map of colored squares. The 3D greybox (CityView, issue #65) extends it and replaces only how the map is drawn
# and how the camera picks a cell, so placing, demolishing, the panel and the gamepad stay one piece of code.

const TYPES: Array[StringName] = [&"wharf", &"mill", &"bakery", &"housing", &"wheat_field", &"malthouse", &"brewery", &"artisan_housing"]
# The player's street (issue #168, D-080): not a building, so it stays out of TYPES. It is the last entry of the
# LB/RB cycle and key 9, only on a map with streets.
const ROAD: StringName = GameSession.ROAD
const ROAD_KEY: Key = KEY_9
# The service buildings (issue #87, D-118): key 0 goes through them in the order of their attributes. The LB/RB cycle
# does not take them yet.
const SERVICE_KEY: Key = KEY_0
const SCENARIO_FLAG: String = "--scenario="
# Repairs the damaged wharf under the selection (issue #178, D-083), or disinfects the house in a crisis (issue #222);
# Y on the gamepad.
const REPAIR_KEY: Key = KEY_R
# Points in the demolish ring. A drawing constant, not the hold time (that lives in data/ui/map.json).
const DEMOLISH_RING_POINTS: int = 32

var session: GameSession
var clock: SimClock
var geometry: MapGeometry
var presentation: MapPresentation = MapPresentation.new()
# Where the player's mods live; a test points it elsewhere so the machine's own mods never reach it.
var mods_root: String = ModLayer.DEFAULT_ROOT
# Where saved games live (issue #57); a test points it elsewhere so the player's saves are never touched.
var saves_root: String = SaveFile.DEFAULT_ROOT
# The scenario this view plays; the 3D city plays the full map (issue #65). `-- --scenario=<id>` on the command line
# plays another scenario of data/scenarios, like the trial one with the incidents on (issue #87, D-122).
var scenario_id: StringName = &"victorian_demo"
var _catalog: DataCatalog
var _snapshot: Dictionary
var _building_type: StringName = &""
var _status: Label
var _mode: Label
var _help: Label
var _legend_caption: Label
var _terrain_labels: Dictionary[String, Label] = {}
# The second legend row: the 1870 lots and the damaged wharf (issue #178).
var _lots_caption: Label
var _lot_labels: Dictionary[StringName, Label] = {}
var _damaged_wharf_label: Label
# Attribution of the historical map sources (issue #60, CREDITS.md).
var _credits: Label
var _stats_panel: StatsPanel
var _archive_panel: ArchivePanel
# The statistics screen (issue #83): while it shows, the map's input goes to it.
var _stats_screen: StatsScreen
var _autosave: Autosave
var _status_pending: bool = false
var _status_has_result: bool = false
var _status_accepted: bool = false
var _status_reason: StringName = &""
# Whether the last input came from a gamepad, so the help shows its buttons (issue #68).
var _gamepad: bool = false
# Hold X to demolish (issue #164, D-078). One press submits one command; the ring reads _demolish_progress.
var _demolish_was_down: bool = false
var _demolish_holding: bool = false
var _demolish_fired: bool = false
var _demolish_elapsed: float = 0.0
var _demolish_progress: float = 0.0
var _demolish_cell: Vector2i = Vector2i(-1, -1)
# The tooltip of the selected house in a crisis (issue #222, D-108), with its Disinfect button.
var _crisis_tip: PanelContainer
var _crisis_text: Label
var _crisis_button: Button
# The tooltip of the selected service, with its availability bar, or of the selected house, with its district's
# attributes (issue #87, D-118).
var _service_tip: PanelContainer
var _service_title: Label
var _service_bar: ProgressBar
var _service_text: Label


func _ready() -> void:
	Strings.use_default_locale()
	# Phrases are already translated. Leaving auto-translate on would look the sentence up as a key.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	GamepadBindings.install()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var loaded: DataLoadResult = _load_catalog()
	if not loaded.is_ok():
		_show_load_error(layer, loaded.errors)
		return
	var ids: Array[StringName] = []
	ids.assign(loaded.catalog.buildings.keys())
	_load_presentation(ids)
	var stats_look: StatsPresentation = StatsPresentation.new()
	stats_look.load_data()
	if not presentation.errors.is_empty() or not stats_look.errors.is_empty():
		_show_load_error(layer, presentation.errors + stats_look.errors)
		return
	var save_settings: SaveSettings = SaveSettings.new()
	save_settings.load_data()
	if not save_settings.errors.is_empty():
		_show_load_error(layer, save_settings.errors)
		return
	var background: ColorRect = ColorRect.new()
	background.color = presentation.ui_colors["header"]
	background.size = Vector2(get_viewport_rect().size.x, presentation.layout["header_height"])
	background.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	background.offset_bottom = presentation.layout["header_height"]
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(background)
	var help: VBoxContainer = VBoxContainer.new()
	# Stops short of the panel, so at 1280×800 a long line wraps instead of running under it.
	help.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help.offset_left = presentation.layout["help_x"]
	help.offset_top = presentation.layout["help_y"]
	help.offset_right = -presentation.layout["panel_width"] - presentation.layout["help_x"]
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(help)
	for text: String in [Strings.text(Strings.LOADING), "", ""]:
		var label: Label = Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.add_child(label)
	var legend: HBoxContainer = HBoxContainer.new()
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption: Label = Label.new()
	caption.text = Strings.text(Strings.LEGEND)
	_legend_caption = caption
	legend.add_child(caption)
	for kind: String in MapPresentation.TERRAIN_KINDS:
		var sample: ColorRect = ColorRect.new()
		sample.color = presentation.terrain[kind]
		sample.custom_minimum_size = Vector2.ONE * presentation.layout["font_size"]
		sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
		legend.add_child(sample)
		var label: Label = Label.new()
		label.text = Strings.text(Strings.TERRAIN_LABELS[kind])
		_terrain_labels[kind] = label
		legend.add_child(label)
	help.add_child(legend)
	help.move_child(legend, 1)
	var lots: HBoxContainer = _lots_legend()
	help.add_child(lots)
	help.move_child(lots, 2)
	_credits = Label.new()
	# The full NLS credit line (issue #152) is long: it wraps instead of widening the header.
	_credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credits.text = Strings.text(Strings.MAP_CREDITS)
	help.add_child(_credits)
	_mode = help.get_child(3) as Label
	_status = help.get_child(4) as Label
	_help = help.get_child(0) as Label
	_crisis_tip = _crisis_tooltip()
	layer.add_child(_crisis_tip)
	_service_tip = _service_tooltip()
	layer.add_child(_service_tip)
	# Mount last so issue #9 draws and receives input above the header and help.
	var panel_mount: Control = Control.new()
	panel_mount.name = "PanelMount"
	panel_mount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel_mount)
	_catalog = loaded.catalog
	scenario_id = launch_scenario(loaded.catalog, scenario_id)
	session = GameSession.new(loaded.catalog, Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"]), scenario_id)
	_use_mods(loaded, false)
	_autosave = Autosave.new(session, save_settings, saves_root)
	_update_help()
	geometry = MapGeometry.new(Vector2i(session.context.map.width, session.context.map.height), presentation.layout["cell_size"], _map_viewport(), presentation.camera["max_zoom_factor"])
	_snapshot = session.get_snapshot()
	session.snapshot_changed.connect(_snapshot_received)
	session.command_resolved.connect(_command_resolved)
	session.snapshot_changed.connect(_autosave.observe)
	_autosave.saved.connect(func(_path: String) -> void: _stats_panel.show_saves(SaveFile.list(saves_root)))
	clock = SimClock.new()
	clock.simulation = session.simulation
	clock.tick_advanced.connect(session.publish_tick)
	add_child(clock)
	_stats_panel = StatsPanel.new()
	_stats_panel.name = "StatsPanel"
	_stats_panel.setup(session, clock)
	_stats_panel.apply_style(presentation.ui_colors["header"], presentation.ui_colors["alert"], presentation.layout["panel_margin"])
	# Anchored to the right edge, so window resizes keep it in place without manual layout.
	_stats_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_stats_panel.offset_left = -presentation.layout["panel_width"]
	_stats_panel.restart_requested.connect(_restart_session)
	_stats_panel.difficulty_selected.connect(_start_on_difficulty)
	_stats_panel.mod_order_requested.connect(_reorder_mods)
	_stats_panel.save_requested.connect(_save_game)
	_stats_panel.load_requested.connect(_load_game)
	_stats_panel.load_with_save_mods_requested.connect(_load_with_save_mods)
	_stats_panel.stats_requested.connect(_open_stats)
	if not mods_root.is_empty():
		_stats_panel.set_mods_folder(ProjectSettings.globalize_path(mods_root))
	panel_mount.add_child(_stats_panel)
	_stats_panel.show_saves(SaveFile.list(saves_root))
	_stats_panel.update_snapshot(_snapshot)
	_mount_archive(panel_mount)
	_stats_screen = StatsScreen.new()
	_stats_screen.name = "StatsScreen"
	_stats_screen.setup(session, stats_look)
	_stats_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_mount.add_child(_stats_screen)
	get_viewport().size_changed.connect(_resized)
	_view_ready()
	_update_mode()
	queue_redraw()


func _load_presentation(building_ids: Array[StringName]) -> void:
	presentation.load_data(building_ids)


# Called once the session, the geometry and the panel exist; the 3D city builds its world here.
func _view_ready() -> void:
	pass


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or _help == null:
		return
	presentation.refresh_labels()
	_legend_caption.text = Strings.text(Strings.LEGEND)
	_credits.text = Strings.text(Strings.MAP_CREDITS)
	for kind: String in _terrain_labels:
		_terrain_labels[kind].text = Strings.text(Strings.TERRAIN_LABELS[kind])
	_lots_caption.text = Strings.text(Strings.LOTS_LEGEND)
	for style: StringName in _lot_labels:
		_lot_labels[style].text = presentation.lot_labels[style]
	_damaged_wharf_label.text = Strings.text(Strings.DAMAGED_WHARF)
	_update_help()
	if geometry != null:
		_update_mode()
	_apply_status()
	queue_redraw()


# Same shape as the terrain legend: a sample square and its name for each lot style, then the damaged wharf.
func _lots_legend() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lots_caption = Label.new()
	_lots_caption.text = Strings.text(Strings.LOTS_LEGEND)
	row.add_child(_lots_caption)
	for style: StringName in Strings.LOT_STYLE_LABELS:
		_lot_labels[style] = _legend_entry(row, presentation.lot_colors[style], presentation.lot_labels[style])
	_damaged_wharf_label = _legend_entry(row, presentation.ui_colors["damaged_wharf"], Strings.text(Strings.DAMAGED_WHARF))
	return row


func _legend_entry(row: HBoxContainer, color: Color, text: String) -> Label:
	var sample: ColorRect = ColorRect.new()
	sample.color = color
	sample.custom_minimum_size = Vector2.ONE * presentation.layout["font_size"]
	sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sample)
	var label: Label = Label.new()
	label.text = text
	row.add_child(label)
	return label


func _load_catalog() -> DataLoadResult:
	return DataLoader.new().load_all("res://data", DataLoader.DEFAULT_ERA, mods_root)


func _update_help() -> void:
	var labels: Array[String] = []
	for id: StringName in TYPES:
		var label: String = presentation.labels[id]
		var reason: String = presentation.building_unavailable_reason(session.get_building_unavailable_reason(id))
		labels.append(label if reason.is_empty() else Strings.text(Strings.DISABLED_BUILDING) % [label, reason])
	_help.text = Strings.text(Strings.HELP_GAMEPAD if _gamepad else Strings.HELP) % labels


# The Archive (issue #64, D-110): over the map, left of the side panel, hidden until its button is pressed. It only
# reads the snapshot. A card whose mission this game's data lacks just stays locked, so missions are not checked here.
func _mount_archive(panel_mount: Control) -> void:
	var archive: ArchiveCatalog = ArchiveCatalog.new()
	archive.load_data()
	for error: String in archive.errors:
		push_error(error)
	_archive_panel = ArchivePanel.new()
	_archive_panel.name = "ArchivePanel"
	_archive_panel.setup(archive)
	_archive_panel.apply_style(presentation.ui_colors["header"], presentation.layout["panel_margin"])
	_archive_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_archive_panel.offset_left = -2.0 * presentation.layout["panel_width"]
	_archive_panel.offset_right = -presentation.layout["panel_width"]
	_archive_panel.visible = false
	_stats_panel.archive_requested.connect(func() -> void: _archive_panel.visible = not _archive_panel.visible)
	panel_mount.add_child(_archive_panel)
	_archive_panel.update_snapshot(_snapshot)


func _show_load_error(layer: CanvasLayer, errors: Array[String]) -> void:
	var label: Label = Label.new()
	label.text = Strings.text(Strings.LOAD_ERROR)
	layer.add_child(label)
	for diagnostic: String in errors:
		push_error(diagnostic)


func _map_viewport() -> Vector2:
	var size: Vector2 = get_viewport_rect().size
	return Vector2(maxf(size.x - presentation.layout["panel_width"], 1.0), maxf(size.y - presentation.layout["header_height"], 1.0))


func _resized() -> void:
	if geometry.viewport_size == _map_viewport():
		return
	geometry.viewport_size = _map_viewport()
	geometry.constrain()
	queue_redraw()


func _process(delta: float) -> void:
	if geometry == null or _stats_screen.visible:
		return
	_advance_demolish_hold(delta)
	var direction: Vector2 = Vector2.ZERO
	var zoom_factor: float = 1.0
	# Poll only camera keys, the stick and the triggers; commands use unhandled events so UI can consume them.
	if get_viewport().gui_get_focus_owner() == null:
		direction.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		direction.y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		direction += Input.get_vector(&"map_pan_left", &"map_pan_right", &"map_pan_up", &"map_pan_down")
		# A trigger zooms one step per pull, like a key press.
		if Input.is_action_just_pressed(&"map_zoom_in"):
			zoom_factor *= presentation.camera["zoom_step"]
		if Input.is_action_just_pressed(&"map_zoom_out"):
			zoom_factor /= presentation.camera["zoom_step"]
	_move_camera(direction.limit_length(1.0), zoom_factor, delta)


# Pans by a direction of length up to 1 and multiplies the zoom by a factor (above 1 zooms in).
func _move_camera(direction: Vector2, zoom_factor: float, delta: float) -> void:
	var previous_center: Vector2 = geometry.center
	var previous_zoom: float = geometry.zoom
	geometry.zoom *= zoom_factor
	geometry.center += direction * presentation.camera["pan_speed"] * delta / geometry.zoom
	geometry.constrain()
	if geometry.center != previous_center or geometry.zoom != previous_zoom:
		queue_redraw()


# Sees every event, even those the panel takes, so the help follows whatever the player last touched.
func _input(event: InputEvent) -> void:
	if _help == null or session == null:
		return
	var gamepad: bool = _gamepad
	if GamepadBindings.is_gamepad(event):
		gamepad = true
	elif (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		gamepad = false
	if gamepad != _gamepad:
		_gamepad = gamepad
		_update_help()
		_update_mode()


func _unhandled_input(event: InputEvent) -> void:
	if geometry == null:
		return
	if _stats_screen.visible:
		_stats_screen.handle(event)
		get_viewport().set_input_as_handled()
		return
	var previous_center: Vector2 = geometry.center
	var previous_zoom: float = geometry.zoom
	var previous_selection: Vector2i = geometry.selected
	var previous_type: StringName = _building_type
	var header_offset: Vector2 = Vector2(0, presentation.layout["header_height"])
	var zoom_step: float = presentation.camera["zoom_step"]
	if GamepadBindings.is_gamepad(event):
		_gamepad_command(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode >= KEY_1 and event.keycode <= KEY_1 + TYPES.size() - 1) or event.keycode == ROAD_KEY:
			var type: StringName = ROAD if event.keycode == ROAD_KEY else TYPES[event.keycode - KEY_1]
			var reason_id: StringName = session.get_building_unavailable_reason(type)
			var reason: String = presentation.building_unavailable_reason(reason_id)
			_building_type = type if reason.is_empty() else &""
			if not reason.is_empty():
				_show_result(false, reason_id)
		elif event.keycode == SERVICE_KEY:
			_next_service()
		elif event.keycode == KEY_ESCAPE:
			_building_type = &""
		elif event.keycode == KEY_DELETE and geometry.selected != Vector2i(-1, -1):
			_submit(DemolishCommand.new(geometry.selected))
		elif event.keycode == REPAIR_KEY and geometry.selected != Vector2i(-1, -1):
			_submit(_action_command(geometry.selected))
		elif event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
			_zoom_by(1.0 / zoom_step if event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] else zoom_step)
	if event is InputEventMouseButton:
		# Clicking the map takes keyboard focus back from HUD fields such as the tax box, and leaves the panel.
		if event.pressed:
			get_viewport().gui_release_focus()
			_stats_panel.leave_focus()
		if event.pressed and event.position.y >= header_offset.y:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_select_at(event.position)
				if _building_type != &"":
					_submit(_place_command(_cell_at(event.position)))
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				_zoom_by(zoom_step if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_step)
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		_drag_camera(event.relative)
	geometry.constrain()
	if geometry.selected != previous_selection or _building_type != previous_type:
		_update_mode()
	if geometry.center != previous_center or geometry.zoom != previous_zoom or geometry.selected != previous_selection or _building_type != previous_type:
		queue_redraw()


# The cell under a point of the viewport, inside the map or not: the simulation says why a build there fails.
func _cell_at(screen: Vector2) -> Vector2i:
	return geometry.screen_to_cell(screen - Vector2(0, presentation.layout["header_height"]))


# Selects the cell under a point of the viewport, or nothing outside the map.
func _select_at(screen: Vector2) -> void:
	geometry.select_cell(screen - Vector2(0, presentation.layout["header_height"]))


func _zoom_by(factor: float) -> void:
	geometry.zoom *= factor


# Dragging with the middle button moves the map under the mouse.
func _drag_camera(relative: Vector2) -> void:
	geometry.center -= relative / geometry.zoom


# The gamepad cursor moves one cell and the camera follows it out of view.
func _move_cursor(offset: Vector2i) -> void:
	geometry.move_selection(offset)
	geometry.follow_selection()


# Gamepad presses on the map (issue #68). While the panel has the focus only Menu, View and B reach here: the d-pad
# and A belong to the panel then.
func _gamepad_command(event: InputEvent) -> void:
	# A pressed button that hides itself (restart, the victory notice) drops the focus; the panel takes it back.
	if _stats_panel.is_focused() and get_viewport().gui_get_focus_owner() == null:
		_stats_panel.enter_focus()
	if event.is_action_pressed(&"gamepad_panel"):
		if _stats_panel.is_focused():
			_stats_panel.leave_focus()
		else:
			_stats_panel.enter_focus()
	elif event.is_action_pressed(&"gamepad_pause"):
		_stats_panel.toggle_pause()
	elif _stats_panel.is_focused():
		if event.is_action_pressed(&"ui_cancel"):
			_stats_panel.leave_focus()
	elif event.is_action_pressed(&"ui_cancel"):
		_building_type = &""
	elif event.is_action_pressed(&"map_build_next") or event.is_action_pressed(&"map_build_prev"):
		_cycle_building(1 if event.is_action_pressed(&"map_build_next") else -1)
	elif event.is_action_pressed(&"map_place") and _building_type != &"" and geometry.selected != Vector2i(-1, -1):
		_submit(_place_command(geometry.selected))
	elif event.is_action_pressed(&"map_repair") and geometry.selected != Vector2i(-1, -1):
		_submit(_action_command(geometry.selected))
	else:
		for action: StringName in GamepadBindings.CURSOR:
			if event.is_action_pressed(action):
				_move_cursor(GamepadBindings.CURSOR[action])


# X demolishes only after it has been held (issue #164). Frame time, so it works while the sim clock is paused.
# Releasing, moving the cell cursor, or entering the panel cancels this press; it does not start again until X is
# released. Finishing the hold submits one command.
func _advance_demolish_hold(delta: float) -> void:
	var down: bool = Input.is_action_pressed(&"map_demolish")
	if not down:
		_end_demolish_hold(true)
		return
	if get_viewport().gui_get_focus_owner() != null or (_stats_panel != null and _stats_panel.is_focused()):
		_end_demolish_hold(false)
		_demolish_was_down = true
		return
	if not _demolish_was_down:
		_demolish_was_down = true
		if geometry.selected == Vector2i(-1, -1):
			return
		_demolish_holding = true
		_demolish_fired = false
		_demolish_elapsed = 0.0
		_demolish_cell = geometry.selected
	if not _demolish_holding or _demolish_fired:
		return
	if geometry.selected != _demolish_cell:
		_end_demolish_hold(false)
		return
	var seconds: float = presentation.input["demolish_hold_seconds"]
	_demolish_elapsed += delta
	if _demolish_elapsed >= seconds:
		var cell: Vector2i = _demolish_cell
		_demolish_fired = true
		_demolish_holding = false
		_demolish_elapsed = 0.0
		_set_demolish_progress(0.0)
		_submit(DemolishCommand.new(cell))
		return
	_set_demolish_progress(_demolish_elapsed / seconds)


func _end_demolish_hold(released: bool) -> void:
	_demolish_holding = false
	_demolish_fired = false
	_demolish_elapsed = 0.0
	if released:
		_demolish_was_down = false
	_set_demolish_progress(0.0)


func _set_demolish_progress(progress: float) -> void:
	if is_equal_approx(_demolish_progress, progress):
		return
	_demolish_progress = progress
	queue_redraw()


# Half a cell, minus the inset already in data. The 0.5 is the centre of the square, not the hold time.
func _draw_demolish_ring(cell_size: float) -> void:
	if _demolish_progress <= 0.0:
		return
	var center: Vector2 = (Vector2(_demolish_cell) + Vector2.ONE * 0.5) * cell_size
	var radius: float = cell_size * 0.5 - presentation.layout["building_inset"]
	var start: float = -PI * 0.5
	draw_arc(center, radius, start, start + TAU * _demolish_progress, DEMOLISH_RING_POINTS, presentation.ui_colors["selection"], presentation.layout["selection_width"])


# Selecting, then every building that can be built now and the street; the help already says why the others cannot.
func _cycle_building(step: int) -> void:
	var choices: Array[StringName] = [&""]
	for type: StringName in TYPES + [ROAD]:
		if session.get_building_unavailable_reason(type) == &"":
			choices.append(type)
	_building_type = choices[posmod(maxi(choices.find(_building_type), 0) + step, choices.size())]


# The service buildings of the data, safety first, then health and order.
func _service_types() -> Array[StringName]:
	var found: Array[StringName] = []
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		for definition: BuildingDef in session.context.buildings.values():
			if ServiceSystem.SERVICE_TAG in definition.tags and definition.service_attribute == attribute:
				found.append(definition.id)
	return found


# Key 0: the service after the one picked, the first one otherwise. One that cannot be built says why, like 1 to 8.
func _next_service() -> void:
	var services: Array[StringName] = _service_types()
	if services.is_empty():
		return
	var next: StringName = services[(services.find(_building_type) + 1) % services.size()]
	var reason_id: StringName = session.get_building_unavailable_reason(next)
	_building_type = next if reason_id == &"" else &""
	if reason_id != &"":
		_show_result(false, reason_id)


func _place_command(cell: Vector2i) -> SimulationCommand:
	if _building_type == ROAD:
		return BuildRoadCommand.new(session.context, cell)
	return BuildCommand.new(session.context, _building_type, cell)


# R / Y disinfect a house in a crisis (issue #222) and repair a damaged wharf anywhere else.
func _action_command(cell: Vector2i) -> SimulationCommand:
	if not _crisis_house_at(cell).is_empty():
		return DisinfectCommand.new(cell)
	return _repair_command(cell)


# The locked house of the snapshot whose footprint covers the cell, or {} when none does.
func _crisis_house_at(cell: Vector2i) -> Dictionary:
	for house: Dictionary in _snapshot["crisis"]["houses"]:
		if session.context.area_of(house).has_point(cell):
			return house
	return {}


# Bottom left of the map, as wide as the panel. Its button never takes the focus, so the gamepad keeps the map.
func _crisis_tooltip() -> PanelContainer:
	var tip: PanelContainer = PanelContainer.new()
	tip.name = "CrisisTooltip"
	tip.visible = false
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tip.offset_left = presentation.layout["help_x"]
	tip.offset_bottom = -presentation.layout["help_x"]
	tip.custom_minimum_size.x = presentation.layout["panel_width"]
	var rows: VBoxContainer = VBoxContainer.new()
	tip.add_child(rows)
	_crisis_text = Label.new()
	_crisis_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_crisis_text)
	_crisis_button = Button.new()
	_crisis_button.focus_mode = Control.FOCUS_NONE
	_crisis_button.pressed.connect(func() -> void: _submit(DisinfectCommand.new(geometry.selected)))
	rows.add_child(_crisis_button)
	return tip


# Why the house is locked and the time left; for a sick one also the price and length of a disinfection, why it
# cannot start if it cannot, and the button (D-108). Chronicler's note closes it.
func _update_crisis_tip() -> void:
	var house: Dictionary = _crisis_house_at(geometry.selected)
	_crisis_tip.visible = not house.is_empty()
	if house.is_empty():
		return
	var sick: bool = house["lock"] == CrisisSystem.HOUSE_SICK
	var lines: Array[String] = [Strings.reason(house["lock"])]
	if sick:
		var crisis: Dictionary = _snapshot["crisis"]
		lines.append(Strings.text(Strings.CRISIS_DISINFECTION) % [Strings.money(crisis["cost"]), crisis["duration_seconds"]])
	if int(house["seconds_left"]) > 0:
		lines.append(Strings.text(Strings.CRISIS_SECONDS_LEFT) % house["seconds_left"])
	if sick and house["disinfect"] != &"":
		lines.append(Strings.reason(house["disinfect"]))
	var note: String = _catalog.crisis_texts.get(CrisisSystem.HEALTH, {}).get("tooltip", "")
	if not note.is_empty():
		lines.append(note)
	_crisis_text.text = "\n".join(lines)
	_crisis_button.visible = sick
	_crisis_button.disabled = house["disinfect"] != &""
	_crisis_button.text = Strings.text(Strings.CRISIS_DISINFECT_GAMEPAD if _gamepad else Strings.CRISIS_DISINFECT)


# Bottom left, beside the crisis tooltip so a house in a crisis shows both.
func _service_tooltip() -> PanelContainer:
	var tip: PanelContainer = PanelContainer.new()
	tip.name = "ServiceTooltip"
	tip.visible = false
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tip.offset_left = presentation.layout["help_x"] * 2.0 + presentation.layout["panel_width"]
	tip.offset_bottom = -presentation.layout["help_x"]
	tip.custom_minimum_size.x = presentation.layout["panel_width"]
	var rows: VBoxContainer = VBoxContainer.new()
	tip.add_child(rows)
	_service_title = Label.new()
	_service_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_service_title)
	_service_bar = ProgressBar.new()
	_service_bar.show_percentage = false
	_service_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_service_bar)
	_service_text = Label.new()
	rows.add_child(_service_text)
	return tip


# The scenario named by `--scenario=<id>` among the user arguments, when data/scenarios has it; `fallback` otherwise.
static func launch_scenario(catalog: DataCatalog, fallback: StringName,
		user_args: PackedStringArray = OS.get_cmdline_user_args()) -> StringName:
	for argument: String in user_args:
		if argument.begins_with(SCENARIO_FLAG) and catalog.scenarios.has(StringName(argument.trim_prefix(SCENARIO_FLAG))):
			return StringName(argument.trim_prefix(SCENARIO_FLAG))
	return fallback


# A service: its name and attribute, the bar and the figures of its availability. A house: its district and the
# district's attributes, and with the incidents on its pressure by attribute and the warning (issue #87, D-119).
func _update_service_tip() -> void:
	var service: Dictionary = _service_entry("buildings", geometry.selected)
	var house: Dictionary = _service_entry("houses", geometry.selected)
	_service_tip.visible = not service.is_empty() or not house.is_empty()
	_service_bar.visible = not service.is_empty()
	if not service.is_empty():
		var attribute: StringName = StringName(service["attribute"])
		_service_title.text = "%s %s · %s" % [Strings.text(Strings.SERVICE_ICONS[attribute]),
			presentation.labels[StringName(service["definition_id"])], Strings.text(Strings.SERVICE_ATTRIBUTES[attribute])]
		_service_bar.max_value = float(service["availability_max"])
		_service_bar.value = float(service["availability"])
		_service_text.text = Strings.text(Strings.SERVICE_AVAILABILITY) % [roundi(float(service["availability"])),
			roundi(float(service["availability_max"]))]
	elif not house.is_empty():
		var district: StringName = StringName(house["district"])
		var district_name: String = session.context.map.district_names.get(district, "")
		_service_title.text = Strings.text(Strings.SERVICE_DISTRICT) % district_name if not district_name.is_empty() \
			else Strings.text(Strings.SERVICE_WHOLE_CITY)
		var values: Array[String] = []
		for attribute: StringName in ServiceSystem.ATTRIBUTES:
			values.append(Strings.text(Strings.SERVICE_VALUE) % [Strings.text(Strings.SERVICE_ATTRIBUTES[attribute]),
				roundi(float(_snapshot["services"]["districts"][district][attribute]))])
		_service_text.text = " · ".join(values)
		if _snapshot["incidents"]["enabled"]:
			_service_text.text += "\n" + _pressure_text(district)


# The district's pressure by attribute, then the attributes it warns about, if any.
func _pressure_text(district: StringName) -> String:
	var values: Array[String] = []
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		values.append(Strings.text(Strings.SERVICE_VALUE) % [Strings.text(Strings.SERVICE_ATTRIBUTES[attribute]),
			roundi(float(_snapshot["incidents"]["districts"][district][attribute]["pressure"]))])
	var text: String = Strings.text(Strings.INCIDENT_PRESSURE) % " · ".join(values)
	var warned: Array[String] = []
	for attribute: StringName in _warnings(district):
		warned.append(Strings.text(Strings.SERVICE_ATTRIBUTES[attribute]))
	if not warned.is_empty():
		text += "\n" + Strings.text(Strings.INCIDENT_WARNING) % ", ".join(warned)
	return text


# The attributes whose pressure in the district has reached its warning threshold; none with the incidents off.
func _warnings(district: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	if not _snapshot["incidents"]["enabled"]:
		return found
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		if _snapshot["incidents"]["districts"][district][attribute]["warning"]:
			found.append(attribute)
	return found


# The entry of the services snapshot whose footprint covers the cell, or {} when none does.
func _service_entry(list: String, cell: Vector2i) -> Dictionary:
	for entry: Dictionary in _snapshot["services"][list]:
		if session.context.area_of(entry).has_point(cell):
			return entry
	return {}


# Any cell of a damaged wharf repairs it. Elsewhere the command goes as it is and the simulation says why it cannot.
func _repair_command(cell: Vector2i) -> SimulationCommand:
	var wharf: Dictionary = _damaged_wharf_at(cell)
	return RepairWharfCommand.new(RoadNetwork.cell_of(wharf) if not wharf.is_empty() else cell)


# The repairable damaged wharf of the snapshot whose footprint covers the cell, or {} when none does.
func _damaged_wharf_at(cell: Vector2i) -> Dictionary:
	for wharf: Dictionary in _snapshot["repair"]["wharves"]:
		if _damaged_wharf_area(wharf).has_point(cell):
			return wharf
	return {}


func _damaged_wharf_area(wharf: Dictionary) -> Rect2i:
	return session.context.area_of({"definition_id": RepairWharfCommand.WHARF, "cell": wharf["cell"]})


func _submit(command: SimulationCommand) -> void:
	_show_pending()
	session.submit_command(command)


func _command_resolved(accepted: bool, reason: StringName) -> void:
	_show_result(accepted, reason)


func _show_pending() -> void:
	_status_pending = true
	_status_has_result = false
	_status.text = Strings.text(Strings.PENDING)


func _show_result(accepted: bool, reason: StringName) -> void:
	_status_pending = false
	_status_has_result = true
	_status_accepted = accepted
	_status_reason = reason
	_status.text = Strings.command_result(accepted, reason)


func _clear_status() -> void:
	_status_pending = false
	_status_has_result = false
	if _status != null:
		_status.text = ""


func _apply_status() -> void:
	if _status_pending:
		_status.text = Strings.text(Strings.PENDING)
	elif _status_has_result:
		_status.text = Strings.command_result(_status_accepted, _status_reason)


# The panel gives up the gamepad focus: the screen takes the shoulders and B until it closes.
func _open_stats() -> void:
	get_viewport().gui_release_focus()
	_stats_panel.leave_focus()
	_stats_screen.open()


func _snapshot_received(snapshot: Dictionary) -> void:
	if snapshot == _snapshot:
		return
	_snapshot = snapshot
	_stats_panel.update_snapshot(snapshot)
	_archive_panel.update_snapshot(snapshot)
	# A repair or a new wharf on the ruin changes what the selected cell offers.
	_update_mode()
	queue_redraw()


# A new game leaves a save's mods (issue #136).
func _restart_session() -> void:
	if session.mods_from_save and _load_player_mods():
		_restart_on(session.difficulty, _catalog)
	else:
		session.restart()
	_reset_view()


func _start_on_difficulty(preset_id: StringName) -> void:
	var catalog: DataCatalog = null
	if session.mods_from_save and _load_player_mods():
		catalog = _catalog
	_restart_on(preset_id, catalog)
	_reset_view()


# The presets were validated when data/ loaded, so resolving one here cannot fail. `catalog` is data loaded again.
func _restart_on(preset_id: StringName, catalog: DataCatalog) -> void:
	var layers: DataLayers = DataLayers.resolve(_catalog, preset_id)
	session.restart_with(Params.new(_catalog, _catalog.roles[&"neutral_administrator"], layers.modifiers), preset_id,
		catalog)


func _use_mods(loaded: DataLoadResult, from_save: bool) -> void:
	_catalog = loaded.catalog
	session.mods = loaded.mods
	session.mod_conflicts = loaded.mod_conflicts
	session.mod_fingerprints = loaded.mod_fingerprints
	session.mods_from_save = from_save


# Back to the player's own mods after a save's (issue #136): load_order.json was never touched, so it loads as it is.
# If it no longer validates, the game stays on the save's mods and the mods menu says why.
func _load_player_mods() -> bool:
	var loaded: DataLoadResult = _load_catalog()
	if not loaded.is_ok():
		_stats_panel.show_mod_error("\n".join(loaded.errors))
		return false
	_use_mods(loaded, false)
	_update_help()
	return true


# The mods menu's new order (D-065): saved to load_order.json, then data/ and the mods load again and a new game
# starts on the same difficulty. If the new order does not validate, the old list goes back and the game goes on.
func _reorder_mods(order: Array[StringName]) -> void:
	var previous: Array[StringName] = session.mods.duplicate()
	var saved: Error = ModLayer.save_load_order(mods_root, order)
	if saved != OK:
		_stats_panel.show_mod_error(error_string(saved))
		return
	var loaded: DataLoadResult = _load_catalog()
	if not loaded.is_ok():
		ModLayer.save_load_order(mods_root, previous)
		_stats_panel.show_mod_error("
".join(loaded.errors))
		return
	_use_mods(loaded, false)
	var layers: DataLayers = DataLayers.resolve(_catalog, session.difficulty)
	session.restart_with_catalog(_catalog, Params.new(_catalog, _catalog.roles[&"neutral_administrator"], layers.modifiers))
	_update_help()
	_reset_view()


# Saves the state at the end of the last tick (issue #57); orders still queued stay in this game, not in the file.
func _save_game() -> void:
	var path: String = SaveFile.write_manual(saves_root, SaveFile.build(session))
	var message: StringName = Strings.SAVED_WITHOUT_QUEUE if session.simulation.has_queued_commands() else Strings.SAVED
	_stats_panel.show_saves(SaveFile.list(saves_root), Strings.text(Strings.SAVE_WRITE_ERROR if path.is_empty() else message))


# A save loads on the difficulty it was played on; a file from another version is refused and the current game goes
# on. One played with other mods shows them and offers to load with its own, unless one is missing or changed.
func _load_game(path: String) -> void:
	var result: Dictionary = SaveFile.read(path)
	var saved: Dictionary = result["data"]
	if result["reason"] == &"":
		result = SaveFile.check_compatible(saved, session, _catalog)
	if result["reason"] == SaveFile.OTHER_MODS:
		result = SaveFile.mods_offer(saved, ModLayer.installed(mods_root))
		if result["reason"] == &"":
			_stats_panel.show_saves(SaveFile.list(saves_root), Strings.save_mods_differ(saved["mods"], session.mods), path)
			return
	if result["reason"] != &"":
		_stats_panel.show_saves(SaveFile.list(saves_root), Strings.save_refusal(result["reason"], result["args"]))
		return
	_load_checked(saved, null)


# The player accepted the save's mods (issue #136, D-117): data/ loads again with exactly those, in the save's order,
# for this session only. load_order.json is not written, so the next new game or start brings the player's back.
func _load_with_save_mods(path: String) -> void:
	var result: Dictionary = SaveFile.read(path)
	if result["reason"] == &"":
		result = SaveFile.mods_offer(result["data"], ModLayer.installed(mods_root))
	if result["reason"] != &"":
		_stats_panel.show_saves(SaveFile.list(saves_root), Strings.save_refusal(result["reason"], result["args"]))
		return
	var save_mods: Array[StringName] = []
	save_mods.assign(result["data"]["mods"].map(func(mod: Variant) -> StringName: return StringName(mod)))
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", DataLoader.DEFAULT_ERA, mods_root, save_mods)
	if not loaded.is_ok():
		_stats_panel.show_saves(SaveFile.list(saves_root), Strings.text(Strings.MODS_ERROR) % "\n".join(loaded.errors))
		return
	_use_mods(loaded, true)
	_update_help()
	_load_checked(result["data"], _catalog)


# `catalog` is the data loaded with the save's mods, or null when the save runs on the current one.
func _load_checked(saved: Dictionary, catalog: DataCatalog) -> void:
	var layers: DataLayers = DataLayers.resolve(_catalog, StringName(saved["difficulty"]))
	session.load_save(saved, Params.new(_catalog, _catalog.roles[&"neutral_administrator"], layers.modifiers), catalog)
	_reset_view()
	_stats_panel.show_saves(SaveFile.list(saves_root), Strings.text(Strings.SAVE_LOADED))


func _reset_view() -> void:
	_autosave.reset()
	clock.simulation = session.simulation
	clock.reset()
	_building_type = &""
	geometry.selected = Vector2i(-1, -1)
	_clear_status()
	_snapshot = session.get_snapshot()
	_stats_panel.update_snapshot(_snapshot)
	_archive_panel.update_snapshot(_snapshot)
	_update_mode()
	queue_redraw()


func _update_mode() -> void:
	var label: String = Strings.text(Strings.ROAD) if _building_type == ROAD else presentation.labels.get(_building_type, Strings.text(Strings.SELECT))
	var parts: Array[String] = [Strings.text(Strings.MODE) % [label, geometry.selected]]
	var style: StringName = session.context.map.lot_styles.get(geometry.selected, &"")
	if style != &"":
		parts.append(presentation.lot_labels[style])
	var wharf: Dictionary = _damaged_wharf_at(geometry.selected)
	if not wharf.is_empty():
		parts.append(Strings.text(Strings.REPAIR_HINT_GAMEPAD if _gamepad else Strings.REPAIR_HINT) % Strings.money(wharf["cost"]))
	_mode.text = " · ".join(parts)
	_update_crisis_tip()
	_update_service_tip()


func _draw() -> void:
	if geometry == null:
		return
	var cell_size: float = presentation.layout["cell_size"]
	draw_set_transform(Vector2(0, presentation.layout["header_height"]) + geometry.viewport_size / 2.0 - geometry.center * geometry.zoom, 0.0, Vector2.ONE * geometry.zoom)
	var map: MapDef = session.context.map
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			var kind: String = geometry.terrain_at(cell, map)
			# Free land shows its 1870 lot (issue #178); the other kinds keep their terrain colour.
			var color: Color = presentation.lot_colors[map.lot_styles[cell]] if kind == "land" and map.lot_styles.has(cell) else presentation.terrain[kind]
			draw_rect(Rect2(Vector2(cell) * cell_size, Vector2.ONE * cell_size).grow(-presentation.layout["grid_inset"]), color)
	# The player's streets come from the state, not the map, in their own colour: unlike the historic ones they can be
	# demolished.
	for road: Array in _snapshot["distance"]["player_roads"]:
		draw_rect(geometry.area_rect(session.context.road_area({"cell": road})).grow(-presentation.layout["grid_inset"]), presentation.terrain["player_road"])
	# Each building over its whole footprint (issue #186, D-086).
	for building: Dictionary in _snapshot["economy"]["buildings"]:
		var id: StringName = StringName(building["definition_id"])
		var rect: Rect2 = geometry.area_rect(session.context.area_of(building)).grow(-presentation.layout["building_inset"])
		draw_rect(rect, presentation.colors[id])
		_draw_label(rect.get_center(), presentation.labels[id])
	# A house in a crisis carries a mark in its corner (issue #222, D-108): filled while it has sick people, an outline in
	# quarantine. Not a red cross: the building is locked, not the people (D-104).
	for house: Dictionary in _snapshot["crisis"]["houses"]:
		var rect: Rect2 = geometry.area_rect(session.context.area_of(house)).grow(-presentation.layout["building_inset"])
		var side: float = presentation.layout["font_size"]
		var mark: Rect2 = Rect2(rect.end.x - side, rect.position.y, side, side)
		if house["lock"] == CrisisSystem.HOUSE_SICK:
			draw_rect(mark, presentation.ui_colors["inspection"])
		else:
			draw_rect(mark, presentation.ui_colors["inspection"], false, presentation.layout["selection_width"])
	# A service carries the icon of its attribute in its top-left corner (issue #87, D-118).
	for service: Dictionary in _snapshot["services"]["buildings"]:
		var rect: Rect2 = geometry.area_rect(session.context.area_of(service)).grow(-presentation.layout["building_inset"])
		var side: float = presentation.layout["font_size"]
		var icon: Rect2 = Rect2(rect.position, Vector2.ONE * side)
		var attribute: StringName = StringName(service["attribute"])
		draw_rect(icon, presentation.service_colors[attribute])
		_draw_label(icon.get_center(), Strings.text(Strings.SERVICE_ICONS[attribute]))
	# Every house of a district under pressure carries the warning in its bottom-left corner, in the colour of the
	# first attribute it warns about (issue #87, D-119).
	for house: Dictionary in _snapshot["services"]["houses"]:
		var warned: Array[StringName] = _warnings(StringName(house["district"]))
		if warned.is_empty():
			continue
		var rect: Rect2 = geometry.area_rect(session.context.area_of(house)).grow(-presentation.layout["building_inset"])
		var side: float = presentation.layout["font_size"]
		var icon: Rect2 = Rect2(rect.position.x, rect.end.y - side, side, side)
		draw_rect(icon, presentation.service_colors[warned[0]])
		_draw_label(icon.get_center(), Strings.text(Strings.INCIDENT_ICON))
	# A damaged wharf that can be repaired, with what repairing costs (issue #178, D-083).
	for wharf: Dictionary in _snapshot["repair"]["wharves"]:
		var rect: Rect2 = geometry.area_rect(_damaged_wharf_area(wharf)).grow(-presentation.layout["building_inset"])
		draw_rect(rect, presentation.ui_colors["damaged_wharf"])
		var line: Vector2 = Vector2(0.0, presentation.layout["font_size"] / 2.0)
		_draw_label(rect.get_center() - line, Strings.text(Strings.DAMAGED_WHARF))
		# Only the price fits the footprint; the mode line says which button repairs.
		_draw_label(rect.get_center() + line, Strings.money(wharf["cost"]))
	if geometry.selected != Vector2i(-1, -1):
		draw_rect(Rect2(Vector2(geometry.selected) * cell_size, Vector2.ONE * cell_size).grow(-presentation.layout["selection_inset"]), presentation.ui_colors["selection"], false, presentation.layout["selection_width"])
	_draw_demolish_ring(cell_size)


func _draw_label(center: Vector2, text: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = int(presentation.layout["font_size"])
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center + Vector2(-width / 2.0, presentation.layout["label_offset_y"]), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, presentation.ui_colors["label"])
