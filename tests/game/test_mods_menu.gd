extends GutTest

# Mods menu (issue #70, D-065): it lists the active mods in load order, shows their conflicts and saves a new
# order to load_order.json, which starts a new game. The map view reads mods from a scratch folder here.

const ROOT: String = "user://test_mods_menu"


func before_each() -> void:
	_remove(ROOT)


func after_each() -> void:
	_remove(ROOT)


func _write(path: String, content: Variant) -> void:
	var full: String = ROOT.path_join(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var file: FileAccess = FileAccess.open(full, FileAccess.WRITE)
	file.store_string(JSON.stringify(content))
	file.close()


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(folder))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _view() -> Node2D:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1152, 800)
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	view.set("mods_root", ROOT)
	viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	return view


func _menu(view: Node2D) -> ModsMenu:
	return (view.get("_stats_panel") as StatsPanel).get("_mods_menu") as ModsMenu


func _texts(menu: ModsMenu) -> String:
	var texts: Array[String] = []
	for node: Node in menu.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return "\n".join(texts)


# The buttons of row `index`: [up, down].
func _buttons(menu: ModsMenu, index: int) -> Array[Node]:
	return menu.get_children().filter(func(node: Node) -> bool: return node is HBoxContainer)[index] \
		.find_children("*", "Button", true, false)


func _saved_order() -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(ROOT.path_join(ModLayer.LOAD_ORDER_FILE)))


func test_without_mods_the_menu_says_where_to_put_them() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var view: Node2D = await _view()
	assert_string_contains(_texts(_menu(view)), ProjectSettings.globalize_path(ROOT))


func test_menu_lists_mods_in_order_and_shows_the_conflict() -> void:
	_write("a_rich/data/economy/startup.json", {"money": 2000})
	_write("b_poor/data/economy/startup.json", {"money": 600})
	var view: Node2D = await _view()
	var session: GameSession = view.get("session") as GameSession
	assert_eq(session.mods, [&"a_rich", &"b_poor"] as Array[StringName])
	assert_eq(session.get_snapshot()["economy"]["money"], 600)
	var texts: String = _texts(_menu(view))
	assert_string_contains(texts, "1. a_rich")
	assert_string_contains(texts, "2. b_poor")
	assert_string_contains(texts, Strings.text(Strings.MODS_CONFLICT) % ["economy/startup.json.money",
		"a_rich, b_poor", "b_poor"])


func test_moving_a_mod_saves_the_order_and_starts_a_new_game() -> void:
	_write("a_rich/data/economy/startup.json", {"money": 2000})
	_write("b_poor/data/economy/startup.json", {"money": 600})
	var view: Node2D = await _view()
	var session: GameSession = view.get("session") as GameSession
	session.simulation.tick()
	var buttons: Array[Node] = _buttons(_menu(view), 0)
	assert_true((buttons[0] as Button).disabled, "The first mod cannot move up")
	(buttons[1] as Button).pressed.emit()
	assert_eq(_saved_order(), ["b_poor", "a_rich"])
	assert_eq(session.mods, [&"b_poor", &"a_rich"] as Array[StringName])
	assert_eq(session.mod_conflicts[0]["winner"], "a_rich")
	assert_eq(session.get_snapshot()["tick_count"], 0)
	assert_eq(session.get_snapshot()["economy"]["money"], 2000)
	assert_eq((view.get("clock") as SimClock).simulation, session.simulation)
	assert_string_contains(_texts(_menu(view)), "1. b_poor")


func test_an_order_that_does_not_validate_keeps_the_game_and_the_old_order() -> void:
	# In this order b's fractions win; reversed, a's defeat fraction ends above b's warning fraction.
	_write("a/data/economy/defeat.json", {"depopulation": {"defeat_fraction": 0.35}})
	_write("b/data/economy/defeat.json", {"depopulation": {"warning_fraction": 0.3, "defeat_fraction": 0.2}})
	var view: Node2D = await _view()
	var session: GameSession = view.get("session") as GameSession
	session.simulation.tick()
	var simulation: Simulation = session.simulation
	(_buttons(_menu(view), 0)[1] as Button).pressed.emit()
	assert_eq(session.simulation, simulation, "The game goes on")
	assert_eq(session.mods, [&"a", &"b"] as Array[StringName])
	assert_eq(_saved_order(), ["a", "b"])
	assert_string_contains(_texts(_menu(view)), "defeat_fraction must be <= defeat.depopulation.warning_fraction")
