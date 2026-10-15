class_name StatsHistory
extends RefCounted

# History of every statistics series for the whole chapter (issue #82, D-066), in three levels: each second for
# the last minutes (never saved), buckets of a few seconds for the last hours, and one bucket per minute since the
# start. It is derived: it reads the state at the end of a tick and never writes to it, so it cannot change the
# simulation, and a game whose history is missing or broken loads with an empty one.

const VERSION: int = 1
const TIER_FINE: StringName = &"fine"
const TIER_MEDIUM: StringName = &"medium"
const TIER_CHAPTER: StringName = &"chapter"
# A closed bucket keeps min, max, mean and a total: the sum of a flow, or the last value of a level (D-066).
const BUCKET_FIELDS: int = 4
# An open bucket also counts its samples, so a bucket cut by a load still averages right.
const OPEN_FIELDS: int = 5
# Cause of a building that was demolished, logged once.
const GONE: StringName = &"gone"
const NO_EMIGRATION: StringName = &"none"


# One downsampled level: closed buckets oldest first, plus the bucket being filled.
class Tier:
	extends RefCounted

	var bucket_seconds: int
	# Closed buckets kept; 0 keeps every one.
	var capacity: int
	var first_bucket: int = 0
	var buckets: Array[PackedFloat32Array] = []
	var open_bucket: int = 0
	var open: PackedFloat64Array = []
	var _last_flags: PackedByteArray = []

	func _init(seconds: int, kept: int, last_flags: PackedByteArray) -> void:
		bucket_seconds = maxi(1, seconds)
		capacity = maxi(0, kept)
		_last_flags = last_flags
		open.resize(last_flags.size() * OPEN_FIELDS)
		_reset_open()

	func add(second: int, values: PackedFloat64Array) -> void:
		@warning_ignore("integer_division")
		var bucket: int = (second - 1) / bucket_seconds
		if bucket != open_bucket:
			# Only a history restored at another time gets here; its partial bucket would mix two periods.
			_reset_open()
			open_bucket = bucket
		for index: int in values.size():
			var base: int = index * OPEN_FIELDS
			var value: float = values[index]
			open[base] += 1.0
			open[base + 1] = minf(open[base + 1], value)
			open[base + 2] = maxf(open[base + 2], value)
			open[base + 3] += value
			open[base + 4] = value
		if second % bucket_seconds == 0:
			_close()

	func _close() -> void:
		var closed: PackedFloat32Array = []
		closed.resize(_last_flags.size() * BUCKET_FIELDS)
		for index: int in _last_flags.size():
			var base: int = index * OPEN_FIELDS
			var out: int = index * BUCKET_FIELDS
			var count: float = open[base]
			if count <= 0.0:
				for field: int in BUCKET_FIELDS:
					closed[out + field] = NAN
				continue
			closed[out] = open[base + 1]
			closed[out + 1] = open[base + 2]
			closed[out + 2] = open[base + 3] / count
			closed[out + 3] = open[base + 4] if _last_flags[index] else open[base + 3]
		if buckets.is_empty():
			first_bucket = open_bucket
		buckets.append(closed)
		if capacity > 0 and buckets.size() > capacity:
			buckets.pop_front()
			first_bucket += 1
		open_bucket += 1
		_reset_open()

	func _reset_open() -> void:
		for index: int in _last_flags.size():
			var base: int = index * OPEN_FIELDS
			open[base] = 0.0
			open[base + 1] = INF
			open[base + 2] = -INF
			open[base + 3] = 0.0
			open[base + 4] = NAN

	# Whether the bucket being filled is the one the given recorded second falls in.
	func matches(recorded_seconds: int) -> bool:
		@warning_ignore("integer_division")
		var current: int = recorded_seconds / bucket_seconds
		return open_bucket == current

	# Bucket fields of one series, oldest first.
	func column(index: int) -> Dictionary:
		var lows: PackedFloat32Array = []
		var highs: PackedFloat32Array = []
		var means: PackedFloat32Array = []
		var totals: PackedFloat32Array = []
		var base: int = index * BUCKET_FIELDS
		for bucket: PackedFloat32Array in buckets:
			lows.append(bucket[base])
			highs.append(bucket[base + 1])
			means.append(bucket[base + 2])
			totals.append(bucket[base + 3])
		return {"bucket_seconds": bucket_seconds, "first_bucket": first_bucket,
			"min": lows, "max": highs, "mean": means, "total": totals}

	# Saved by series id, so a later registry (a new class, a new good) still reads it.
	func to_dict(ids: Array[StringName]) -> Dictionary:
		var columns: Dictionary = {}
		var opens: Dictionary = {}
		for index: int in ids.size():
			var packed: PackedFloat32Array = []
			for bucket: PackedFloat32Array in buckets:
				packed.append_array(bucket.slice(index * BUCKET_FIELDS, (index + 1) * BUCKET_FIELDS))
			columns[String(ids[index])] = packed
			opens[String(ids[index])] = open.slice(index * OPEN_FIELDS, (index + 1) * OPEN_FIELDS)
		return {"bucket_seconds": bucket_seconds, "first_bucket": first_bucket, "count": buckets.size(),
			"open_bucket": open_bucket, "columns": columns, "open": opens}

	# Series the save does not have read as no data (NaN). Returns false, leaving the tier empty, when malformed.
	func restore(saved: Variant, ids: Array[StringName]) -> bool:
		if saved is not Dictionary or not saved.has_all(["bucket_seconds", "first_bucket", "count", "open_bucket",
				"columns", "open"]) or saved["columns"] is not Dictionary or saved["open"] is not Dictionary:
			return false
		var count: int = int(saved["count"])
		if int(saved["bucket_seconds"]) != bucket_seconds or count < 0 or int(saved["first_bucket"]) < 0 				or (count > 0 and int(saved["open_bucket"]) != int(saved["first_bucket"]) + count):
			return false
		var kept: int = mini(count, capacity) if capacity > 0 else count
		var skipped: int = count - kept
		# Saved columns in registry order; null for a series the save does not have.
		var columns: Array[Variant] = []
		var restored_open: PackedFloat64Array = open.duplicate()
		for index: int in ids.size():
			var packed: Variant = saved["columns"].get(String(ids[index]))
			var pending: Variant = saved["open"].get(String(ids[index]))
			if packed != null and (packed is not PackedFloat32Array or packed.size() != count * BUCKET_FIELDS
					or pending is not PackedFloat64Array or pending.size() != OPEN_FIELDS):
				return false
			columns.append(packed)
			if packed != null:
				for field: int in OPEN_FIELDS:
					restored_open[index * OPEN_FIELDS + field] = pending[field]
		var restored: Array[PackedFloat32Array] = []
		for bucket: int in kept:
			var closed: PackedFloat32Array = []
			closed.resize(ids.size() * BUCKET_FIELDS)
			closed.fill(NAN)
			for index: int in ids.size():
				if columns[index] == null:
					continue
				var packed: PackedFloat32Array = columns[index]
				for field: int in BUCKET_FIELDS:
					closed[index * BUCKET_FIELDS + field] = packed[(skipped + bucket) * BUCKET_FIELDS + field]
			restored.append(closed)
		buckets = restored
		first_bucket = int(saved["first_bucket"]) + skipped
		open_bucket = int(saved["open_bucket"])
		open = restored_open
		return true


var _defs: Array[SeriesDef] = []
var _ids: Array[StringName] = []
var _params: Params
var _context: EconomyContext
# Game seconds recorded so far: the history's own clock, saved with it, so buckets line up after a load.
var _seconds: int = 0
var _fine: Array[PackedFloat64Array] = []
var _fine_span: int
var _medium: Tier
var _chapter: Tier
var _causes: CauseLog


func _init(defs: Array[SeriesDef], params: Params, context: EconomyContext) -> void:
	_defs = defs
	_params = params
	_context = context
	var last_flags: PackedByteArray = []
	for def: SeriesDef in defs:
		_ids.append(def.id)
		last_flags.append(1 if def.aggregation == SeriesDef.AGGREGATION_LAST else 0)
	_fine_span = maxi(1, int(params.get_value(&"stats.fine.span_seconds")))
	var medium_seconds: int = maxi(1, int(params.get_value(&"stats.medium.bucket_seconds")))
	@warning_ignore("integer_division")
	var medium_buckets: int = int(params.get_value(&"stats.medium.span_seconds")) / medium_seconds
	_medium = Tier.new(medium_seconds, maxi(1, medium_buckets), last_flags)
	_chapter = Tier.new(int(params.get_value(&"stats.chapter.bucket_seconds")), 0, last_flags)
	_causes = CauseLog.new(int(params.get_value(&"stats.causes.max_events")))


# Step 11 of the tick: one sample of every series and the causes that changed.
func record(state: EconomyState) -> void:
	_seconds += 1
	var values: PackedFloat64Array = []
	values.resize(_defs.size())
	for index: int in _defs.size():
		values[index] = float(_defs[index].sampler.call(state))
	_fine.append(values)
	if _fine.size() > _fine_span:
		_fine.pop_front()
	_medium.add(_seconds, values)
	_chapter.add(_seconds, values)
	_note_causes(state)


# Step 1 of the tick: every command's outcome, on the second the tick is about to record.
func note_command(command: SimulationCommand) -> void:
	var cause: StringName = &"accepted" if command.accepted else command.reason
	_causes.note(_seconds + 1, &"command", command.get_script().get_global_name(), cause)


func _note_causes(state: EconomyState) -> void:
	var present: Array[StringName] = []
	for building: Dictionary in state.buildings:
		var id: StringName = StringName(building["definition_id"])
		if WorkersSystem.job_capacity(_params, id) <= 0:
			continue
		var subject: StringName = StringName("%s@%d,%d" % [id, int(building["cell"][0]), int(building["cell"][1])])
		present.append(subject)
		_causes.note(_seconds, &"building", subject, BreadDiagnostics.building_reason(state, _context, building, _params))
	_causes.forget_missing(_seconds, &"building", present, GONE)
	_causes.note(_seconds, &"import", &"tea", ImportSystem.tea_reason(state, _params))
	_causes.note(_seconds, &"import", &"flour", ImportSystem.flour_reason(state, _params))
	for def: ClassDef in ClassStates.defs(_context):
		_causes.note(_seconds, &"emigration", SeriesRegistry.member_of(def), _emigration_cause(state, def))
	_causes.note(_seconds, &"policy", &"tax_rate", StringName(str(state.tax_rate)))
	_causes.note(_seconds, &"policy", &"wheat_purchases", StringName(str(state.wheat_purchases_enabled)))
	_causes.note(_seconds, &"policy", &"wheat_policy", StringName("%d/%d/%d/%d" % [state.wheat_accumulate_price,
		state.wheat_max_price, state.wheat_target_stock, state.wheat_reserve_minutes]))
	_causes.note(_seconds, &"policy", &"unloading_barley_percent", StringName(str(state.unloading_barley_percent)))
	_causes.note(_seconds, &"policy", &"tea_imports", StringName(str(state.tea_imports_enabled)))
	_causes.note(_seconds, &"policy", &"flour_imports", StringName(str(state.flour_imports_enabled)))
	for condition: StringName in SeriesRegistry.DEFEAT_CONDITIONS:
		_causes.note(_seconds, &"defeat", condition, SeriesRegistry.defeat_state(state, condition).status)
	for stage: StringName in state.victory.stages:
		var done: bool = int(state.victory.stages[stage]["completed_tick"]) >= 0
		_causes.note(_seconds, &"victory", stage, &"completed" if done else &"pending")


# Only the two reasons people leave: hunger or low satisfaction (GrowthSystem).
func _emigration_cause(state: EconomyState, def: ClassDef) -> StringName:
	var entry: ClassState = ClassStates.checkout(state, def) if def.base else state.class_states.get(def.id)
	if entry == null:
		return NO_EMIGRATION
	var reason: StringName = GrowthSystem.reason(state, _params, def, entry)
	return reason if reason in [GrowthSystem.REASON_HUNGRY, GrowthSystem.REASON_UNHAPPY] else NO_EMIGRATION


func defs() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for def: SeriesDef in _defs:
		found.append(def.describe())
	return found


# A copy of one series in one level; empty for an unknown series or level. The fine level has one value a second.
func series(id: StringName, tier: StringName) -> Dictionary:
	var index: int = _ids.find(id)
	if index < 0:
		return {}
	match tier:
		TIER_FINE:
			var values: PackedFloat32Array = []
			for sample: PackedFloat64Array in _fine:
				values.append(sample[index])
			return {"bucket_seconds": 1, "first_second": _seconds - _fine.size() + 1, "values": values}
		TIER_MEDIUM:
			return _medium.column(index)
		TIER_CHAPTER:
			return _chapter.column(index)
	return {}


func events(from_second: int = 0) -> Array[Dictionary]:
	return _causes.events(from_second)


func seconds() -> int:
	return _seconds


# What a save keeps: the medium and chapter levels and the cause log; the fine level is rebuilt by playing.
func to_dict() -> Dictionary:
	return {"version": VERSION, "seconds": _seconds, "medium": _medium.to_dict(_ids),
		"chapter": _chapter.to_dict(_ids), "causes": _causes.to_dict()}


# Size of a saved history once compressed, the way the size criterion of D-066 measures it.
static func compressed_size(saved: Dictionary) -> int:
	return var_to_bytes(saved).compress(FileAccess.COMPRESSION_ZSTD).size()


# A missing history starts empty without a word; a malformed one starts empty with a warning. Either way the game
# loads: statistics are never needed to simulate.
func restore(saved: Dictionary) -> void:
	if saved.is_empty():
		return
	var fresh: StatsHistory = StatsHistory.new(_defs, _params, _context)
	if int(saved.get("version", -1)) != VERSION or typeof(saved.get("seconds")) != TYPE_INT \
			or int(saved["seconds"]) < 0 or saved.get("causes") is not Dictionary \
			or not fresh._medium.restore(saved.get("medium"), _ids) \
			or not fresh._chapter.restore(saved.get("chapter"), _ids) \
			or not fresh._causes.restore(saved["causes"]) 			or not fresh._medium.matches(int(saved["seconds"])) or not fresh._chapter.matches(int(saved["seconds"])):
		push_warning("StatsHistory: malformed saved history; starting an empty one")
		return
	_seconds = int(saved["seconds"])
	_medium = fresh._medium
	_chapter = fresh._chapter
	_causes = fresh._causes
