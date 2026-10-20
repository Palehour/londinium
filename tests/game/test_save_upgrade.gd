extends GutTest

# Issue #186 (D-087): a game saved on the grid of 50 m (format 1) converts itself when it loads. Every old cell (x, y)
# becomes its 2x2 block from (2x, 2y), with the buildings, the streets and the state as they were, and the game plays
# on as it did. The fixture is a game on the strip (two streets of the player, a mill, a bakery, three houses) saved
# by develop 3fcc336 at tick 600, before the scale changed, and what that same game held at tick 1500.

const SAVE: String = "res://tests/fixtures/saves/format_1_strip.sav"
const EXPECTED: String = "res://tests/fixtures/saves/format_1_strip_expected.sav"
# Cells of 25 m on each side of an old cell of 50 m (D-086).
const BLOCK: int = 2
const OLD_STEP_M: int = 50

var _catalog: DataCatalog
var _params: Params
var _expected: Dictionary


func before_all() -> void:
	Strings.use_default_locale()
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	var file: FileAccess = FileAccess.open_compressed(EXPECTED, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	_expected = file.get_var(false)
	file.close()


# The game of the fixture loaded into a session, played on to the tick of the expected state.
func _loaded() -> GameSession:
	var read: Dictionary = SaveFile.read(SAVE)
	assert_eq(read["reason"], &"", "A save of format 1 is still read")
	var session: GameSession = GameSession.new(_catalog, _params)
	assert_eq(SaveFile.check_compatible(read["data"], session, _catalog)["reason"], &"")
	session.load_save(read["data"], _params)
	return session


func _play_to_expected(session: GameSession) -> void:
	while session.simulation.snapshot()["tick_count"] < int(_expected["tick_count"]):
		session.simulation.tick()


func _scaled(cell: Array) -> Array:
	return [int(cell[0]) * BLOCK, int(cell[1]) * BLOCK]


# The expected entries with their cells in the new grid, the way the save had them in the old one.
func _scaled_entries(entries: Array, fields: Array[String]) -> Array:
	var scaled: Array = []
	for entry: Dictionary in entries:
		var copy: Dictionary = entry.duplicate(true)
		for field: String in fields:
			copy[field] = _scaled(entry[field])
		scaled.append(copy)
	return scaled


func _scaled_subject(subject: String) -> String:
	if not subject.contains("@"):
		return subject
	var cell: PackedStringArray = subject.get_slice("@", 1).split(",")
	return "%s@%d,%d" % [subject.get_slice("@", 0), cell[0].to_int() * BLOCK, cell[1].to_int() * BLOCK]


func test_an_old_save_plays_on_to_the_same_state() -> void:
	var session: GameSession = _loaded()
	_play_to_expected(session)
	var economy: Dictionary = session.simulation.to_save()["economy"]
	var expected: Dictionary = _expected["economy"].duplicate(true)
	expected["buildings"] = _scaled_entries(expected["buildings"], ["cell"])
	expected["player_roads"] = _scaled_entries(expected["player_roads"], ["cell"])
	assert_eq(economy, expected, "Money, people, stocks, buildings and streets as in v0.3.0")
	assert_eq(session.simulation.get_rng_state(), int(_expected["rng_state"]))
	assert_eq(session.simulation.get_barley_rng_state(), int(_expected["barley_rng_state"]))


func test_the_transport_and_the_houses_served_are_the_same() -> void:
	var session: GameSession = _loaded()
	_play_to_expected(session)
	var distance: Dictionary = session.simulation.snapshot()["distance"]
	var legs: Array = _scaled_entries(_expected["legs"], ["cell", "supplier_cell"])
	assert_false(legs.is_empty(), "The fixture pays transport")
	for leg: Dictionary in legs:
		leg["metres"] = int(leg["steps"]) * OLD_STEP_M
	assert_eq(distance["legs"], legs)
	assert_eq(distance["houses"], _scaled_entries(_expected["houses"], ["cell"]))
	assert_eq(distance["blocked"], _scaled_entries(_expected["blocked"], ["cell"]))


func test_the_causes_keep_their_buildings() -> void:
	var session: GameSession = _loaded()
	_play_to_expected(session)
	var expected: Array = []
	for event: Dictionary in _expected["events"]:
		var copy: Dictionary = event.duplicate()
		copy["subject"] = StringName(_scaled_subject(String(event["subject"])))
		expected.append(copy)
	assert_eq(session.simulation.stats_events(), expected)


# Each street of the player becomes a piece over the 4 cells of its block: none of them takes another street.
func test_an_old_street_becomes_a_two_by_two_piece() -> void:
	var session: GameSession = _loaded()
	var road: Array = session.simulation.snapshot()["economy"]["player_roads"][0]["cell"]
	assert_eq(road, [8 * BLOCK, 4 * BLOCK])
	for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var cell: Vector2i = Vector2i(road[0], road[1]) + offset
		var command: BuildRoadCommand = BuildRoadCommand.new(session.context, cell)
		session.simulation.apply_command(command)
		session.simulation.tick()
		assert_eq(command.reason, &"road_cell", str(cell))


func test_a_converted_game_is_saved_in_the_new_format() -> void:
	var session: GameSession = _loaded()
	var saved: Dictionary = SaveFile.build(session)
	assert_eq(saved["version"], SaveFile.VERSION)
	assert_eq(saved["simulation"]["economy"]["player_roads"][0]["cell"], [8 * BLOCK, 4 * BLOCK])
