extends GutTest

# The need layers of the map (issue #73, D-038): one per good some class needs, and each house that needs it is
# marked as served or not exactly as the snapshot says (distance.houses, from RoadSystem). In the 3D city the marks
# are game information: never under the fog nor the ink.

const ROOT: String = "user://test_need_overlay"
const HOUSE: Vector2i = Vector2i(12, 22)

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


func _mount(scene_path: String) -> MapView:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 800)
	add_child_autofree(_viewport)
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	var view: MapView = scene.get_node("Map") as MapView
	view.mods_root = ROOT
	view.saves_root = ROOT
	_viewport.add_child(scene)
	view.clock.speed = 0
	await get_tree().process_frame
	return view


func _key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_viewport.push_input(event)


func _snapshot(houses: Array) -> Dictionary:
	return {"distance": {"houses": houses}}


func test_the_layers_are_the_goods_the_classes_need_each_once() -> void:
	var catalog: DataCatalog = DataLoader.new().load_all().catalog
	var context: EconomyContext = EconomyContext.new(catalog, catalog.maps[&"riverside_strip"])
	var goods: Array[StringName] = NeedOverlay.goods(context)
	for definition: ClassDef in context.classes.values():
		for need: NeedDef in definition.needs:
			assert_has(goods, need.good)
	for good: StringName in goods:
		assert_eq(goods.count(good), 1, "%s once" % good)
	assert_eq(NeedOverlay.goods(null), [] as Array[StringName])


func test_each_house_is_served_or_not_as_the_snapshot_says() -> void:
	var snapshot: Dictionary = _snapshot([
		{"cell": [1, 1], "definition_id": &"housing", "class_id": &"worker", "connected": true,
			"served": {&"bread": true, &"beer": false}},
		{"cell": [4, 1], "definition_id": &"housing", "class_id": &"worker", "connected": false,
			"served": {&"bread": false, &"beer": false}},
		{"cell": [7, 1], "definition_id": &"artisan_housing", "class_id": &"artisan", "connected": true,
			"served": {&"tea": true}},
	])
	var bread: Array[Dictionary] = NeedOverlay.houses(snapshot, &"bread")
	assert_eq(bread, [{"cell": [1, 1], "definition_id": &"housing", "served": true},
		{"cell": [4, 1], "definition_id": &"housing", "served": false}] as Array[Dictionary],
		"only the houses whose class needs bread, as served as the simulation says")
	assert_eq(NeedOverlay.houses(snapshot, &"tea").size(), 1)
	assert_eq(NeedOverlay.houses(snapshot, NeedOverlay.NONE), [] as Array[Dictionary], "no layer, no marks")


func test_the_next_layer_goes_through_the_goods_and_back_to_none() -> void:
	var goods: Array[StringName] = [&"bread", &"beer"]
	assert_eq(NeedOverlay.next(goods, NeedOverlay.NONE), &"bread")
	assert_eq(NeedOverlay.next(goods, &"bread"), &"beer")
	assert_eq(NeedOverlay.next(goods, &"beer"), NeedOverlay.NONE)
	assert_eq(NeedOverlay.next([] as Array[StringName], NeedOverlay.NONE), NeedOverlay.NONE)


func test_o_goes_through_the_layers_on_the_map_and_the_bar_names_them() -> void:
	var view: MapView = await _mount("res://scenes/main.tscn")
	var bar: OverlayBar = view.get("_overlay_bar") as OverlayBar
	var goods: Array[StringName] = NeedOverlay.goods(view.session.context)
	assert_eq(bar.selected, NeedOverlay.NONE, "the map starts with no layer")
	assert_eq(bar.find_children("*", "Button", false, false).size(), goods.size() + 1, "none and one per good")
	for expected: StringName in goods + [NeedOverlay.NONE]:
		_key(KEY_O)
		assert_eq(bar.selected, expected)
	var texts: Array[String] = []
	for button: Node in bar.find_children("*", "Button", false, false):
		texts.append((button as Button).text)
	assert_has(texts, Strings.text(Strings.OVERLAY_NONE))
	assert_has(texts, Strings.label(Strings.GOOD_LABELS, goods[0]))
	assert_eq((bar.get_child(0) as Label).text, Strings.text(Strings.OVERLAY_CAPTION))


func test_the_city_marks_each_house_of_the_layer_outside_the_fog_and_the_ink() -> void:
	var view: MapView = await _mount("res://scenes/city.tscn")
	view.session.submit_command(BuildCommand.new(view.session.context, &"housing", HOUSE))
	view.session.simulation.tick()
	view.session.publish_tick()
	await get_tree().process_frame
	var marks: Node3D = view.get("_marks") as Node3D
	var before: int = marks.get_child_count()
	var bar: OverlayBar = view.get("_overlay_bar") as OverlayBar
	bar.select(&"bread")
	var houses: Array[Dictionary] = NeedOverlay.houses(view.session.get_snapshot(), &"bread")
	assert_false(houses.is_empty(), "the new house needs bread")
	assert_eq(marks.get_child_count(), before + houses.size(), "one block per house of the layer")
	var colors: Array[Color] = []
	for node: Node in marks.get_children():
		var material: BaseMaterial3D = (node as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
		assert_true(material.disable_fog, "never under the fog")
		assert_eq(material.render_priority, CityInk.ABOVE_INK, "never under the ink")
		colors.append(material.albedo_color)
	var expected: Color = view.presentation.ui_colors["selection" if houses[0]["served"] else "alert"]
	assert_has(colors, expected, "served or not, as the snapshot says")
	bar.select(NeedOverlay.NONE)
	assert_eq(marks.get_child_count(), before, "no layer, no blocks")
