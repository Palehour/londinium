class_name CityView
extends MapView

# The 3D greybox of the full map (issue #65, D-028, D-093): low poly boxes on a 48x80 grid of 25 m cells, under a tilted
# camera that turns freely and zooms from a street to the whole district. Only the drawing and the camera change: the
# commands, the panel and the gamepad are the 2D map's (MapView), so the simulation never sees the difference.

const FULL_MAP: StringName = &"whitechapel_full"
const ROTATE_LEFT_KEY: Key = KEY_Q
const ROTATE_RIGHT_KEY: Key = KEY_E
const NONE: Vector2i = CityCamera.NONE

var style: CityPresentation = CityPresentation.new()
var camera: CityCamera
var _container: SubViewportContainer
var _viewport_3d: SubViewport
var _camera_3d: Camera3D
var _terrain: MultiMeshInstance3D
var _roads: MultiMeshInstance3D
var _boxes: MultiMeshInstance3D
var _roofs: MultiMeshInstance3D
# Crisis marks and damaged wharves, rebuilt with the state; the labels apart, so they hide when zoomed out.
var _marks: Node3D
var _labels: Node3D
var _selection: Node3D
var _selection_cell: Vector2i = NONE
# What the world shows now, to rebuild it only when the buildings, streets, crises or ruins change.
var _drawn: Array = []
# The box around each building and its footprint, so a click on a roof picks that building and not the ground behind.
var _picks: Array[Dictionary] = []
# The instances of each multimesh by node name, as they were filled; the headless renderer of the tests keeps none.
var _items: Dictionary[StringName, Array] = {}


func _init() -> void:
	scenario_id = FULL_MAP


func _load_presentation(building_ids: Array[StringName]) -> void:
	super(building_ids)
	if not presentation.errors.is_empty():
		return
	style.load_data(building_ids)
	presentation.errors.append_array(style.errors)
	if style.errors.is_empty():
		style.apply_palette(presentation)


func _view_ready() -> void:
	var map: MapDef = session.context.map
	camera = CityCamera.new(Vector2i(map.width, map.height), session.cell_size_m(), style.camera)
	_build_world()
	_build_terrain()
	_sync_world(true)


func _update_help() -> void:
	super()
	_help.text += " · " + Strings.text(Strings.HELP_CITY_GAMEPAD if _gamepad else Strings.HELP_CITY)


func _notification(what: int) -> void:
	super(what)
	if what == NOTIFICATION_TRANSLATION_CHANGED and camera != null:
		_sync_world(true)


func _process(delta: float) -> void:
	super(delta)
	if camera == null:
		return
	if get_viewport().gui_get_focus_owner() == null:
		var turn: float = float(Input.is_physical_key_pressed(ROTATE_RIGHT_KEY)) - float(Input.is_physical_key_pressed(ROTATE_LEFT_KEY))
		turn += Input.get_axis(&"map_rotate_left", &"map_rotate_right")
		camera.rotate(clampf(turn, -1.0, 1.0) * deg_to_rad(style.camera["rotate_speed_deg"]) * delta)
	camera.update(delta)
	_camera_3d.transform = camera.camera_transform()
	_sync_world(false)
	_place_selection()
	_labels.visible = camera.distance <= style.marks["label_max_distance_m"]


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if camera == null:
		return
	# Dragging with the right button turns the city, like Anno.
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		camera.rotate(-deg_to_rad(event.relative.x * style.camera["drag_rotate_deg_per_px"]))


func _move_camera(direction: Vector2, zoom_factor: float, delta: float) -> void:
	if camera == null:
		return
	camera.zoom_by(zoom_factor)
	# A share of the distance per second, so the city crosses the screen at the same pace at any zoom.
	camera.pan(direction * style.camera["pan_speed"] * camera.distance * delta)


func _zoom_by(factor: float) -> void:
	camera.zoom_by(factor)


func _drag_camera(relative: Vector2) -> void:
	camera.pan(-relative * camera.metres_per_pixel(_viewport_3d.size.y))


# The building under the point first, then the ground; NONE when the ray misses the ground.
func _cell_at(screen: Vector2) -> Vector2i:
	_camera_3d.transform = camera.camera_transform()
	var point: Vector2 = screen - _container.position
	var origin: Vector3 = _camera_3d.project_ray_origin(point)
	var direction: Vector3 = _camera_3d.project_ray_normal(point)
	var nearest: float = INF
	var cell: Vector2i = NONE
	for pick: Dictionary in _picks:
		var hit: Variant = (pick["box"] as AABB).intersects_ray(origin, direction)
		if hit == null or origin.distance_to(hit) >= nearest:
			continue
		var area: Rect2i = pick["area"]
		nearest = origin.distance_to(hit)
		cell = camera.cell_of(hit).clamp(area.position, area.end - Vector2i.ONE)
	return cell if cell != NONE else camera.ground_cell(origin, direction)


func _select_at(screen: Vector2) -> void:
	var cell: Vector2i = _cell_at(screen)
	geometry.selected = cell if camera.has_cell(cell) else NONE


# The d-pad moves the cursor in screen directions, whatever the rotation; it starts in the middle of the view.
func _move_cursor(offset: Vector2i) -> void:
	var cell: Vector2i = geometry.selected
	if cell == NONE:
		cell = _cell_at(_container.position + _container.size / 2.0)
		if not camera.has_cell(cell):
			cell = camera.cell_of(camera.focus)
	else:
		cell += camera.grid_step(offset)
	var last: Vector2i = Vector2i(camera.map_size / camera.cell_size) - Vector2i.ONE
	geometry.selected = cell.clamp(Vector2i.ZERO, last)
	_follow(geometry.selected)


# Centres the camera on the cell only when it is out of view, so moving inside the view keeps the city still.
func _follow(cell: Vector2i) -> void:
	_camera_3d.transform = camera.camera_transform()
	var point: Vector3 = camera.cell_center(cell)
	if not _camera_3d.is_position_behind(point) and Rect2(Vector2.ZERO, Vector2(_viewport_3d.size)).has_point(_camera_3d.unproject_position(point)):
		return
	camera.focus = point
	camera.constrain()


func _resized() -> void:
	super()
	if _container != null:
		_layout_container()


func _reset_view() -> void:
	super()
	if camera == null:
		return
	# Another mod order can load another map.
	var map: MapDef = session.context.map
	camera = CityCamera.new(Vector2i(map.width, map.height), session.cell_size_m(), style.camera)
	_build_terrain()
	_sync_world(true)


# Only the demolish ring stays in 2D, drawn over the cell where it is on screen.
func _draw() -> void:
	if _demolish_progress <= 0.0 or camera == null:
		return
	var center_3d: Vector3 = camera.cell_center(_demolish_cell)
	var center: Vector2 = _container.position + _camera_3d.unproject_position(center_3d)
	# Half a cell to the side of the centre, the edge of the square.
	var edge: Vector2 = _container.position + _camera_3d.unproject_position(center_3d + camera.screen_right() * camera.cell_size * 0.5)
	var start: float = -PI * 0.5
	draw_arc(center, center.distance_to(edge), start, start + TAU * _demolish_progress, DEMOLISH_RING_POINTS, presentation.ui_colors["selection"], presentation.layout["selection_width"])


func _build_world() -> void:
	_container = SubViewportContainer.new()
	_container.name = "City"
	_container.stretch = true
	# Clicks go on to _unhandled_input, the same path as the 2D map.
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_3d = SubViewport.new()
	_viewport_3d.own_world_3d = true
	# The thin joints between ground slabs shimmer at a distance without it.
	_viewport_3d.msaa_3d = Viewport.MSAA_2X
	_container.add_child(_viewport_3d)
	# Behind this node's own drawing, so the demolish ring of _draw() shows over the city.
	_container.show_behind_parent = true
	add_child(_container)
	move_child(_container, 0)
	_layout_container()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = style.world_colors["background"]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = style.world_colors["ambient"]
	environment.ambient_light_energy = style.world["ambient_energy"]
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	_viewport_3d.add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = style.world_colors["sun"]
	sun.light_energy = style.world["sun_energy"]
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(style.world["sun_pitch_deg"], style.world["sun_yaw_deg"], 0.0)
	_viewport_3d.add_child(sun)
	_camera_3d = Camera3D.new()
	_camera_3d.fov = style.camera["fov_deg"]
	# Far enough to see the whole map from the farthest zoom, past the ground under the horizon.
	_camera_3d.far = style.camera["max_distance_m"] + camera.map_size.length()
	_camera_3d.current = true
	_camera_3d.transform = camera.camera_transform()
	_viewport_3d.add_child(_camera_3d)
	_terrain = _multimesh(BoxMesh.new(), "Terrain")
	_roads = _multimesh(BoxMesh.new(), "Roads")
	_boxes = _multimesh(BoxMesh.new(), "Buildings")
	_roofs = _multimesh(PrismMesh.new(), "Roofs")
	_marks = Node3D.new()
	_marks.name = "Marks"
	_viewport_3d.add_child(_marks)
	_labels = Node3D.new()
	_labels.name = "Labels"
	_viewport_3d.add_child(_labels)
	_selection = _frame(style.selection_color)
	_viewport_3d.add_child(_selection)


func _layout_container() -> void:
	_container.position = Vector2(0, presentation.layout["header_height"])
	_container.size = _map_viewport()


# One draw call for many boxes, each with its own transform and colour.
func _multimesh(mesh: PrimitiveMesh, node_name: String) -> MultiMeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	_viewport_3d.add_child(instance)
	return instance


# The ground: one slab per cell at the height of its kind, with a thin gap so the grid still reads.
func _build_terrain() -> void:
	var map: MapDef = session.context.map
	var slabs: Array[Dictionary] = []
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			var kind: String = geometry.terrain_at(cell, map)
			# Free land shows its 1870 lot, as in 2D (issue #178).
			var color: Color = style.lot_colors[map.lot_styles[cell]] if kind == "land" and map.lot_styles.has(cell) else style.terrain[kind]
			slabs.append(_slab(Rect2(Vector2(cell) * camera.cell_size, Vector2.ONE * camera.cell_size), style.elevation[kind], color))
	_fill(_terrain, slabs)


func _slab(area: Rect2, top: float, color: Color) -> Dictionary:
	var depth: float = style.ground["depth_m"]
	var gap: float = style.ground["gap_m"]
	var size: Vector3 = Vector3(area.size.x - gap, depth, area.size.y - gap)
	var center: Vector3 = Vector3(area.get_center().x, top - depth / 2.0, area.get_center().y)
	return {"transform": Transform3D(Basis.from_scale(size), center), "color": color}


func _fill(instance: MultiMeshInstance3D, items: Array[Dictionary]) -> void:
	_items[instance.name] = items
	var multimesh: MultiMesh = instance.multimesh
	multimesh.instance_count = items.size()
	for index: int in range(items.size()):
		multimesh.set_instance_transform(index, items[index]["transform"])
		multimesh.set_instance_color(index, items[index]["color"])


func _box_item(box: AABB, color: Color) -> Dictionary:
	return {"transform": Transform3D(Basis.from_scale(box.size), box.get_center()), "color": color}


# A gable over the box, its ridge along the longer side. The prism's ridge runs along its own z, so a ridge along x
# turns it a quarter.
func _roof_item(box: AABB, ridge_along_x: bool, color: Color) -> Dictionary:
	var basis: Basis = Basis.from_scale(box.size)
	if ridge_along_x:
		basis = Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3(box.size.z, box.size.y, box.size.x))
	return {"transform": Transform3D(basis, box.get_center()), "color": color}


# What the world draws from the snapshot: only the parts that change its shape, not the per-tick figures.
func _world_signature() -> Array:
	var buildings: Array = []
	for building: Dictionary in _snapshot["economy"]["buildings"]:
		buildings.append([building["definition_id"], building["cell"]])
	var houses: Array = []
	for house: Dictionary in _snapshot["crisis"]["houses"]:
		houses.append([house["cell"], house["lock"]])
	var wharves: Array = []
	for wharf: Dictionary in _snapshot["repair"]["wharves"]:
		wharves.append([wharf["cell"], wharf["cost"]])
	return [buildings, _snapshot["distance"]["player_roads"].duplicate(true), houses, wharves, TranslationServer.get_locale()]


func _sync_world(force: bool) -> void:
	var signature: Array = _world_signature()
	if not force and signature == _drawn:
		return
	_drawn = signature
	for node: Node in _marks.get_children() + _labels.get_children():
		node.free()
	_picks.clear()
	var land: float = style.elevation["land"]
	var roads: Array[Dictionary] = []
	for road: Array in _snapshot["distance"]["player_roads"]:
		var area: Rect2 = _metres(session.context.road_area({"cell": road}))
		roads.append(_slab(area, style.elevation["player_road"], style.terrain["player_road"]))
	_fill(_roads, roads)
	var boxes: Array[Dictionary] = []
	var roofs: Array[Dictionary] = []
	var tops: Dictionary[Vector2i, float] = {}
	for building: Dictionary in _snapshot["economy"]["buildings"]:
		var id: StringName = StringName(building["definition_id"])
		var area: Rect2i = session.context.area_of(building)
		var pieces: Array[Dictionary] = CityLayout.pieces(style.shapes[id], style.filler, style.chimney_side, _metres(area), land, area.position.x * 7 + area.position.y * 13)
		for piece: Dictionary in pieces:
			match piece["kind"]:
				CityLayout.ROOF:
					roofs.append(_roof_item(piece["box"], piece["ridge_along_x"], style.colors[id]))
				CityLayout.FILLER:
					boxes.append(_box_item(piece["box"], style.filler_color))
				CityLayout.CHIMNEY:
					boxes.append(_box_item(piece["box"], style.chimney_color))
				_:
					boxes.append(_box_item(piece["box"], style.colors[id]))
		var bounds: AABB = CityLayout.bounds(pieces)
		_picks.append({"box": bounds, "area": area})
		tops[area.position] = bounds.end.y
		_add_label(_metres(area).get_center(), bounds.end.y, presentation.labels[id])
	for wharf: Dictionary in _snapshot["repair"]["wharves"]:
		var area: Rect2 = _metres(_damaged_wharf_area(wharf))
		var height: float = style.marks["damaged_wharf_height_m"]
		boxes.append(_box_item(AABB(Vector3(area.position.x, land, area.position.y), Vector3(area.size.x, height, area.size.y)), presentation.ui_colors["damaged_wharf"]))
		_add_label(area.get_center(), land + height, "%s\n%s" % [Strings.text(Strings.DAMAGED_WHARF), Strings.money(wharf["cost"])])
	_fill(_boxes, boxes)
	_fill(_roofs, roofs)
	for house: Dictionary in _snapshot["crisis"]["houses"]:
		_add_crisis_mark(session.context.area_of(house), tops.get(RoadNetwork.cell_of(house), land), house["lock"] == CrisisSystem.HOUSE_SICK)


func _metres(area: Rect2i) -> Rect2:
	return Rect2(Vector2(area.position) * camera.cell_size, Vector2(area.size) * camera.cell_size)


func _add_label(ground: Vector2, top: float, text: String) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = style.marks["label_pixel_size"]
	label.font_size = int(style.marks["label_font_size"])
	label.modulate = presentation.ui_colors["label"]
	label.outline_modulate = style.selection_color
	label.position = Vector3(ground.x, top + style.marks["mark_size_m"], ground.y)
	_labels.add_child(label)


# Above the house (D-108): a solid block while it has sick people, a frame in quarantine. Not a red cross: the
# building is locked, not the people (D-104).
func _add_crisis_mark(area: Rect2i, top: float, sick: bool) -> void:
	var size: float = style.marks["mark_size_m"]
	var ground: Vector2 = _metres(area).get_center()
	var color: Color = presentation.ui_colors["inspection"]
	if not sick:
		var frame: Node3D = _frame(color)
		_marks.add_child(frame)
		_place_frame(frame, Rect2(ground - Vector2.ONE * size / 2.0, Vector2.ONE * size), top + size)
		return
	var block: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = _flat_material(color)
	block.mesh = mesh
	block.position = Vector3(ground.x, top + size, ground.y)
	_marks.add_child(block)


# Four bars around a square, drawn through everything so the selection never hides behind a building.
func _frame(color: Color) -> Node3D:
	var frame: Node3D = Node3D.new()
	for side: int in range(4):
		var bar: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.material = _flat_material(color)
		bar.mesh = mesh
		frame.add_child(bar)
	frame.visible = false
	return frame


func _place_frame(frame: Node3D, area: Rect2, height: float) -> void:
	var width: float = style.marks["selection_width_m"]
	var bars: Array[AABB] = [
		AABB(Vector3(area.position.x, height, area.position.y), Vector3(area.size.x, width, width)),
		AABB(Vector3(area.position.x, height, area.end.y - width), Vector3(area.size.x, width, width)),
		AABB(Vector3(area.position.x, height, area.position.y), Vector3(width, width, area.size.y)),
		AABB(Vector3(area.end.x - width, height, area.position.y), Vector3(width, width, area.size.y)),
	]
	for index: int in range(bars.size()):
		var bar: MeshInstance3D = frame.get_child(index) as MeshInstance3D
		(bar.mesh as BoxMesh).size = bars[index].size
		bar.position = bars[index].get_center()
	frame.visible = true


func _place_selection() -> void:
	if geometry.selected == _selection_cell:
		return
	_selection_cell = geometry.selected
	if geometry.selected == NONE:
		_selection.visible = false
		return
	var cell: Vector2 = Vector2(geometry.selected) * camera.cell_size
	_place_frame(_selection, Rect2(cell, Vector2.ONE * camera.cell_size), style.elevation["land"])


func _flat_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = color
	return material
