extends GutTest

# Saved games (issue #57, D-037): a versioned, compressed file with what the game ran on. A file that is not a save,
# a save in another format version or one played with other mods is refused with a message from Strings.

const ROOT: String = "user://test_save_file"

var _catalog: DataCatalog
var _session: GameSession


func before_each() -> void:
	_remove(ROOT)
	Strings.use_default_locale()
	_catalog = DataLoader.new().load_all().catalog
	_session = GameSession.new(_catalog, Params.new(_catalog, _catalog.roles[&"neutral_administrator"]))
	for tick: int in 120:
		_session.simulation.tick()


func after_each() -> void:
	_remove(ROOT)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _write_raw(file_name: String, bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var path: String = ROOT.path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return path


func test_write_then_read_returns_same_save_with_version() -> void:
	var path: String = SaveFile.write_manual(ROOT, SaveFile.build(_session))
	assert_false(path.is_empty())
	var result: Dictionary = SaveFile.read(path)
	assert_eq(result["reason"], &"")
	assert_eq(result["data"]["format"], SaveFile.FORMAT)
	assert_eq(result["data"]["version"], SaveFile.VERSION)
	assert_eq(result["data"]["simulation"], _session.simulation.to_save())


func test_save_records_difficulty_and_mods() -> void:
	_session.restart_with(Params.new(_catalog, _catalog.roles[&"neutral_administrator"],
		DataLayers.resolve(_catalog, &"hard").modifiers), &"hard")
	_session.mods.assign([&"bigger_mills", &"cheap_tea"])
	var saved: Dictionary = SaveFile.build(_session)
	assert_eq(saved["difficulty"], &"hard")
	assert_eq(saved["mods"], [&"bigger_mills", &"cheap_tea"])
	assert_eq(saved["scenario"], &"victorian_demo")
	assert_eq(saved["knobs"], {})


func test_rejects_garbage_file() -> void:
	var path: String = _write_raw("garbage.sav", "esto no es una partida".to_utf8_buffer())
	var result: Dictionary = SaveFile.read(path)
	assert_eq(result["reason"], SaveFile.INVALID_FILE)
	assert_eq(Strings.save_refusal(result["reason"], result["args"]),
		"No se pudo cargar: el archivo no es una partida guardada de Londinium o está dañado.")


func test_rejects_a_save_with_a_broken_economy() -> void:
	var saved: Dictionary = SaveFile.build(_session)
	saved["simulation"]["economy"]["money"] = "mucho"
	assert_eq(SaveFile.validate(saved)["reason"], SaveFile.INVALID_FILE)
	saved["simulation"]["economy"].erase("money")
	assert_eq(SaveFile.validate(saved)["reason"], SaveFile.INVALID_FILE)
	assert_eq(SaveFile.validate({"format": SaveFile.FORMAT})["reason"], SaveFile.INVALID_FILE)


func test_rejects_other_version() -> void:
	var saved: Dictionary = SaveFile.build(_session)
	saved["version"] = SaveFile.VERSION + 1
	var path: String = ROOT.path_join("future.sav")
	assert_eq(SaveFile.write(path, saved), OK)
	var result: Dictionary = SaveFile.read(path)
	assert_eq(result["reason"], SaveFile.OTHER_VERSION)
	assert_eq(Strings.save_refusal(result["reason"], result["args"]),
		"No se pudo cargar: la partida está guardada en el formato %d y este juego lee el %d."
			% [SaveFile.VERSION + 1, SaveFile.VERSION])


func test_rejects_other_mods() -> void:
	var saved: Dictionary = SaveFile.build(_session)
	saved["mods"] = ["bigger_mills"]
	var result: Dictionary = SaveFile.check_compatible(saved, _session, _catalog)
	assert_eq(result["reason"], SaveFile.OTHER_MODS)
	assert_string_contains(Strings.save_refusal(result["reason"], result["args"]), "bigger_mills")
	_session.mods.assign([&"bigger_mills"])
	saved["mods"] = []
	result = SaveFile.check_compatible(saved, _session, _catalog)
	assert_string_contains(Strings.save_refusal(result["reason"], result["args"]), "sin mods")


func test_rejects_unknown_difficulty_or_scenario() -> void:
	var saved: Dictionary = SaveFile.build(_session)
	saved["difficulty"] = "nightmare"
	assert_eq(SaveFile.check_compatible(saved, _session, _catalog)["reason"], SaveFile.INVALID_FILE)
	saved = SaveFile.build(_session)
	saved["scenario"] = "roman_demo"
	assert_eq(SaveFile.check_compatible(saved, _session, _catalog)["reason"], SaveFile.INVALID_FILE)


func test_save_without_stats_history_loads() -> void:
	var saved: Dictionary = SaveFile.build(_session)
	saved["simulation"].erase("stats_history")
	saved["simulation"].erase("stats_window")
	var path: String = ROOT.path_join("old.sav")
	assert_eq(SaveFile.write(path, saved), OK)
	var result: Dictionary = SaveFile.read(path)
	assert_eq(result["reason"], &"")
	_session.load_save(result["data"], Params.new(_catalog, _catalog.roles[&"neutral_administrator"]))
	assert_eq(_session.get_snapshot()["tick_count"], 120)


# Issue #88, T4: transformed cells of another shape refuse the save instead of breaking the load.
func test_rejects_malformed_terrain_changes() -> void:
	var saved: Dictionary = SaveFile.build(_session)
	var economy: Dictionary = saved["simulation"]["economy"]
	economy["terrain_changes"] = [{"cell": [3, 4], "terrain": "firm"}]
	assert_eq(SaveFile.validate(saved)["reason"], &"")
	for broken: Variant in ["firm", [{"cell": [3], "terrain": "firm"}], [{"cell": [3, 4]}],
			[{"cell": [3, 4], "terrain": 2}], [{"cell": ["a", 4], "terrain": "firm"}], ["firm"]]:
		economy["terrain_changes"] = broken
		assert_eq(SaveFile.validate(saved)["reason"], SaveFile.INVALID_FILE, str(broken))


# Issue #67 (D-080): a game saved before the streets loads without them and without errors.
func test_old_save_without_roads_loads() -> void:
	var saved: Dictionary = SaveFile.build(_session)
	saved["simulation"]["economy"].erase("player_roads")
	saved["simulation"]["economy"].erase("transport_fraction")
	var path: String = ROOT.path_join("before_roads.sav")
	assert_eq(SaveFile.write(path, saved), OK)
	var result: Dictionary = SaveFile.read(path)
	assert_eq(result["reason"], &"")
	_session.load_save(result["data"], Params.new(_catalog, _catalog.roles[&"neutral_administrator"]))
	assert_eq(_session.get_snapshot()["economy"]["player_roads"], [])
	assert_eq(_session.get_snapshot()["distance"]["player_roads"], [])


func test_manual_saves_never_overwrite() -> void:
	var first: String = SaveFile.write_manual(ROOT, SaveFile.build(_session))
	_session.simulation.tick()
	var second: String = SaveFile.write_manual(ROOT, SaveFile.build(_session))
	assert_ne(first, second)
	assert_eq(SaveFile.list(ROOT).size(), 2)
	assert_eq(int(SaveFile.read(first)["data"]["simulation"]["tick_count"]), 120)
	assert_eq(int(SaveFile.read(second)["data"]["simulation"]["tick_count"]), 121)


func test_list_names_each_save_and_marks_unreadable_ones() -> void:
	SaveFile.write_manual(ROOT, SaveFile.build(_session))
	SaveFile.write(SaveFile.autosave_path(ROOT, 2), SaveFile.build(_session))
	_write_raw("broken.sav", PackedByteArray([1, 2, 3]))
	var lines: Array[String] = []
	for entry: Dictionary in SaveFile.list(ROOT):
		lines.append(Strings.save_entry(entry))
	assert_eq(lines.size(), 3)
	assert_true(lines.any(func(line: String) -> bool: return line.begins_with("Guardada a mano · minuto 2 · ")))
	assert_true(lines.any(func(line: String) -> bool: return line.begins_with("Autoguardado 2 · minuto 2 · ")))
	assert_has(lines, "Guardada a mano · no se puede leer (broken.sav)")


func test_load_save_restores_difficulty_and_game() -> void:
	var hard: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"],
		DataLayers.resolve(_catalog, &"hard").modifiers)
	_session.restart_with(hard, &"hard")
	for tick: int in 90:
		_session.simulation.tick()
	var saved: Dictionary = SaveFile.build(_session)
	var expected: Dictionary = _session.get_snapshot()
	_session.restart_with(Params.new(_catalog, _catalog.roles[&"neutral_administrator"]), DataLayers.NORMAL)
	_session.load_save(saved, hard)
	assert_eq(_session.difficulty, &"hard")
	assert_eq(_session.get_snapshot(), expected)
