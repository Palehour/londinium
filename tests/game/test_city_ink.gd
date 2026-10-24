extends GutTest

# The subtle ink pass of the 3D greybox (issue #65, D-028): fine contours, hatching only in deep shadows and paper grain,
# with the cell grid inked on the ground. It never covers game information (Cristian, 2026-10-11): marks and selection
# draw after it, labels are 2D, and the data cannot make the grain or the hatching heavy.

const ROOT: String = "user://test_city_ink"
const HOUSE: Vector2i = Vector2i(12, 22)

var _style: CityPresentation


func before_all() -> void:
	_style = CityPresentation.new()
	_style.load_data([])


func after_each() -> void:
	Strings.use_default_locale()


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


func _ink_material(view: CityView) -> ShaderMaterial:
	var ink: MeshInstance3D = view.find_child("Ink", true, false) as MeshInstance3D
	assert_not_null(ink, "The city has its ink pass")
	return ink.mesh.surface_get_material(0) as ShaderMaterial


func test_the_data_is_valid_and_subtle() -> void:
	assert_eq(_style.errors, [] as Array[String])
	assert_lte(_style.ink["grain_strength"], CityInk.MAX_GRAIN)
	assert_lte(_style.ink["hatch_luminance"], CityInk.MAX_HATCH_LUMINANCE, "Hatching only in deep shadows")


func test_the_shader_has_contours_hatching_grain_and_the_grid() -> void:
	var names: Array[String] = []
	for uniform: Dictionary in CityInk.SHADER.get_shader_uniform_list():
		names.append(uniform["name"])
	for key: String in CityInk.KEYS + ["ink_color", "grid_cell_m"]:
		assert_has(names, key)


func test_the_city_draws_through_the_ink_with_the_data_values() -> void:
	var view: CityView = await _view()
	var ink: ShaderMaterial = _ink_material(view)
	assert_eq(ink.shader, CityInk.SHADER)
	for key: String in CityInk.KEYS:
		assert_eq(float(ink.get_shader_parameter(key)), view.style.ink[key], key)
	assert_eq(float(ink.get_shader_parameter("grid_cell_m")), 25.0, "The inked grid is the 25 m cell (D-093)")


func test_marks_and_the_selection_draw_after_the_ink() -> void:
	var view: CityView = await _view()
	view.session.submit_command(BuildCommand.new(view.session.context, &"housing", HOUSE))
	view.session.simulation.tick()
	assert_true(view.session.simulation.mark_house_sick(HOUSE))
	view.session.publish_tick()
	view.geometry.selected = HOUSE
	await get_tree().process_frame
	var ink_priority: int = _ink_material(view).render_priority
	var meshes: Array[Node] = (view.get("_selection") as Node3D).get_children() + (view.get("_marks") as Node3D).get_children()
	assert_gt(meshes.size(), 4, "The selection's four bars and the crisis mark")
	for node: Node in meshes:
		var material: Material = (node as MeshInstance3D).mesh.surface_get_material(0)
		assert_gt(material.render_priority, ink_priority, "%s over the ink" % node)


func test_heavy_grain_or_hatching_beyond_deep_shadows_is_refused() -> void:
	var raw: Dictionary = _raw()
	raw["ink"]["grain_strength"] = CityInk.MAX_GRAIN * 2.0
	raw["ink"]["hatch_luminance"] = CityInk.MAX_HATCH_LUMINANCE * 2.0
	var style: CityPresentation = CityPresentation.new()
	style.validate(raw, [])
	assert_eq(style.errors.size(), 2, str(style.errors))
