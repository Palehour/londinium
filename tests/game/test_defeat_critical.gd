extends GutTest

# The critical step of the defeat warnings (issue #350). The simulation fills snapshot["defeat_state"]; these tests
# hand-build that part so the UI is checked alone.

const CONDITIONS: Array[StringName] = [&"bankruptcy", &"hunger", &"depopulation"]

var _widget: DefeatCritical
var _entries: Array[StringName] = []


func before_each() -> void:
	Strings.use_default_locale()
	_entries.clear()
	_widget = DefeatCritical.new()
	add_child_autofree(_widget)
	_widget.critical_entered.connect(func(condition: StringName) -> void: _entries.append(condition))


func _state(levels: Dictionary) -> Dictionary:
	var states: Dictionary = {}
	for condition: StringName in levels:
		var entry: Array = levels[condition]
		states[condition] = {"level": entry[0], "seconds_left": entry[1]}
		if entry.size() > 2:
			states[condition]["cause"] = entry[2]
	return {"defeat_state": states, "defeat": {"causes": []}}


func _loader(_path: String) -> Variant:
	return AudioStreamWAV.new()


func _label_text(notice_condition: StringName, label_name: String) -> String:
	var notice: Node = _widget.get_node("Notice_%s" % notice_condition)
	return (notice.find_child(label_name, true, false) as Label).text


func test_no_notice_without_critical_state() -> void:
	_widget.show_state(_state({&"hunger": [&"warning", 40], &"bankruptcy": [&"normal", 200]}))
	assert_false(_widget.visible)
	assert_eq(_widget.rows(), [] as Array[Dictionary])


func test_snapshot_without_defeat_state_shows_nothing() -> void:
	_widget.show_state({"defeat": {"causes": []}})
	assert_false(_widget.visible)


func test_a_critical_condition_shows_name_seconds_and_cause() -> void:
	_widget.show_state(_state({&"hunger": [&"critical", 17]}))
	assert_true(_widget.visible)
	assert_eq(_label_text(&"hunger", "Name"), Strings.label(Strings.CONDITION_LABELS, &"hunger"))
	assert_eq(_label_text(&"hunger", "Left"), Strings.text(Strings.CRITICAL_LEFT) % 17)
	assert_eq(_label_text(&"hunger", "Cause"), Strings.label(Strings.CRITICAL_CAUSES, &"hunger"))
	assert_string_contains(_label_text(&"hunger", "Left"), "17")


func test_each_condition_has_its_own_icon_and_text_not_only_color() -> void:
	var shapes: Array[StringName] = []
	var causes: Array[String] = []
	var names: Array[String] = []
	var icon_texts: Array[String] = []
	for condition: StringName in CONDITIONS:
		assert_true(Strings.CRITICAL_CAUSES.has(condition))
		assert_true(Strings.CRITICAL_ICON_LABELS.has(condition))
		shapes.append(DefeatIcon.shape_for(condition))
		causes.append(Strings.label(Strings.CRITICAL_CAUSES, condition))
		names.append(Strings.label(Strings.CONDITION_LABELS, condition))
		icon_texts.append(Strings.label(Strings.CRITICAL_ICON_LABELS, condition))
	for list: Array in [shapes, causes, names, icon_texts]:
		var seen: Dictionary = {}
		for item: Variant in list:
			seen[item] = true
		assert_eq(seen.size(), CONDITIONS.size(), "all different: " + str(list))
	# Same palette for the three: what tells them apart is not the color.
	_widget.show_state(_state({&"bankruptcy": [&"critical", 5], &"hunger": [&"critical", 6], &"depopulation": [&"critical", 7]}))
	var icons: Array[DefeatIcon] = []
	for condition: StringName in CONDITIONS:
		icons.append(_widget.get_node("Notice_%s" % condition).find_child("Icon", true, false) as DefeatIcon)
	assert_eq(icons[0].ink, icons[1].ink)
	assert_eq(icons[1].ink, icons[2].ink)
	assert_ne(icons[0].shape, icons[1].shape)
	assert_ne(icons[1].shape, icons[2].shape)


func test_bankruptcy_under_a_receiver_keeps_its_condition_but_uses_the_receiver_text_and_icon() -> void:
	var state: Dictionary = _state({&"bankruptcy": [&"critical", 30, &"loan_bankruptcy"]})
	var found: Array[Dictionary] = DefeatCriticalRows.rows(state)
	assert_eq(found[0]["condition"], &"bankruptcy", "still the third condition, not a fourth")
	assert_eq(found[0]["cause"], &"loan_bankruptcy")
	_widget.show_state(state)
	assert_not_null(_widget.get_node_or_null("Notice_bankruptcy"))
	assert_null(_widget.get_node_or_null("Notice_loan_bankruptcy"))
	assert_eq(_label_text(&"bankruptcy", "Name"), Strings.label(Strings.CONDITION_LABELS, &"loan_bankruptcy"))
	assert_eq(_label_text(&"bankruptcy", "Cause"), Strings.label(Strings.CRITICAL_CAUSES, &"loan_bankruptcy"))
	var icon: DefeatIcon = _widget.get_node("Notice_bankruptcy").find_child("Icon", true, false) as DefeatIcon
	assert_eq(icon.shape, DefeatIcon.shape_for(&"loan_bankruptcy"))
	assert_ne(icon.shape, DefeatIcon.shape_for(&"bankruptcy"))


func test_a_plain_bankruptcy_without_a_cause_uses_the_normal_text() -> void:
	_widget.show_state(_state({&"bankruptcy": [&"critical", 30]}))
	assert_eq(_label_text(&"bankruptcy", "Cause"), Strings.label(Strings.CRITICAL_CAUSES, &"bankruptcy"))


func test_the_sound_follows_the_condition_not_the_cause() -> void:
	# Bankruptcy turns into the receiver's text mid-clock: same condition, so no second sound.
	_widget.show_state(_state({&"bankruptcy": [&"critical", 30]}))
	_widget.show_state(_state({&"bankruptcy": [&"critical", 29, &"loan_bankruptcy"]}))
	assert_eq(_entries, [&"bankruptcy"] as Array[StringName])


func test_the_receiver_notice_orders_with_the_others_by_seconds_left() -> void:
	_widget.show_state(_state({&"hunger": [&"critical", 50], &"bankruptcy": [&"critical", 20, &"loan_bankruptcy"]}))
	assert_eq(DefeatCriticalRows.conditions(_widget.rows()), [&"bankruptcy", &"hunger"] as Array[StringName])


func test_notices_stack_by_fewest_seconds_left() -> void:
	_widget.show_state(_state({&"bankruptcy": [&"critical", 40], &"hunger": [&"critical", 12], &"depopulation": [&"critical", 25]}))
	assert_eq(DefeatCriticalRows.conditions(_widget.rows()), [&"hunger", &"depopulation", &"bankruptcy"] as Array[StringName])
	var order: Array[String] = []
	for child: Node in _widget.get_children():
		if child.name.begins_with("Notice_"):
			order.append(child.name)
	assert_eq(order, ["Notice_hunger", "Notice_depopulation", "Notice_bankruptcy"] as Array[String])


func test_a_tie_keeps_a_fixed_order() -> void:
	var state: Dictionary = _state({&"depopulation": [&"critical", 9], &"bankruptcy": [&"critical", 9], &"hunger": [&"critical", 9]})
	assert_eq(DefeatCriticalRows.conditions(DefeatCriticalRows.rows(state)), [&"bankruptcy", &"hunger", &"depopulation"] as Array[StringName])
	var reversed: Dictionary = _state({&"hunger": [&"critical", 9], &"bankruptcy": [&"critical", 9], &"depopulation": [&"critical", 9]})
	assert_eq(DefeatCriticalRows.conditions(DefeatCriticalRows.rows(reversed)), [&"bankruptcy", &"hunger", &"depopulation"] as Array[StringName])


func test_the_notice_leaves_the_same_update_the_condition_stops_being_critical() -> void:
	_widget.show_state(_state({&"hunger": [&"critical", 3]}))
	assert_true(_widget.visible)
	_widget.show_state(_state({&"hunger": [&"normal", 180]}))
	assert_false(_widget.visible)
	assert_eq(_widget.rows(), [] as Array[Dictionary])


func test_a_lost_game_keeps_the_notice_to_the_end() -> void:
	var state: Dictionary = _state({&"hunger": [&"critical", 0]})
	state["defeat"] = {"causes": [&"hunger"]}
	_widget.show_state(state)
	assert_true(_widget.visible)
	assert_eq(_label_text(&"hunger", "Left"), Strings.text(Strings.CRITICAL_LEFT) % 0)


func test_texts_exist_in_both_languages() -> void:
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		for condition: StringName in CONDITIONS:
			for labels: Dictionary in [Strings.CRITICAL_CAUSES, Strings.CRITICAL_ICON_LABELS]:
				var key: StringName = labels[condition]
				assert_ne(Strings.text(key), String(key), "%s has no %s text" % [key, locale])
		assert_string_contains(Strings.text(Strings.CRITICAL_LEFT) % 8, "8")
	Strings.use_default_locale()


func test_the_event_fires_once_per_entry_and_again_after_leaving() -> void:
	var critical: Dictionary = _state({&"hunger": [&"critical", 10]})
	_widget.show_state(critical)
	_widget.show_state(critical)
	_widget.show_state(_state({&"hunger": [&"critical", 9]}))
	assert_eq(_entries, [&"hunger"] as Array[StringName])
	_widget.show_state(_state({&"hunger": [&"normal", 100]}))
	_widget.show_state(critical)
	assert_eq(_entries, [&"hunger", &"hunger"] as Array[StringName])


func test_each_condition_fires_on_its_own() -> void:
	_widget.show_state(_state({&"hunger": [&"critical", 10]}))
	_widget.show_state(_state({&"hunger": [&"critical", 9], &"bankruptcy": [&"critical", 20]}))
	assert_eq(_entries, [&"hunger", &"bankruptcy"] as Array[StringName])


func test_pausing_and_a_language_change_do_not_repeat_the_event() -> void:
	var critical: Dictionary = _state({&"depopulation": [&"critical", 15]})
	_widget.show_state(critical)
	# Paused: no tick, so the same snapshot arrives again when the panel redraws.
	_widget.show_state(critical)
	_widget.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	Strings.set_locale("en")
	_widget.show_state(critical)
	Strings.use_default_locale()
	assert_eq(_entries.size(), 1)


func test_reset_makes_the_next_entry_sound_again() -> void:
	var critical: Dictionary = _state({&"hunger": [&"critical", 10]})
	_widget.show_state(critical)
	_widget.reset_sound()
	_widget.show_state(critical)
	assert_eq(_entries.size(), 2)


func test_sound_without_data_says_why_and_does_not_play() -> void:
	_widget.configure_sound(null)
	assert_eq(_widget.sound.status, DefeatCriticalSound.STATUS_NO_DATA)
	_widget.show_state(_state({&"hunger": [&"critical", 10]}))
	assert_eq(_entries.size(), 1, "the entry is still reported")
	assert_null(_widget.sound.stream)
	var diagnostic: Label = _widget.get_child(_widget.get_child_count() - 1) as Label
	assert_eq(diagnostic.text, Strings.text(Strings.CRITICAL_SOUND_DIAGNOSTICS[DefeatCriticalSound.STATUS_NO_DATA]))


func test_sound_ids_are_validated() -> void:
	var sound: DefeatCriticalSound = DefeatCriticalSound.new()
	for empty: Variant in [null, "", "sin dato", "  Sin Dato "]:
		sound.configure(empty, _loader)
		assert_eq(sound.status, DefeatCriticalSound.STATUS_NO_DATA, str(empty))
	for bad: Variant in ["../x", "Has Space", 7, "a.b"]:
		sound.configure(bad, _loader)
		assert_eq(sound.status, DefeatCriticalSound.STATUS_INVALID_ID, str(bad))
	sound.configure("no_such_sound")
	assert_eq(sound.status, DefeatCriticalSound.STATUS_MISSING_ASSET)
	assert_false(sound.is_ready())
	sound.configure("fixture_sound", _loader)
	assert_eq(sound.status, DefeatCriticalSound.STATUS_OK)
	assert_true(sound.stream is AudioStreamWAV)


func test_a_resolved_sound_is_loaded_from_the_ui_audio_folder() -> void:
	var paths: Array[String] = []
	var spy: Callable = func(path: String) -> Variant:
		paths.append(path)
		return null
	var sound: DefeatCriticalSound = DefeatCriticalSound.new()
	sound.configure("fixture_sound", spy)
	assert_eq(paths, ["res://assets/audio/ui/fixture_sound.ogg", "res://assets/audio/ui/fixture_sound.wav"] as Array[String])


func test_a_ready_sound_plays_once_per_entry_and_shows_no_diagnostic() -> void:
	_widget.configure_sound("fixture_sound", _loader)
	var critical: Dictionary = _state({&"hunger": [&"critical", 10]})
	_widget.show_state(critical)
	var player: AudioStreamPlayer = _widget.get("_player") as AudioStreamPlayer
	assert_true(player.stream is AudioStreamWAV)
	assert_eq(_widget.get_child_count(), 2, "the player and one notice, no diagnostic line")
	player.stream = null
	_widget.show_state(critical)
	assert_null(player.stream, "a repeated snapshot does not start it again")
	_widget.show_state(_state({&"hunger": [&"normal", 100]}))
	_widget.show_state(critical)
	assert_true(player.stream is AudioStreamWAV, "a new entry does")


func test_panel_without_defeat_state_keeps_working_and_critical_leaves_the_warning_line() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var session: GameSession = GameSession.new(loaded.catalog, Params.new(loaded.catalog, RoleDef.new()))
	var clock: SimClock = SimClock.new()
	clock.simulation = session.simulation
	add_child_autofree(clock)
	clock.set_process(false)
	var panel: StatsPanel = StatsPanel.new()
	panel.setup(session, clock)
	add_child_autofree(panel)
	var snapshot: Dictionary = session.get_snapshot()
	snapshot.erase("defeat_state")
	panel.update_snapshot(snapshot)
	var banner: DefeatCritical = panel.find_child("DefeatCritical", true, false) as DefeatCritical
	assert_eq(banner.rows(), [] as Array[Dictionary], "no critical notice without defeat_state")
	snapshot["defeat"][&"hunger"]["status"] = &"warning"
	snapshot["defeat"][&"hunger"]["timer_running"] = true
	snapshot["defeat_state"] = {&"hunger": {"level": &"critical", "seconds_left": 20}}
	panel.update_snapshot(snapshot)
	assert_true(banner.visible)
	assert_eq((panel.get("_alert") as Label).text, "", "hunger is not said twice")
	panel.reset_critical()
	assert_eq(banner.sound.status, DefeatCriticalSound.STATUS_NO_DATA)


func _panel_with_session() -> Array:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var session: GameSession = GameSession.new(loaded.catalog, Params.new(loaded.catalog, RoleDef.new()))
	var clock: SimClock = SimClock.new()
	clock.simulation = session.simulation
	add_child_autofree(clock)
	clock.set_process(false)
	var panel: StatsPanel = StatsPanel.new()
	panel.setup(session, clock)
	add_child_autofree(panel)
	return [panel, session]


func test_panel_counts_one_entry_per_condition_and_reset_critical_rearms_it() -> void:
	var made: Array = _panel_with_session()
	var panel: StatsPanel = made[0]
	var session: GameSession = made[1]
	var banner: DefeatCritical = panel.find_child("DefeatCritical", true, false) as DefeatCritical
	banner.critical_entered.connect(func(condition: StringName) -> void: _entries.append(condition))
	var snapshot: Dictionary = session.get_snapshot()
	snapshot["defeat_state"] = {&"depopulation": {"level": &"critical", "seconds_left": 12}}
	panel.update_snapshot(snapshot)
	panel.update_snapshot(snapshot)
	Strings.set_locale("en")
	panel.update_snapshot(snapshot)
	Strings.use_default_locale()
	assert_eq(_entries, [&"depopulation"] as Array[StringName])
	panel.reset_critical()
	panel.update_snapshot(snapshot)
	assert_eq(_entries, [&"depopulation", &"depopulation"] as Array[StringName])


func test_a_restarted_session_rearms_the_sound_and_clears_the_notice() -> void:
	var made: Array = _panel_with_session()
	var panel: StatsPanel = made[0]
	var session: GameSession = made[1]
	var banner: DefeatCritical = panel.find_child("DefeatCritical", true, false) as DefeatCritical
	var snapshot: Dictionary = session.get_snapshot()
	snapshot["defeat_state"] = {&"hunger": {"level": &"critical", "seconds_left": 9}}
	panel.update_snapshot(snapshot)
	assert_true(banner.visible)
	session.restart()
	panel.reset_critical()
	panel.update_snapshot(session.get_snapshot())
	assert_eq(banner.rows(), [] as Array[Dictionary], "a fresh game has no critical state")
	assert_eq(banner.find_children("Notice_*", "PanelContainer", true, false).size(), 0)
	assert_ne(banner.sound.status, DefeatCriticalSound.STATUS_OK, "no sound is chosen yet, so none is claimed")


# Steam Deck size (D-048): three notices at once leave the panel's scroll area most of the screen and every row inside
# the panel width, in both languages.
func test_three_notices_fit_the_1280x800_panel_in_both_languages() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	view.set("mods_root", "user://test_defeat_critical")
	view.set("saves_root", "user://test_defeat_critical")
	viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var panel: StatsPanel = view.get("_stats_panel") as StatsPanel
	var session: GameSession = view.get("session") as GameSession
	var snapshot: Dictionary = session.get_snapshot()
	snapshot["defeat_state"] = {
		&"bankruptcy": {"level": &"critical", "seconds_left": 41, "cause": &"loan_bankruptcy"},
		&"hunger": {"level": &"critical", "seconds_left": 42},
		&"depopulation": {"level": &"critical", "seconds_left": 43},
	}
	var room: float = presentation.layout["panel_width"] - 2.0 * presentation.layout["panel_margin"]
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		panel.update_snapshot(snapshot)
		await get_tree().process_frame
		await get_tree().process_frame
		var banner: DefeatCritical = panel.find_child("DefeatCritical", true, false) as DefeatCritical
		assert_eq(banner.rows().size(), 3)
		assert_lte(banner.size.y, 800.0 * 0.35, "Three notices stay a third of the screen at most (%s)" % locale)
		var scroll: ScrollContainer = panel.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		assert_gte(scroll.size.y, 800.0 * 0.4, "The controls keep their room (%s)" % locale)
		assert_lte(banner.get_combined_minimum_size().x, room, "Banner width (%s)" % locale)
		for node: Node in banner.find_children("*", "HBoxContainer", true, false):
			assert_lte((node as HBoxContainer).get_combined_minimum_size().x, room, "Row %s (%s)" % [node.get_path(), locale])
	Strings.use_default_locale()


# The settings of the critical notices (issue #350): "sin dato" is said, never read as zero.
func _config(thresholds: Dictionary, sound: Variant, errors: Array[String]) -> Dictionary:
	var config: Dictionary = {"bankruptcy": null, "hunger": null, "depopulation": null, "critical_sound": sound,
		"complete": errors.is_empty(), "incomplete": not errors.is_empty(), "errors": errors}
	for condition: StringName in thresholds:
		config[condition] = thresholds[condition]
	return {"defeat_critical_config": config, "defeat": {"causes": []}}


func test_pending_settings_show_a_compact_line_even_without_any_notice() -> void:
	var snapshot: Dictionary = _config({}, null, ["no data for bankruptcy", "no data for hunger"] as Array[String])
	_widget.show_state(snapshot)
	assert_true(_widget.visible)
	assert_eq(_widget.rows(), [] as Array[Dictionary], "no false notice")
	assert_eq(_widget.get_child_count(), 2, "the player and the one line")
	var line: Label = _widget.get_node("ConfigPending") as Label
	for condition: StringName in CONDITIONS:
		assert_string_contains(line.text, Strings.label(Strings.CONDITION_LABELS, condition))
	assert_string_contains(line.text, Strings.text(Strings.CRITICAL_CONFIG_SOUND))
	assert_string_contains(line.tooltip_text, "no data for bankruptcy")


func test_only_the_missing_settings_are_named() -> void:
	var snapshot: Dictionary = _config({&"bankruptcy": 30, &"hunger": 20}, "sin dato", ["no data for depopulation"] as Array[String])
	_widget.show_state(snapshot)
	var text: String = _widget.config_text()
	assert_string_contains(text, Strings.label(Strings.CONDITION_LABELS, &"depopulation"))
	assert_false(text.contains(Strings.label(Strings.CONDITION_LABELS, &"bankruptcy")))
	assert_false(text.contains(Strings.label(Strings.CONDITION_LABELS, &"hunger")))


func test_a_threshold_of_zero_is_a_value_not_a_missing_one() -> void:
	var snapshot: Dictionary = _config({&"bankruptcy": 0, &"hunger": 0, &"depopulation": 0}, "x", ["something else is wrong"] as Array[String])
	_widget.show_state(snapshot)
	assert_eq(_widget.config_text(), Strings.text(Strings.CRITICAL_CONFIG_INVALID) % 1)


func test_complete_settings_or_no_settings_in_the_snapshot_say_nothing() -> void:
	_widget.show_state(_config({&"bankruptcy": 30, &"hunger": 20, &"depopulation": 10}, "x", [] as Array[String]))
	assert_eq(_widget.config_text(), "")
	assert_false(_widget.visible)
	_widget.show_state({"defeat": {"causes": []}})
	assert_false(_widget.visible)


func test_the_settings_line_sits_below_the_notices_and_follows_the_language() -> void:
	var snapshot: Dictionary = _config({}, null, ["x"] as Array[String])
	snapshot["defeat_state"] = {"hunger": {"level": &"critical", "seconds_left": 12}}
	_widget.show_state(snapshot)
	assert_eq(_widget.get_child(_widget.get_child_count() - 1).name, "ConfigPending")
	var spanish: String = _widget.config_text()
	Strings.set_locale("en")
	_widget.show_state(snapshot)
	assert_ne(_widget.config_text(), spanish)
	assert_eq((_widget.get_node("ConfigPending") as Label).text, _widget.config_text())
	assert_eq(_entries.size(), 1, "the notice sounded once, the line is not one")
	Strings.use_default_locale()


func test_the_line_leaves_when_the_settings_are_completed() -> void:
	_widget.show_state(_config({}, null, ["x"] as Array[String]))
	assert_true(_widget.visible)
	_widget.show_state(_config({&"bankruptcy": 30, &"hunger": 20, &"depopulation": 10}, null, [] as Array[String]))
	assert_false(_widget.visible)
	assert_null(_widget.get_node_or_null("ConfigPending"))
