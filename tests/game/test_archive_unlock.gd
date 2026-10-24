extends GutTest

# The Archive (issue #64) only reads the simulation: its cards stay locked until their event has passed (D-097), and
# STINK, BAZALGETTE and INQUIRY open together when the Old Ford mission closes, met or not (D-099). Reading it never
# changes the game.

const OLDFORD: StringName = &"oldford"
const MAP: StringName = &"whitechapel_1850s"
const HOUSE_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
const SEED: int = 7

var _data: DataCatalog
var _context: EconomyContext
var _archive: ArchiveCatalog


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_data = loaded.catalog
	_context = EconomyContext.new(_data, _data.maps[MAP])
	_archive = ArchiveCatalog.new()
	_archive.load_data()
	_archive.check_missions(_data.missions.keys())


func after_each() -> void:
	Strings.use_default_locale()


func _sim() -> Simulation:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"events.enabled", &"set", 1.0))
	role.modifiers.append(Modifier.new(&"defeat.enabled", &"set", 0.0))
	var params: Params = SimTestParams.isolated_params(_data, role)
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	for cell: Vector2i in HOUSE_CELLS:
		state.buildings.append({"definition_id": &"housing", "cell": [cell.x, cell.y]})
	return Simulation.new(params, state, SEED, _context)


func _command(sim: Simulation, action: StringName) -> void:
	var command: MissionCommand = MissionCommand.new(action, OLDFORD)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))


func _unlocked(sim: Simulation) -> Array[StringName]:
	var ids: Array[StringName] = []
	for card: ArchiveCard in _archive.cards:
		if ArchiveCatalog.is_unlocked(card, sim.snapshot()["economy"]):
			ids.append(card.id)
	return ids


func _status(sim: Simulation) -> StringName:
	return StringName(sim.snapshot()["economy"]["missions"][OLDFORD]["status"])


func test_every_card_is_locked_before_and_during_the_mission() -> void:
	var sim: Simulation = _sim()
	assert_eq(_unlocked(sim), [] as Array[StringName])
	_command(sim, &"start")
	assert_eq(_status(sim), MissionSystem.ACTIVE)
	assert_eq(_unlocked(sim), [] as Array[StringName])


# Houses with no water at the close: the mission fails, and the cards open anyway.
func test_a_failed_close_opens_all_four() -> void:
	var sim: Simulation = _sim()
	_command(sim, &"start")
	while _status(sim) == MissionSystem.ACTIVE:
		sim.tick()
	assert_eq(_status(sim), MissionSystem.FAILED)
	assert_eq(_unlocked(sim), [&"stink", &"bazalgette", &"oldford", &"inquiry"] as Array[StringName])


func test_an_abandoned_mission_is_closed_too() -> void:
	var sim: Simulation = _sim()
	_command(sim, &"start")
	_command(sim, &"abandon")
	assert_eq(_status(sim), MissionSystem.ABANDONED)
	assert_eq(_unlocked(sim).size(), 4)


func test_a_met_mission_opens_them_as_well() -> void:
	var economy: Dictionary = {"missions": {String(OLDFORD): {"status": String(MissionSystem.COMPLETED)}}}
	for card: ArchiveCard in _archive.cards:
		assert_true(ArchiveCatalog.is_unlocked(card, economy), String(card.id))


func test_the_panel_hides_locked_cards_and_never_touches_the_snapshot() -> void:
	var sim: Simulation = _sim()
	var panel: ArchivePanel = ArchivePanel.new()
	add_child_autofree(panel)
	panel.setup(_archive)
	var before: Dictionary = sim.snapshot()
	var copy: Dictionary = before.duplicate(true)
	panel.update_snapshot(before)
	assert_eq(before, copy, "The Archive only reads the snapshot")
	var title: String = Strings.text(Strings.archive_key(&"stink", Strings.ARCHIVE_TITLE_FIELD))
	assert_false(_texts(panel).has(title), "A locked card does not show its title")
	assert_true(_texts(panel).has(Strings.text(Strings.ARCHIVE_LOCKED)))
	_command(sim, &"start")
	_command(sim, &"abandon")
	var after: Dictionary = sim.snapshot()
	copy = after.duplicate(true)
	panel.update_snapshot(after)
	assert_eq(after, copy)
	assert_true(_texts(panel).has(title))
	assert_false(_texts(panel).has(Strings.text(Strings.ARCHIVE_LOCKED)))
	var note: String = Strings.text(Strings.archive_key(&"oldford", Strings.ARCHIVE_IMAGE_CONTEXT))
	assert_true(_texts(panel).any(func(text: String) -> bool: return text.contains(note)), "The context note shows")


func _texts(panel: Control) -> Array[String]:
	var texts: Array[String] = []
	for node: Node in panel.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return texts
