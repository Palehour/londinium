extends GutTest

# The lessons in the history view (issue #87, D-120): with the incidents on, a line per district with its lessons by
# attribute and the severity and deaths the cholera had there, or that it has not come yet. Everything is read from the
# snapshot; with the incidents off (D-122) there is nothing, and the history tab looks as before.

const TRIAL: StringName = &"incidents_trial"
const WEST: StringName = &"west"
const EAST: StringName = &"east"

var _catalog: DataCatalog


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func after_each() -> void:
	Strings.use_default_locale()


func _entry(safety: int, health: int, order: int) -> Dictionary:
	return {ServiceSystem.SAFETY: {"lessons": safety}, ServiceSystem.HEALTH: {"lessons": health},
		ServiceSystem.ORDER: {"lessons": order}}


func _names() -> Dictionary[StringName, String]:
	return {WEST: "West", EAST: "East"}


func test_with_the_incidents_off_there_are_no_lines() -> void:
	assert_eq(DistrictLessons.lines({"enabled": false, "districts": {}}, _names()), [] as Array[String])


func test_each_district_shows_its_lessons_and_the_severity_it_had() -> void:
	Strings.set_locale("es")
	var west: Dictionary = _entry(1, 3, 0)
	west["crisis"] = {"severity": 0.35, "deaths": 7}
	var lines: Array[String] = DistrictLessons.lines({"enabled": true, "districts": {WEST: west,
		EAST: _entry(0, 0, 2)}}, _names())
	assert_eq(lines, [
		"Lecciones por distrito (duran el capítulo)",
		"West · lecciones: Seguridad 1 · Salud 3 · Orden 0 · cólera: gravedad 35 % · 7 muertes",
		"East · lecciones: Seguridad 0 · Salud 0 · Orden 2 · el cólera todavía no llegó",
	] as Array[String])


func test_a_map_without_districts_is_the_whole_city() -> void:
	Strings.set_locale("en")
	var lines: Array[String] = DistrictLessons.lines({"enabled": true,
		"districts": {WaterSystem.DEFAULT_DISTRICT: _entry(0, 1, 0)}}, {} as Dictionary[StringName, String])
	assert_eq(lines[1], "Whole city · lessons: Safety 0 · Health 1 · Order 0 · cholera has not come yet")


# The view of the trial scenario lists every district of its map; the demo, with the incidents off, lists none.
func test_the_history_tab_shows_the_lessons_only_with_the_incidents_on() -> void:
	for case: Array in [[TRIAL, true], [&"victorian_demo", false]]:
		var session: GameSession = GameSession.new(_catalog, Params.new(_catalog, RoleDef.new()), case[0])
		var look: StatsPresentation = StatsPresentation.new()
		look.load_data()
		var tab: TimelineTab = TimelineTab.new()
		add_child_autofree(tab)
		tab.setup(session, look)
		tab.refresh()
		var label: Label = tab.get("_lessons") as Label
		assert_eq(label.visible, case[1], str(case[0]))
		var expected: Array[String] = DistrictLessons.lines(session.get_snapshot()["incidents"],
			session.context.map.district_names)
		assert_eq(label.text, "\n".join(expected), str(case[0]))
		if case[1]:
			assert_eq(expected.size(), 1 + session.context.map.district_names.size())
