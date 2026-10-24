extends GutTest

# The fog of the 3D greybox (issue #65, D-028): it opens when the camera comes close and closes when it pulls back;
# volumetric in high quality (Forward+), a plain depth fog in low. It never hides game information (Cristian,
# 2026-10-11): the point in view keeps at least half its light, and marks, selection and labels are drawn outside it.

const ROOT: String = "user://test_city_fog"
const HOUSE: Vector2i = Vector2i(12, 22)

var _style: CityPresentation


func before_all() -> void:
	_style = CityPresentation.new()
	_style.load_data([])


func after_each() -> void:
	Strings.use_default_locale()


func _camera() -> CityCamera:
	return CityCamera.new(Vector2i(48, 80), 25.0, _style.camera)


func _at(camera: CityCamera, distance: float) -> CityCamera:
	camera.target_distance = distance
	camera.distance = distance
	return camera


func _raw() -> Dictionary:
	var json: JSON = JSON.new()
	json.parse(FileAccess.get_file_as_string(CityPresentation.PATH))
	return json.data


func _view() -> CityView:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/city.tscn") as PackedScene).instantiate()
	var view: CityView = scene.get_node("Map") as CityView
	view.mods_root = ROOT
	view.saves_root = ROOT
	viewport.add_child(scene)
	view.clock.speed = 0
	await get_tree().process_frame
	return view


func test_the_data_is_valid() -> void:
	assert_eq(_style.errors, [] as Array[String])


func test_the_fog_opens_as_the_camera_comes_close() -> void:
	var camera: CityCamera = _camera()
	var near: float = CityFog.focus_visibility(_style.fog, _at(camera, camera.min_distance))
	var far: float = CityFog.focus_visibility(_style.fog, _at(camera, camera.max_distance))
	assert_gt(near, far, "More of the city shows close up")
	var near_depth: float = CityFog.depth_opacity(_style.fog, _at(camera, camera.min_distance))
	assert_lt(near_depth, CityFog.depth_opacity(_style.fog, _at(camera, camera.max_distance)), "The low quality fog too")


func test_the_point_in_view_always_keeps_at_least_half_its_light() -> void:
	var camera: CityCamera = _camera()
	var environment: Environment = Environment.new()
	var distance: float = camera.min_distance
	while distance <= camera.max_distance:
		_at(camera, distance)
		CityFog.apply(environment, _style.fog, _style.fog_color, camera, CityFog.HIGH)
		var light: float = exp(-environment.volumetric_fog_density * distance)
		assert_gte(light, CityFog.MIN_FOCUS_VISIBILITY, "At %d m" % distance)
		CityFog.apply(environment, _style.fog, _style.fog_color, camera, CityFog.LOW)
		assert_eq(environment.fog_depth_begin, distance, "The depth fog starts behind the point in view")
		assert_lte(environment.fog_density, 1.0 - CityFog.MIN_FOCUS_VISIBILITY)
		distance *= 1.5


func test_high_is_volumetric_and_low_is_a_depth_fog() -> void:
	var camera: CityCamera = _camera()
	var environment: Environment = Environment.new()
	CityFog.apply(environment, _style.fog, _style.fog_color, camera, CityFog.HIGH)
	assert_true(environment.volumetric_fog_enabled)
	assert_false(environment.fog_enabled)
	assert_gt(environment.volumetric_fog_length, camera.distance, "It reaches past the point in view")
	CityFog.apply(environment, _style.fog, _style.fog_color, camera, CityFog.LOW)
	assert_false(environment.volumetric_fog_enabled, "No volumetric fog in low quality")
	assert_true(environment.fog_enabled)
	assert_eq(environment.fog_mode, Environment.FOG_MODE_DEPTH)


func test_data_that_would_hide_the_game_or_thicken_up_close_is_refused() -> void:
	var raw: Dictionary = _raw()
	raw["fog"]["focus_visibility_far"] = 0.3
	var style: CityPresentation = CityPresentation.new()
	style.validate(raw, [])
	assert_eq(style.errors.size(), 1, str(style.errors))
	raw = _raw()
	raw["fog"]["depth_opacity_near"] = 0.45
	raw["fog"]["depth_opacity_far"] = 0.2
	style.validate(raw, [])
	assert_eq(style.errors.size(), 1, str(style.errors))
	raw = _raw()
	raw["graphics"]["quality"] = "ultra"
	style.validate(raw, [])
	assert_eq(style.errors.size(), 1, str(style.errors))


func test_marks_selection_and_labels_stay_out_of_the_fog() -> void:
	var view: CityView = await _view()
	view.session.submit_command(BuildCommand.new(view.session.context, &"housing", HOUSE))
	view.session.simulation.tick()
	assert_true(view.session.simulation.mark_house_sick(HOUSE))
	view.session.publish_tick()
	view.geometry.selected = HOUSE
	await get_tree().process_frame
	var marks: Array[Node] = (view.get("_marks") as Node3D).get_children()
	assert_eq(marks.size(), 1, "The sick house carries its mark")
	var meshes: Array[Node] = (view.get("_selection") as Node3D).get_children() + marks
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		assert_true((mesh.mesh.surface_get_material(0) as BaseMaterial3D).disable_fog, "%s outside the fog" % node)
	assert_eq(view.find_children("*", "Label3D", true, false).size(), 0, "No label lives in the 3D world")
	var labels: Array = view.get("_label_items")
	assert_eq(labels.size(), 1, "The house's label is drawn in 2D, over the fog")


func test_the_switch_changes_the_quality_on_screen() -> void:
	var view: CityView = await _view()
	var buttons: Dictionary = view.get("_quality_buttons")
	(buttons[CityFog.LOW] as Button).pressed.emit()
	await get_tree().process_frame
	var environment: Environment = view.get("_environment")
	assert_eq(view.quality, CityFog.LOW)
	assert_false(environment.volumetric_fog_enabled)
	assert_true(environment.fog_enabled)
	assert_eq((view.get("_viewport_3d") as SubViewport).msaa_3d, Viewport.MSAA_DISABLED)
	(buttons[CityFog.HIGH] as Button).pressed.emit()
	await get_tree().process_frame
	assert_true(environment.volumetric_fog_enabled)
	assert_true((buttons[CityFog.HIGH] as Button).button_pressed)
