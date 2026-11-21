class_name Narrator
extends RefCounted

# The neutral narrator (issue #73, D-137): no character and no opinion. Every notice is born from an event of the
# cause log (#82), read by serial, and the rules of NarratorConfig decide which ones speak. No random number and no
# frame time: the same log gives the same notices. Times are the events' game seconds.
#
# Anti-saturation (D-146), by kind|cause: a repeat while its notice is up, or within group_window_s of its last one,
# adds to that notice's `merged`; one inside the cooldown of its priority after its notice went goes to the digest.
# At most max_visible are up: the oldest of the lowest priority goes out, and what is critical never does (it waits
# for a slot instead). Notices spend a budget per minute by priority; past it normal and low go to the digest, shown
# every digest_interval_s when it holds anything. Pause (D-145): a rule that says so asks once for a pause.
#
# The first cause of a subject nobody has seen (D-198) waits first_cause_grace_s before it is offered: a change of
# that subject within the grace cancels it, and what survives is offered in serial order after `_expire`, so the
# wait does not eat the lifetime of the notice that just appeared.

const DIGEST_KEY: StringName = Strings.NARRATOR_DIGEST
const DIGEST_KIND: StringName = &"digest"
const SEPARATOR: String = "|"
const SECONDS_PER_MINUTE: int = 60
# What may go to the digest past the budget; high is shown anyway and critical spends nothing.
const DIGESTIBLE: Array[StringName] = [&"normal", &"low"]

var config: NarratorConfig
# The crisis rules pause only while the crisis's events.json switch lets them (D-145, `defeat_pause`).
var crisis_pause_allowed: bool = false
var _next_serial: int = 0
# kind|subject seen at least once: only subjects first seen after start may wait for a first-cause notice.
var _known: Dictionary[String, bool] = {}
var _visible: Array[Dictionary] = []
var _queued: Array[Dictionary] = []
# Each {key, serial, event, rule, arrival} (D-198): a first cause waiting out its grace; `arrival` is the second it
# came, not the one its event carries.
var _pending: Array[Dictionary] = []
# kind|cause -> the second its last notice was shown.
var _last_shown: Dictionary[String, int] = {}
# (second, cost) of what was shown, for the budget of the last minute.
var _spent: Array[Vector2i] = []
# Each {notice, count}, one per kind|cause, in the order they first came.
var _digest: Array[Dictionary] = []
var _digest_started: int = 0
var _pause: bool = false
var _next_id: int = 0


func _init(narrator_config: NarratorConfig) -> void:
	config = narrator_config


# A new game or a load: what the log already holds is not announced again, only what comes after `next_serial`.
# The pendings (D-198) are UI state, not saved state: they do not survive the screen that held them.
func start(entries: Array[Dictionary], next_serial: int, now: int) -> void:
	_known.clear()
	_visible.clear()
	_queued.clear()
	_pending.clear()
	_last_shown.clear()
	_spent.clear()
	_digest.clear()
	_pause = false
	_next_serial = next_serial
	_digest_started = now
	for entry: Dictionary in entries:
		_known[_subject_key(entry["event"])] = true


# Where the next read of the log starts: an intermittent notice up reads its event again to follow its count.
func read_from() -> int:
	var from: int = _next_serial
	for notice: Dictionary in _visible + _queued:
		if notice["cause"] == CauseLog.INTERMITTENT:
			from = mini(from, int(notice["serial"]))
	return from


func feed(entries: Array[Dictionary], now: int) -> void:
	for entry: Dictionary in entries:
		var serial: int = int(entry["serial"])
		var event: Dictionary = entry["event"]
		if serial < _next_serial:
			_update_count(serial, event)
			continue
		_next_serial = serial + 1
		var key: String = _subject_key(event)
		var rule: Dictionary = config.rule_for(StringName(event["kind"]), StringName(event["cause"]))
		if not _known.has(key):
			_known[key] = true
			# D-198: a first cause may be the subject's starting state or a change nobody has seen yet; it waits out
			# its grace instead of being offered at once.
			if not rule.is_empty() and not rule["silent"]:
				_pending.append({"key": key, "serial": serial, "event": event, "rule": rule, "arrival": now})
			continue
		_cancel_pending(key)
		if rule.is_empty() or rule["silent"]:
			continue
		_offer(_notice(serial, event, rule))
	advance(now)


# The digest, once its interval has gone by and only if it holds anything. Before it, the first causes whose grace
# is over (D-198), in serial order and after `_expire`: a notice born here is not born expired.
func advance(now: int) -> void:
	_expire(now)
	_offer_due_pendings(now)
	if now - _digest_started < config.digest_interval_s:
		return
	_digest_started = now
	if _digest.is_empty():
		return
	var notice: Dictionary = _notice(-1, {"kind": DIGEST_KIND, "subject": &"", "cause": &"", "second": now},
		{"priority": NarratorConfig.PRIORITIES[-1], "key": DIGEST_KEY, "pause": false, "crisis": false})
	notice["items"] = _digest
	_digest = []
	_place(notice)


# A notice of any priority but critical goes after its lifetime of game seconds without a repeat; a queued critical
# takes the free slot.
func _expire(now: int) -> void:
	for notice: Dictionary in _visible.duplicate():
		if notice["priority"] != NarratorConfig.CRITICAL \
				and now - int(notice["last_second"]) >= config.toast_lifetime_s[notice["priority"]]:
			_visible.erase(notice)
	while not _queued.is_empty() and _visible.size() < config.max_visible:
		_visible.append(_queued.pop_front())


# D-198: the first causes whose grace is over, offered by serial, the order the log holds them.
func _offer_due_pendings(now: int) -> void:
	for pending: Dictionary in _pending.duplicate():
		if now - int(pending["arrival"]) >= config.first_cause_grace_s:
			_pending.erase(pending)
			_offer(_notice(int(pending["serial"]), pending["event"], pending["rule"]))


# D-198: a later event of a pending subject replaces the state its first cause would announce.
func _cancel_pending(key: String) -> void:
	for pending: Dictionary in _pending.duplicate():
		if pending["key"] == key:
			_pending.erase(pending)


func visible() -> Array[Dictionary]:
	var copies: Array[Dictionary] = []
	for notice: Dictionary in _visible:
		copies.append(notice.duplicate(true))
	return copies


func queued_count() -> int:
	return _queued.size()


# Kinds and causes waiting for the next digest.
func digest_size() -> int:
	return _digest.size()


func dismiss(id: int) -> void:
	for list: Array[Dictionary] in [_visible, _queued]:
		for notice: Dictionary in list:
			if notice["id"] == id:
				list.erase(notice)
				break
	while not _queued.is_empty() and _visible.size() < config.max_visible:
		_visible.append(_queued.pop_front())


# Whether a notice asked for a pause since the last call.
func take_pause() -> bool:
	var asked: bool = _pause
	_pause = false
	return asked


func _offer(notice: Dictionary) -> void:
	var group: String = notice["group"]
	var second: int = notice["second"]
	var cooldown: int = config.cooldown_s[notice["priority"]]
	var cooling: bool = _last_shown.has(group) and second - _last_shown[group] < cooldown
	var existing: Dictionary = _up_in_group(group)
	if not existing.is_empty() and (cooling or second - int(existing["last_second"]) <= config.group_window_s):
		existing["merged"] += 1
		existing["last_second"] = second
		return
	if cooling:
		_to_digest(notice)
		return
	var cost: int = config.attention_cost[notice["priority"]]
	var recent: Array[Vector2i] = []
	var spent: int = 0
	for entry: Vector2i in _spent:
		if second - entry.x < SECONDS_PER_MINUTE:
			recent.append(entry)
			spent += entry.y
	_spent = recent
	if spent + cost > config.attention_budget_per_min and notice["priority"] in DIGESTIBLE:
		_to_digest(notice)
		return
	_spent.append(Vector2i(second, cost))
	_last_shown[group] = second
	if notice["pause"] and config.pause_on_critical and (not notice["crisis"] or crisis_pause_allowed):
		_pause = true
	_place(notice)


# Over the cap, the oldest of the lowest priority goes out, the new one included; what is critical waits instead.
func _place(notice: Dictionary) -> void:
	_visible.append(notice)
	if _visible.size() <= config.max_visible:
		return
	var out: Dictionary = {}
	for candidate: Dictionary in _visible:
		if candidate["priority"] == NarratorConfig.CRITICAL:
			continue
		if out.is_empty() or _rank(candidate) > _rank(out):
			out = candidate
	if out.is_empty():
		_visible.erase(notice)
		_queued.append(notice)
		return
	_visible.erase(out)
	# The new one was never seen: it is not lost, it goes to the digest.
	if out == notice and notice["kind"] != DIGEST_KIND:
		_to_digest(notice)


func _to_digest(notice: Dictionary) -> void:
	for item: Dictionary in _digest:
		if item["notice"]["group"] == notice["group"]:
			item["count"] += notice["merged"]
			return
	_digest.append({"notice": notice, "count": notice["merged"]})


func _up_in_group(group: String) -> Dictionary:
	for notice: Dictionary in _visible + _queued:
		if notice["group"] == group:
			return notice
	return {}


func _update_count(serial: int, event: Dictionary) -> void:
	if not event.has("count"):
		return
	for notice: Dictionary in _visible + _queued:
		if notice["serial"] == serial:
			notice["count"] = int(event["count"])


func _rank(notice: Dictionary) -> int:
	return NarratorConfig.PRIORITIES.find(notice["priority"])


func _notice(serial: int, event: Dictionary, rule: Dictionary) -> Dictionary:
	_next_id += 1
	var subject: StringName = StringName(event["subject"])
	var second: int = int(event["second"])
	return {"id": _next_id, "serial": serial, "cause_id": serial, "kind": StringName(event["kind"]), "subject": subject,
		"cause": StringName(event["cause"]), "second": second, "last_second": second,
		"priority": rule["priority"], "key": rule["key"], "pause": rule["pause"], "crisis": rule["crisis"],
		"group": String(event["kind"]) + SEPARATOR + String(event["cause"]), "merged": 1,
		"count": int(event.get("count", 0)), "items": [],
		"map_target": NarratorText.map_target(subject, rule.get("target_from", NarratorConfig.TARGET_NONE)),
		"graph_link": NarratorText.graph_link(subject, rule.get("series", ""), second),
		"overlay": NarratorText.fill(rule.get("overlay", ""), subject)}


static func _subject_key(event: Dictionary) -> String:
	return String(event["kind"]) + SEPARATOR + String(event["subject"])
