extends GutTest

# The neutral narrator (issue #73, D-137): every notice is born from an event of the cause log, mapped by
# data/ui/narrator.json. It pauses on a defeat warning and at the start of a crisis (D-145), and does not flood the
# screen (D-146): a wait between repeats by priority, repeats within the merge window as one notice, at most
# max_visible on screen, and an attention budget a minute whose overflow goes to a digest. Times are game seconds.
# A subject's first cause waits out a grace before it speaks (D-198); a change of that subject within it cancels it.

const BAKERIES: int = 6

var _serial: int = 0


func _config(raw: Dictionary = {}, kinds: Array[StringName] = StatsHistory.CAUSE_KINDS) -> NarratorConfig:
	var config: NarratorConfig = NarratorConfig.new()
	if raw.is_empty():
		config.load_data()
	else:
		config.validate(raw, kinds)
	assert_eq(config.errors, [] as Array[String])
	return config


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(NarratorConfig.PATH))


func _entry(second: int, kind: StringName, subject: StringName, cause: StringName, count: int = 0) -> Dictionary:
	var event: Dictionary = {"second": second, "kind": kind, "subject": subject, "cause": cause}
	if count > 0:
		event["count"] = count
	_serial += 1
	return {"serial": _serial - 1, "event": event}


# A narrator that has already seen the starting cause of every subject the tests use: a first cause is a starting
# state, not a change, so it is never announced.
func _narrator(config: NarratorConfig = null) -> Narrator:
	_serial = 0
	var known: Array[Dictionary] = []
	for condition: StringName in SeriesRegistry.DEFEAT_CONDITIONS:
		known.append(_entry(0, &"defeat", condition, &"ok"))
	for member: StringName in [&"worker", &"artisan"]:
		known.append(_entry(0, &"emigration", member, &"none"))
	for good: StringName in [&"tea", &"flour"]:
		known.append(_entry(0, &"import", good, &"ok"))
	for index: int in BAKERIES:
		known.append(_entry(0, &"building", _bakery(index), &"ok"))
	known.append(_entry(0, &"victory", &"stage_1", &"pending"))
	known.append(_entry(0, &"policy", &"tax_rate", &"0.25"))
	var narrator: Narrator = Narrator.new(config if config != null else _config())
	narrator.start(known, _serial, 0)
	return narrator


func _bakery(index: int) -> StringName:
	return StringName("bakery@%d,0" % (index * 3))


func _feed(narrator: Narrator, entries: Array[Dictionary], now: int) -> void:
	narrator.feed(entries, now)


# The notices up, without the digest: a repeat held back by its wait reaches the digest, which comes on its own.
func _announced(narrator: Narrator) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for notice: Dictionary in narrator.visible():
		if notice["key"] != Narrator.DIGEST_KEY:
			found.append(notice)
	return found


func _visible_keys(narrator: Narrator) -> Array[StringName]:
	var keys: Array[StringName] = []
	for notice: Dictionary in narrator.visible():
		keys.append(notice["key"])
	return keys


# One event of each priority, by the rules of data/ui/narrator.json.
func _one_of(priority: StringName, second: int, subject_index: int = 0) -> Dictionary:
	match priority:
		&"critical":
			return _entry(second, &"defeat", SeriesRegistry.DEFEAT_CONDITIONS[subject_index], &"defeat")
		&"high":
			return _entry(second, &"emigration", [&"worker", &"artisan"][subject_index], &"hungry_leaving")
		&"normal":
			return _entry(second, &"import", [&"tea", &"flour"][subject_index], &"no_wharf_for_imports")
	# Waits and merges go by kind and cause, so a repeat keeps the same value.
	return _entry(second, &"policy", &"tax_rate", &"0.3")


func test_the_same_log_always_gives_the_same_notices() -> void:
	var lists: Array = []
	for run: int in 2:
		var narrator: Narrator = _narrator()
		var entries: Array[Dictionary] = [_one_of(&"high", 5), _one_of(&"normal", 6)]
		for index: int in BAKERIES:
			entries.append(_entry(7 + index, &"building", _bakery(index), &"no_workers"))
		entries.append(_one_of(&"critical", 20))
		_feed(narrator, entries, 20)
		narrator.advance(130)
		lists.append(narrator.visible())
	assert_false(lists[0].is_empty())
	assert_eq(lists[0], lists[1])


func test_a_starting_state_and_a_loaded_history_are_not_announced() -> void:
	_serial = 0
	var saved: Array[Dictionary] = [_entry(1, &"defeat", &"bankruptcy", &"ok"), _entry(50, &"defeat", &"bankruptcy", &"warning")]
	var narrator: Narrator = Narrator.new(_config())
	narrator.start(saved, _serial, 60)
	_feed(narrator, saved, 60)
	assert_eq(narrator.visible(), [] as Array[Dictionary], "what happened before the load is not announced again")
	assert_false(narrator.take_pause())
	_feed(narrator, [_entry(61, &"building", &"mill@1,1", &"no_workers")], 61)
	assert_eq(narrator.visible(), [] as Array[Dictionary], "a new subject's first cause waits out its grace (D-198)")
	_feed(narrator, [_entry(70, &"defeat", &"bankruptcy", &"defeat")], 70)
	assert_eq(_visible_keys(narrator), [&"narrator.defeat.defeat"] as Array[StringName], "what comes after the load is")
	# D-198: the new mill's first cause shows once its grace is met, and the loaded history still says nothing.
	var grace: int = _config().first_cause_grace_s
	narrator.advance(61 + grace - 1)
	assert_does_not_have(_visible_keys(narrator), &"narrator.building.stopped", "a second short of the grace it is held")
	narrator.advance(61 + grace)
	var keys: Array[StringName] = _visible_keys(narrator)
	assert_has(keys, &"narrator.building.stopped", "the first cause of the new mill is offered")
	assert_does_not_have(keys, &"narrator.defeat.warning", "the loaded history says nothing even past the grace")
	assert_false(narrator.take_pause(), "its warning never asked for a pause")


# D-198: within the grace a change of the same subject cancels its first cause: the state it would announce is over.
func test_a_change_within_the_grace_cancels_the_first_cause() -> void:
	var narrator: Narrator = _narrator()
	var grace: int = _config().first_cause_grace_s
	_feed(narrator, [_entry(10, &"building", &"mill@1,1", &"no_workers"), _entry(10, &"building", &"mill@2,2", &"no_workers")], 10)
	_feed(narrator, [_entry(11, &"building", &"mill@1,1", &"ok")], 11)
	narrator.advance(10 + grace)
	assert_eq(_visible_keys(narrator), [&"narrator.building.stopped"] as Array[StringName],
		"only the mill nobody fixed speaks")
	assert_eq(narrator.visible()[0]["merged"], 1)
	_feed(narrator, [_entry(30, &"building", &"mill@1,1", &"no_flour")], 30)
	assert_eq(_visible_keys(narrator), [&"narrator.building.stopped"] as Array[StringName],
		"a later change of the canceled mill shows at once, no grace")


# D-198: first causes that share a cause and a second are one notice: the merge window does the rest.
func test_first_causes_of_one_cause_and_second_merge_into_one() -> void:
	var narrator: Narrator = _narrator()
	var entries: Array[Dictionary] = []
	for index: int in 3:
		entries.append(_entry(20, &"building", StringName("mill@%d,3" % index), &"no_workers"))
	_feed(narrator, entries, 20)
	assert_eq(narrator.visible(), [] as Array[Dictionary], "within the grace nothing is up")
	narrator.advance(20 + _config().first_cause_grace_s)
	assert_eq(narrator.visible().size(), 1, "three first causes of one cause and second are one notice")
	assert_eq(narrator.visible()[0]["merged"], 3)


# D-198: pendings that come due together are offered by serial, the order the log holds them.
func test_due_pendings_are_offered_in_serial_order() -> void:
	var narrator: Narrator = _narrator()
	var entries: Array[Dictionary] = [_entry(10, &"import", &"wool", &"no_wharf_for_imports"),
		_entry(10, &"building", &"mill@9,9", &"no_workers")]
	_feed(narrator, entries, 10)
	narrator.advance(10 + _config().first_cause_grace_s)
	assert_eq(_visible_keys(narrator), [&"narrator.import.stopped", &"narrator.building.stopped"] as Array[StringName],
		"the earlier serial speaks first")


# D-198: the pendings are UI state, not saved state: a new game or a load does not inherit them.
func test_a_fresh_start_clears_the_pendings() -> void:
	var narrator: Narrator = _narrator()
	var entry: Dictionary = _entry(10, &"building", &"mill@1,1", &"no_workers")
	_feed(narrator, [entry], 10)
	narrator.start([entry], int(entry["serial"]) + 1, 10)
	narrator.advance(10 + _config().first_cause_grace_s + 1)
	assert_eq(narrator.visible(), [] as Array[Dictionary], "no pending survives a fresh start")


func test_a_repeat_waits_the_cooldown_of_its_priority() -> void:
	var config: NarratorConfig = _config()
	for priority: StringName in NarratorConfig.PRIORITIES:
		var narrator: Narrator = _narrator(config)
		var start: int = 100
		_feed(narrator, [_one_of(priority, start)], start)
		assert_eq(_announced(narrator).size(), 1, String(priority))
		narrator.dismiss(_announced(narrator)[0]["id"])
		var wait: int = config.cooldown_s[priority]
		if wait > 0:
			_feed(narrator, [_one_of(priority, start + wait - 1, 0)], start + wait - 1)
			assert_eq(_announced(narrator).size(), 0, "%s: inside its %d s wait it is not shown again" % [priority, wait])
		_feed(narrator, [_one_of(priority, start + wait + 1, 0)], start + wait + 1)
		assert_eq(_announced(narrator).size(), 1, "%s: after %d s it is a notice again" % [priority, wait])


func test_repeats_within_the_merge_window_are_one_notice() -> void:
	var narrator: Narrator = _narrator()
	var entries: Array[Dictionary] = []
	for index: int in BAKERIES:
		entries.append(_entry(10 + index, &"building", _bakery(index), &"no_workers"))
	_feed(narrator, entries, 10 + BAKERIES)
	assert_eq(narrator.visible().size(), 1, "six bakeries without workers within 10 s are one notice")
	assert_eq(narrator.visible()[0]["merged"], BAKERIES)
	var window: int = _config().group_window_s
	var critical: Narrator = _narrator()
	_feed(critical, [_one_of(&"critical", 10, 0), _one_of(&"critical", 10 + window, 1)], 10 + window)
	assert_eq(critical.visible().size(), 1, "even what is critical merges inside the window")
	assert_eq(critical.visible()[0]["merged"], 2)
	_feed(critical, [_one_of(&"critical", 10 + 2 * window + 1, 2)], 10 + 2 * window + 1)
	assert_eq(critical.visible().size(), 2, "with no wait, past the window it is a new notice")


func test_never_more_than_max_visible_and_a_critical_stays() -> void:
	var narrator: Narrator = _narrator()
	var max_visible: int = _config().max_visible
	var entries: Array[Dictionary] = [_one_of(&"critical", 1), _one_of(&"high", 2),
		_entry(3, &"emigration", &"artisan", &"unhappy_leaving"), _one_of(&"normal", 4),
		_entry(5, &"building", _bakery(0), &"no_workers")]
	for entry: Dictionary in entries:
		_feed(narrator, [entry], int(entry["event"]["second"]))
		assert_lte(narrator.visible().size(), max_visible)
	var keys: Array[StringName] = _visible_keys(narrator)
	assert_eq(keys.size(), max_visible)
	assert_has(keys, &"narrator.defeat.defeat", "a critical notice is never pushed out")
	assert_does_not_have(keys, &"narrator.import.stopped", "the oldest of the lowest priority went out")
	assert_has(keys, &"narrator.building.stopped")


func test_a_critical_waits_while_every_slot_holds_a_critical() -> void:
	var raw: Dictionary = _raw()
	for rule: Dictionary in raw["rules"]:
		if rule.has("priority"):
			rule["priority"] = "critical"
	var narrator: Narrator = _narrator(_config(raw))
	var entries: Array[Dictionary] = [_one_of(&"critical", 1), _one_of(&"high", 2), _one_of(&"normal", 3),
		_one_of(&"low", 4), _entry(5, &"building", _bakery(0), &"no_workers")]
	_feed(narrator, entries, 5)
	assert_eq(narrator.visible().size(), _config().max_visible)
	assert_eq(narrator.queued_count(), 1, "the fifth critical waits; none is pushed out")
	narrator.dismiss(narrator.visible()[0]["id"])
	assert_eq(narrator.visible().size(), _config().max_visible, "closing one lets the waiting one in")
	assert_eq(narrator.queued_count(), 0)
	assert_has(_visible_keys(narrator), &"narrator.building.stopped")


func test_past_the_budget_normal_and_low_go_to_the_digest() -> void:
	var narrator: Narrator = _narrator()
	var highs: Array[Dictionary] = [_entry(1, &"emigration", &"worker", &"hungry_leaving"),
		_entry(2, &"emigration", &"artisan", &"unhappy_leaving"), _entry(3, &"victory", &"stage_1", &"completed")]
	_feed(narrator, highs, 3)
	assert_eq(narrator.visible().size(), 3, "three high notices spend the six points")
	_feed(narrator, [_one_of(&"normal", 4), _one_of(&"low", 5)], 5)
	assert_eq(narrator.visible().size(), 3, "normal and low past the budget are not shown on their own")
	assert_eq(narrator.digest_size(), 2)
	_feed(narrator, [_one_of(&"critical", 6)], 6)
	assert_has(_visible_keys(narrator), &"narrator.defeat.defeat", "what is critical spends no budget")
	for notice: Dictionary in narrator.visible():
		narrator.dismiss(notice["id"])
	var later: int = 5 + 61
	_feed(narrator, [_entry(later, &"building", _bakery(0), &"no_workers")], later)
	assert_has(_visible_keys(narrator), &"narrator.building.stopped", "a minute later the budget is back")


func test_the_digest_comes_every_interval_and_only_with_something_in_it() -> void:
	var narrator: Narrator = _narrator()
	var interval: int = _config().digest_interval_s
	var highs: Array[Dictionary] = [_entry(1, &"emigration", &"worker", &"hungry_leaving"),
		_entry(2, &"emigration", &"artisan", &"unhappy_leaving"), _entry(3, &"victory", &"stage_1", &"completed")]
	_feed(narrator, highs, 3)
	_feed(narrator, [_one_of(&"normal", 4), _one_of(&"normal", 5, 1), _one_of(&"low", 6)], 6)
	narrator.advance(interval - 1)
	assert_does_not_have(_visible_keys(narrator), Narrator.DIGEST_KEY, "not before the interval")
	narrator.advance(interval)
	var digest: Array = narrator.visible().filter(func(notice: Dictionary) -> bool: return notice["key"] == Narrator.DIGEST_KEY)
	assert_eq(digest.size(), 1)
	var items: Array = digest[0]["items"]
	assert_eq(items.size(), 2, "one line per kind and cause")
	assert_eq(items[0]["count"], 2, "the two stopped imports")
	assert_eq(items[1]["count"], 1)
	assert_eq(narrator.digest_size(), 0)
	narrator.dismiss(digest[0]["id"])
	narrator.advance(2 * interval)
	assert_does_not_have(_visible_keys(narrator), Narrator.DIGEST_KEY, "an empty digest is not a notice")


func test_a_defeat_warning_pauses_unless_data_turns_it_off() -> void:
	var narrator: Narrator = _narrator()
	_feed(narrator, [_entry(10, &"defeat", &"bankruptcy", &"warning")], 10)
	assert_true(narrator.take_pause(), "D-145: a defeat warning pauses")
	assert_false(narrator.take_pause(), "once")
	_feed(narrator, [_entry(20, &"defeat", &"hunger", &"defeat")], 20)
	assert_false(narrator.take_pause(), "only the rules that say so pause")
	var raw: Dictionary = _raw()
	raw["pause_on_critical"] = false
	var quiet: Narrator = _narrator(_config(raw))
	_feed(quiet, [_entry(10, &"defeat", &"bankruptcy", &"warning")], 10)
	assert_false(quiet.take_pause(), "pause_on_critical off: only the notice")
	assert_eq(quiet.visible().size(), 1)


# The crisis kind is not in the log yet (D-147): the hook is tested with a kind added only here.
func test_a_crisis_pauses_only_when_events_json_lets_it() -> void:
	var raw: Dictionary = _raw()
	raw["rules"].append({"kind": "incident", "cause": "started", "priority": "critical",
		"key": "narrator.defeat.warning", "pause": true, "crisis": true})
	var kinds: Array[StringName] = StatsHistory.CAUSE_KINDS.duplicate()
	kinds.append(&"incident")
	for allowed: bool in [false, true]:
		var narrator: Narrator = _narrator(_config(raw, kinds))
		narrator.crisis_pause_allowed = allowed
		_feed(narrator, [_entry(10, &"incident", &"old_ford", &"none")], 10)
		_feed(narrator, [_entry(20, &"incident", &"old_ford", &"started")], 20)
		assert_eq(narrator.visible().size(), 1)
		assert_eq(narrator.take_pause(), allowed, "defeat_pause %s" % allowed)


func test_an_intermittent_building_is_one_notice_whose_count_grows() -> void:
	var narrator: Narrator = _narrator()
	var flip: Dictionary = _entry(10, &"building", _bakery(0), CauseLog.INTERMITTENT, 1)
	_feed(narrator, [flip], 10)
	assert_eq(narrator.visible().size(), 1)
	assert_eq(narrator.visible()[0]["count"], 1)
	var counted: Dictionary = flip.duplicate(true)
	counted["event"]["count"] = 5
	assert_lte(narrator.read_from(), int(flip["serial"]), "it reads that event again to follow its count")
	_feed(narrator, [counted], 15)
	assert_eq(narrator.visible().size(), 1, "the same notice, not a new one")
	assert_eq(narrator.visible()[0]["count"], 5)


func test_a_notice_carries_its_cause_id_map_target_and_graph_link() -> void:
	var narrator: Narrator = _narrator()
	var entry: Dictionary = _entry(40, &"building", _bakery(1), &"no_flour")
	_feed(narrator, [entry], 40)
	var notice: Dictionary = narrator.visible()[0]
	assert_eq(notice["cause_id"], entry["serial"], "the serial of the event in the cause log")
	assert_eq(notice["map_target"], {"type": &"building", "id": &"bakery", "cell": Vector2i(3, 0)})
	assert_eq(notice["graph_link"], {"series": &"jobs_filled:bakery", "second": 40})
	var emigration: Dictionary = _entry(41, &"emigration", &"worker", &"hungry_leaving")
	_feed(narrator, [emigration], 41)
	var found: Dictionary = narrator.visible()[1]
	assert_eq(found["map_target"], {"type": &"none"}, "no district is a subject yet: none")
	assert_eq(found["graph_link"], {"series": &"emigration:worker:hunger", "second": 41})


func test_every_series_a_rule_names_exists_in_the_history() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	var subjects: Dictionary[StringName, StringName] = {&"defeat": &"bankruptcy", &"victory": &"stage_1",
		&"emigration": &"worker", &"building": &"mill@0,0", &"import": &"tea", &"policy": &"tax_rate"}
	for rule: Dictionary in _config().rules:
		if rule["silent"] or rule["series"].is_empty():
			continue
		var link: Dictionary = NarratorText.graph_link(subjects[rule["kind"]], rule["series"], 1)
		assert_has(look.history_series, link["series"], "%s: %s" % [rule["key"], link["series"]])


func test_a_notice_leaves_after_its_lifetime_and_a_critical_does_not() -> void:
	var config: NarratorConfig = _config()
	var narrator: Narrator = _narrator(config)
	_feed(narrator, [_one_of(&"high", 100), _one_of(&"critical", 100)], 100)
	assert_eq(narrator.visible().size(), 2)
	narrator.advance(100 + config.toast_lifetime_s[&"high"] - 1)
	assert_eq(narrator.visible().size(), 2, "still inside its lifetime")
	narrator.advance(100 + config.toast_lifetime_s[&"high"])
	assert_eq(narrator.visible().size(), 1, "the high one went")
	assert_eq(narrator.visible()[0]["priority"], NarratorConfig.CRITICAL)
	narrator.advance(100 + 100000)
	assert_eq(narrator.visible().size(), 1, "a critical stays until it is closed")


func test_a_repeat_restarts_the_lifetime_and_the_clock_is_game_seconds() -> void:
	var config: NarratorConfig = _config()
	var narrator: Narrator = _narrator(config)
	_feed(narrator, [_one_of(&"normal", 100)], 100)
	_feed(narrator, [_one_of(&"normal", 105)], 105)
	var lifetime: int = config.toast_lifetime_s[&"normal"]
	narrator.advance(100 + lifetime)
	assert_eq(narrator.visible().size(), 1, "the repeat at 105 kept it up")
	narrator.advance(105 + lifetime)
	assert_eq(narrator.visible().size(), 0)


func test_the_target_falls_back_from_building_to_tile_to_none() -> void:
	var target: Dictionary = NarratorText.map_target(&"mill@4,5", NarratorConfig.TARGET_SUBJECT_CELL)
	var yes: Callable = func(_cell: Vector2i) -> bool: return true
	var no: Callable = func(_cell: Vector2i) -> bool: return false
	assert_eq(NarratorText.resolve_target(target, yes, yes)["type"], &"building")
	assert_eq(NarratorText.resolve_target(target, no, yes), {"type": &"tile", "cell": Vector2i(4, 5)}, "demolished: its tile")
	assert_eq(NarratorText.resolve_target(target, no, no), {"type": &"none"}, "nothing left: no button")
	assert_eq(NarratorText.map_target(&"mill@4,5", NarratorConfig.TARGET_NONE), {"type": &"none"})
	assert_eq(NarratorText.map_target(&"tea", NarratorConfig.TARGET_SUBJECT_CELL), {"type": &"none"})


func test_the_pruned_ring_does_not_break_the_narrator() -> void:
	var narrator: Narrator = _narrator()
	# The ring dropped the first events: the serials that come now start past 0 and are announced all the same.
	_serial = 500
	_feed(narrator, [_one_of(&"high", 10)], 10)
	assert_eq(narrator.visible().size(), 1)
	assert_eq(narrator.visible()[0]["cause_id"], 500)
