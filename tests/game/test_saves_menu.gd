extends GutTest

# Saves menu (issue #57): the panel saves the game, lists the saves and loads one; a file it cannot load leaves a
# clear message and the game goes on. The map view keeps its saves (and reads mods) in scratch folders here.

const ROOT: String = "user://test_saves_menu"
const MODS_ROOT: String = "user://test_saves_menu_mods"


func before_each() -> void:
	_remove(ROOT)


func after_each() -> void:
	_remove(ROOT)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _view() -> Node2D:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1152, 800)
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	view.set("mods_root", MODS_ROOT)
	view.set("saves_root", ROOT)
	viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	return view


func _menu(view: Node2D) -> SavesMenu:
	return (view.get("_stats_panel") as StatsPanel).get("_saves_menu") as SavesMenu


func _texts(menu: SavesMenu) -> String:
	var texts: Array[String] = []
	for node: Node in menu.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return "\n".join(texts)


func _press(menu: SavesMenu, caption: String, index: int = 0) -> void:
	var found: Array[Button] = []
	for node: Node in menu.find_children("*", "Button", true, false):
		if (node as Button).text == caption:
			found.append(node as Button)
	(found[index] as Button).pressed.emit()


func _session(view: Node2D) -> GameSession:
	return view.get("session") as GameSession


func _tick(view: Node2D, count: int) -> void:
	for tick: int in count:
		_session(view).simulation.tick()
		_session(view).publish_tick()


func test_save_then_load_brings_the_saved_minute_back() -> void:
	var view: Node2D = await _view()
	var menu: SavesMenu = _menu(view)
	assert_string_contains(_texts(menu), Strings.text(Strings.SAVES_NONE))
	_tick(view, 120)
	_press(menu, Strings.text(Strings.SAVE_GAME))
	assert_string_contains(_texts(menu), Strings.text(Strings.SAVED))
	assert_string_contains(_texts(menu), "Guardada a mano · minuto 2")
	_tick(view, 60)
	_press(menu, Strings.text(Strings.LOAD_GAME))
	assert_eq(_session(view).get_snapshot()["tick_count"], 120)
	assert_eq((view.get("clock") as SimClock).simulation, _session(view).simulation, "The clock drives the loaded game")
	assert_string_contains(_texts(menu), Strings.text(Strings.SAVE_LOADED))


func test_saving_with_a_queued_order_says_it_is_not_in_the_file() -> void:
	var view: Node2D = await _view()
	_session(view).submit_command(SetTaxCommand.new(0.3))
	_press(_menu(view), Strings.text(Strings.SAVE_GAME))
	assert_string_contains(_texts(_menu(view)), Strings.text(Strings.SAVED_WITHOUT_QUEUE))


func test_a_file_from_another_version_is_refused_and_the_game_goes_on() -> void:
	var view: Node2D = await _view()
	_tick(view, 30)
	var saved: Dictionary = SaveFile.build(_session(view))
	saved["version"] = SaveFile.VERSION + 1
	SaveFile.write(ROOT.path_join("future.sav"), saved)
	(view.get("_stats_panel") as StatsPanel).show_saves(SaveFile.list(ROOT))
	_tick(view, 30)
	_press(_menu(view), Strings.text(Strings.LOAD_GAME))
	assert_eq(_session(view).get_snapshot()["tick_count"], 60)
	assert_string_contains(_texts(_menu(view)), Strings.save_refusal(SaveFile.OTHER_VERSION,
		[SaveFile.VERSION + 1, SaveFile.VERSION]))
