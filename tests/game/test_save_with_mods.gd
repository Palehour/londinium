extends GutTest

# Issue #136 (D-117): a game saved with other mods can load with the mods it was saved with, for that session only.
# A missing mod or another version of one is refused naming the mod and the version, and the player's
# load_order.json is never touched. The map view keeps its saves and mods in scratch folders here.

const ROOT: String = "user://test_save_with_mods"
const MODS_ROOT: String = "user://test_save_with_mods_mods"
# Saved at minute 2 and played to minute 8, short of the first autosave (10 minutes, data/game/save.json).
const SAVED_TICK: int = 120
const LAST_TICK: int = 480


func before_each() -> void:
	_remove(ROOT)
	_remove(MODS_ROOT)
	Strings.use_default_locale()


func after_each() -> void:
	_remove(ROOT)
	_remove(MODS_ROOT)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(folder))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _write(path: String, content: Variant) -> void:
	var full: String = MODS_ROOT.path_join(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var file: FileAccess = FileAccess.open(full, FileAccess.WRITE)
	file.store_string(JSON.stringify(content))
	file.close()


# Two mods that set the same per-tick value (the wheat price the market reverts to), so their order changes the game.
func _write_two_mods() -> void:
	_write("a/data/economy/market.json", {"wheat": {"base_price": 1}})
	_write("a/mod.json", {"version": "1.0"})
	_write("b/data/economy/market.json", {"wheat": {"base_price": 3}})
	_write("b/mod.json", {"version": "1.0"})
	_write(ModLayer.LOAD_ORDER_FILE, ["a", "b"])


func _load_order() -> String:
	return FileAccess.get_file_as_string(MODS_ROOT.path_join(ModLayer.LOAD_ORDER_FILE))


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


func _panel(view: Node2D) -> StatsPanel:
	return view.get("_stats_panel") as StatsPanel


func _texts(menu: Control) -> String:
	var texts: Array[String] = []
	for node: Node in menu.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return "\n".join(texts)


func _saves_menu(view: Node2D) -> SavesMenu:
	return _panel(view).get("_saves_menu") as SavesMenu


func _mods_menu(view: Node2D) -> ModsMenu:
	return _panel(view).get("_mods_menu") as ModsMenu


func _buttons(menu: Control, caption: String) -> Array[Button]:
	var found: Array[Button] = []
	for node: Node in menu.find_children("*", "Button", true, false):
		if (node as Button).text == caption:
			found.append(node as Button)
	return found


func _session(view: Node2D) -> GameSession:
	return view.get("session") as GameSession


# A game on the mods of the folder, saved at SAVED_TICK; returns the game's state at LAST_TICK.
func _save_a_game() -> PackedByteArray:
	var view: Node2D = await _view()
	for tick: int in SAVED_TICK:
		_session(view).simulation.tick()
		_session(view).publish_tick()
	_buttons(_saves_menu(view), Strings.text(Strings.SAVE_GAME))[0].pressed.emit()
	for tick: int in LAST_TICK - SAVED_TICK:
		_session(view).simulation.tick()
	return var_to_bytes(_session(view).simulation.to_save())


func _press_load(view: Node2D) -> void:
	_buttons(_saves_menu(view), Strings.text(Strings.LOAD_GAME))[0].pressed.emit()


func _press_load_with_save_mods(view: Node2D) -> void:
	var offer: Array[Button] = _buttons(_saves_menu(view), Strings.text(Strings.LOAD_WITH_SAVE_MODS))
	assert_eq(offer.size(), 1, "The menu offers to load with the save's mods")
	if not offer.is_empty():
		offer[0].pressed.emit()


func test_a_game_loaded_with_its_mods_plays_on_bit_for_bit() -> void:
	_write_two_mods()
	var original: PackedByteArray = await _save_a_game()
	_write(ModLayer.LOAD_ORDER_FILE, ["b", "a"])
	var order: String = _load_order()
	var view: Node2D = await _view()
	assert_eq(_session(view).mods, [&"b", &"a"] as Array[StringName])
	_press_load(view)
	assert_eq(_session(view).get_snapshot()["tick_count"], 0, "Nothing loads before the player accepts")
	assert_string_contains(_texts(_saves_menu(view)), Strings.save_mods_differ([&"a", &"b"], [&"b", &"a"]))
	_press_load_with_save_mods(view)
	assert_eq(_session(view).mods, [&"a", &"b"] as Array[StringName])
	assert_eq(_session(view).get_snapshot()["tick_count"], SAVED_TICK)
	assert_eq((view.get("clock") as SimClock).simulation, _session(view).simulation)
	for tick: int in LAST_TICK - SAVED_TICK:
		_session(view).simulation.tick()
	assert_eq(var_to_bytes(_session(view).simulation.to_save()), original)
	assert_eq(_load_order(), order, "The player's load_order.json is not touched")


# The guard of the test above: on the player's order B, A the same save plays another game.
func test_the_same_save_on_the_other_order_plays_another_game() -> void:
	_write_two_mods()
	var original: PackedByteArray = await _save_a_game()
	_write(ModLayer.LOAD_ORDER_FILE, ["b", "a"])
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", DataLoader.DEFAULT_ERA, MODS_ROOT)
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	var session: GameSession = GameSession.new(loaded.catalog, params)
	session.load_save(SaveFile.read(SaveFile.list(ROOT)[0]["path"])["data"], params)
	for tick: int in LAST_TICK - SAVED_TICK:
		session.simulation.tick()
	assert_ne(var_to_bytes(session.simulation.to_save()), original)


func test_after_that_session_the_players_mods_come_back() -> void:
	_write_two_mods()
	await _save_a_game()
	_write(ModLayer.LOAD_ORDER_FILE, ["b", "a"])
	var order: String = _load_order()
	var view: Node2D = await _view()
	_press_load(view)
	_press_load_with_save_mods(view)
	assert_true(_session(view).mods_from_save)
	assert_string_contains(_texts(_mods_menu(view)), Strings.text(Strings.MODS_FROM_SAVE))
	for button: Button in _buttons(_mods_menu(view), Strings.text(Strings.MODS_DOWN)):
		assert_true(button.disabled, "The save's mods are not reordered: that would write the player's list")
	view.call("_restart_session")
	assert_false(_session(view).mods_from_save)
	assert_eq(_session(view).mods, [&"b", &"a"] as Array[StringName])
	assert_eq(_session(view).get_snapshot()["tick_count"], 0)
	assert_eq(_load_order(), order)
	assert_false(_texts(_mods_menu(view)).contains(Strings.text(Strings.MODS_FROM_SAVE)))


func test_a_missing_mod_is_refused_naming_it_and_its_version() -> void:
	_write_two_mods()
	await _save_a_game()
	_remove(MODS_ROOT.path_join("b"))
	_write(ModLayer.LOAD_ORDER_FILE, ["a"])
	var view: Node2D = await _view()
	_press_load(view)
	var texts: String = _texts(_saves_menu(view))
	assert_string_contains(texts, Strings.save_refusal(SaveFile.MISSING_MOD, ["b", "1.0"]))
	assert_string_contains(texts, "b")
	assert_string_contains(texts, "1.0")
	assert_true(_buttons(_saves_menu(view), Strings.text(Strings.LOAD_WITH_SAVE_MODS)).is_empty(),
		"There is no option to load anyway")
	assert_eq(_session(view).get_snapshot()["tick_count"], 0, "The current game goes on")


func test_another_version_of_a_mod_is_refused_showing_both_versions() -> void:
	_write_two_mods()
	await _save_a_game()
	_write("b/data/economy/market.json", {"wheat": {"base_price": 2}})
	_write("b/mod.json", {"version": "2.0"})
	var view: Node2D = await _view()
	_press_load(view)
	var texts: String = _texts(_saves_menu(view))
	assert_string_contains(texts, Strings.save_refusal(SaveFile.OTHER_MOD_VERSION, ["b", "1.0", "2.0"]))
	assert_true(_buttons(_saves_menu(view), Strings.text(Strings.LOAD_WITH_SAVE_MODS)).is_empty())
	assert_eq(_session(view).get_snapshot()["tick_count"], 0)


func test_a_game_saved_without_mods_loads_without_them_for_the_session() -> void:
	DirAccess.make_dir_recursive_absolute(MODS_ROOT)
	await _save_a_game()
	_write("rich/data/economy/startup.json", {"money": 2000})
	var view: Node2D = await _view()
	assert_eq(_session(view).mods, [&"rich"] as Array[StringName])
	_press_load(view)
	assert_string_contains(_texts(_saves_menu(view)), Strings.save_mods_differ([], [&"rich"]))
	_press_load_with_save_mods(view)
	assert_true(_session(view).mods.is_empty())
	assert_eq(_session(view).get_snapshot()["tick_count"], SAVED_TICK)
	view.call("_restart_session")
	assert_eq(_session(view).mods, [&"rich"] as Array[StringName])
	assert_eq(_session(view).get_snapshot()["economy"]["money"], 2000)


# Steam Deck: in the panel with a gamepad the offer takes the focus like every other button of the menu.
func test_the_offer_works_with_a_gamepad() -> void:
	_write_two_mods()
	await _save_a_game()
	_write(ModLayer.LOAD_ORDER_FILE, ["b", "a"])
	var view: Node2D = await _view()
	_saves_menu(view).focusable = true
	_press_load(view)
	var offer: Array[Button] = _buttons(_saves_menu(view), Strings.text(Strings.LOAD_WITH_SAVE_MODS))
	assert_eq(offer.size(), 1)
	assert_eq(offer[0].focus_mode, Control.FOCUS_ALL)


func test_a_save_records_each_mod_with_its_version_and_hash() -> void:
	_write_two_mods()
	var view: Node2D = await _view()
	var saved: Dictionary = SaveFile.build(_session(view))
	assert_eq(saved["mods"], [&"a", &"b"])
	assert_eq(saved["mod_versions"], ModLayer.installed(MODS_ROOT).values())
	assert_eq(saved["mod_versions"][0]["version"], "1.0")


# The same version name with other data is still another mod: both are shown with their hashes.
func test_same_version_with_other_data_is_refused_with_both_hashes() -> void:
	_write_two_mods()
	var view: Node2D = await _view()
	var saved: Dictionary = SaveFile.build(_session(view))
	assert_eq(SaveFile.check_compatible(saved, _session(view), view.get("_catalog"))["reason"], &"")
	_write("b/data/economy/market.json", {"wheat": {"base_price": 2}})
	var installed: Dictionary[StringName, Dictionary] = ModLayer.installed(MODS_ROOT)
	var result: Dictionary = SaveFile.mods_offer(saved, installed)
	assert_eq(result["reason"], SaveFile.OTHER_MOD_VERSION)
	var old_hash: String = saved["mod_versions"][1]["hash"]
	var new_hash: String = installed[&"b"]["hash"]
	assert_eq(result["args"], ["b", "1.0 (%s)" % old_hash.left(SaveFile.SHORT_HASH),
		"1.0 (%s)" % new_hash.left(SaveFile.SHORT_HASH)])
	_session(view).mod_fingerprints.assign(installed.values())
	assert_eq(SaveFile.check_compatible(saved, _session(view), view.get("_catalog"))["reason"], SaveFile.OTHER_MODS,
		"Same names in the same order are not enough once the data changed")
