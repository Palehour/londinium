extends GutTest

# Autosaves (issue #57, numbers approved on 2026-10-13): every 10 game minutes into 3 rotating slots, and one file of
# its own when a chapter stage is met. Manual saves are unlimited and the autosave never touches them.

const ROOT: String = "user://test_autosave"

var _catalog: DataCatalog
var _session: GameSession
var _settings: SaveSettings
# The session's signal does not keep the autosave alive, so the test does (the map view keeps its own).
var _kept: Autosave


func before_each() -> void:
	_remove(ROOT)
	_catalog = DataLoader.new().load_all().catalog
	_session = GameSession.new(_catalog, Params.new(_catalog, _catalog.roles[&"neutral_administrator"]))
	_settings = SaveSettings.new()
	_settings.load_data()


func after_each() -> void:
	_remove(ROOT)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _autosave() -> Autosave:
	var autosave: Autosave = Autosave.new(_session, _settings, ROOT)
	_session.snapshot_changed.connect(autosave.observe)
	_kept = autosave
	return autosave


func _play(ticks: int) -> void:
	for tick: int in ticks:
		_session.simulation.tick()
		_session.publish_tick()


func _saved_tick(path: String) -> int:
	return int(SaveFile.read(path)["data"]["simulation"]["tick_count"])


func test_settings_hold_the_approved_numbers() -> void:
	assert_eq(_settings.errors, [] as Array[String])
	assert_eq(_settings.autosave_interval_seconds, 600)
	assert_eq(_settings.autosave_slots, 3)


func test_settings_reject_bad_values() -> void:
	var settings: SaveSettings = SaveSettings.new()
	settings.validate({"autosave_interval_seconds": 0, "autosave_slots": 2.5})
	assert_eq(settings.errors.size(), 2)
	settings.validate([])
	assert_eq(settings.errors.size(), 1)


func test_rotates_three_slots_every_interval() -> void:
	_settings.autosave_interval_seconds = 5
	_autosave()
	_play(4)
	assert_eq(SaveFile.list(ROOT).size(), 0, "Nothing before the first interval")
	_play(16)
	assert_eq(SaveFile.list(ROOT).size(), 3, "Three slots, the fourth autosave reused the first")
	assert_eq(_saved_tick(SaveFile.autosave_path(ROOT, 1)), 20)
	assert_eq(_saved_tick(SaveFile.autosave_path(ROOT, 2)), 10)
	assert_eq(_saved_tick(SaveFile.autosave_path(ROOT, 3)), 15)


func test_rotation_goes_on_after_the_newest_slot_on_disk() -> void:
	_settings.autosave_interval_seconds = 5
	_play(5)
	SaveFile.write(SaveFile.autosave_path(ROOT, 2), SaveFile.build(_session))
	_autosave()
	_play(5)
	assert_eq(_saved_tick(SaveFile.autosave_path(ROOT, 3)), 10)


func test_manual_saves_are_never_touched_by_the_rotation() -> void:
	_settings.autosave_interval_seconds = 5
	var manual: String = SaveFile.write_manual(ROOT, SaveFile.build(_session))
	_autosave()
	_play(30)
	assert_eq(_saved_tick(manual), 0)
	assert_eq(SaveFile.list(ROOT).size(), 4)


func test_stage_completion_writes_its_own_save() -> void:
	var autosave: Autosave = _autosave()
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["tick_count"] = 7
	snapshot["victory"]["stages"][&"population"]["completed"] = true
	autosave.observe(snapshot)
	autosave.observe(snapshot)
	var saves: Array[Dictionary] = SaveFile.list(ROOT)
	assert_eq(saves.size(), 1, "One save per stage, written once")
	assert_eq(saves[0]["path"], SaveFile.stage_path(ROOT, &"population"))
	assert_eq(saves[0]["kind"], SaveFile.KIND_STAGE)


func test_a_loaded_game_does_not_save_its_met_stages_again() -> void:
	var autosave: Autosave = _autosave()
	_play(1)
	var saved: Dictionary = SaveFile.build(_session)
	saved["simulation"]["economy"]["victory"]["stages"][&"population"]["completed_tick"] = 1
	_session.load_save(saved, Params.new(_catalog, _catalog.roles[&"neutral_administrator"]))
	assert_true(_session.get_snapshot()["victory"]["stages"][&"population"]["completed"])
	autosave.reset()
	_play(1)
	assert_eq(SaveFile.list(ROOT).size(), 0)
