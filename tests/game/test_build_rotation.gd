extends GutTest

# Issue #296 (D-157): R rotates the building about to be placed. It does not repair while that building can turn.
# With the wharf selected, or with nothing selected, R still repairs. Y always repairs.

const ROOT: String = "user://test_build_rotation"
const DAMAGED_WHARF: Vector2i = Vector2i(26, 13)

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


func _view() -> Node2D:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 800)
	add_child_autofree(_viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	view.set("mods_root", ROOT)
	view.set("saves_root", ROOT)
	_viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	return view


func _select(view: Node2D, cell: Vector2i) -> void:
	(view.get("geometry") as MapGeometry).selected = cell
	view.call("_update_mode")


func _key(view: Node2D, keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_viewport.push_input(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	_viewport.push_input(release)


func _tick(view: Node2D) -> void:
	var session: GameSession = view.get("session") as GameSession
	session.simulation.tick()
	session.publish_tick()


func test_r_rotates_the_malthouse_and_does_not_repair() -> void:
	var view: Node2D = await _view()
	_select(view, DAMAGED_WHARF)
	_key(view, KEY_6)
	assert_eq(view.get("_building_type"), &"malthouse")
	assert_eq((view.call("_placement_area", DAMAGED_WHARF) as Rect2i).size, Vector2i(2, 1))
	_key(view, KEY_R)
	_tick(view)
	assert_eq(view.get("_rotation"), 1)
	assert_eq((view.call("_placement_area", DAMAGED_WHARF) as Rect2i).size, Vector2i(1, 2))
	assert_eq((view.get("session") as GameSession).get_snapshot()["repair"]["wharves"].size(), 1,
		"R rotated; it did not repair")
	assert_string_contains((view.get("_mode") as Label).text, Strings.text(Strings.BUILD_ROTATION) % 2)


func test_r_on_the_wharf_still_repairs() -> void:
	var view: Node2D = await _view()
	_select(view, DAMAGED_WHARF)
	_key(view, KEY_1)
	assert_eq(view.get("_building_type"), &"wharf")
	_key(view, KEY_R)
	_tick(view)
	assert_eq(view.get("_rotation"), 0)
	assert_eq((view.get("session") as GameSession).get_snapshot()["repair"]["wharves"], [])
