class_name DefeatSystem
extends RefCounted


func initialize(state: EconomyState, params: Params) -> void:
	if state.defeat_initialized:
		return
	state.defeat_initialized = true
	state.hunger_smoothed_coverage = state.bread_coverage
	_update_population_history(state, params)
	# Empty cities expose diagnostics immediately only when grace has already ended.
	if params.get_value(&"defeat.enabled") and state.population == 0 and (float(params.get_value(&"defeat.grace_seconds")) == 0.0 \
			or state.defeat_elapsed_seconds > float(params.get_value(&"defeat.grace_seconds"))):
		_update(state.depopulation, &"depopulation", true, true, false,
			float(params.get_value(&"defeat.depopulation.duration_seconds")))


func update_hunger_coverage(state: EconomyState, params: Params) -> void:
	initialize(state, params)
	state.hunger_smoothed_coverage += (state.bread_coverage - state.hunger_smoothed_coverage) \
		* float(params.get_value(&"defeat.hunger.smoothing"))
	var epsilon: float = float(params.get_value(&"population.hunger_coverage_snap_epsilon"))
	if absf(state.bread_coverage - state.hunger_smoothed_coverage) < epsilon:
		state.hunger_smoothed_coverage = state.bread_coverage


# `depopulation_paused` (a mission's defeat_pause, issue #63, D-090) freezes the depopulation timer, not resets it.
func tick(state: EconomyState, params: Params, update_coverage: bool = true, depopulation_paused: bool = false,
		context: EconomyContext = null) -> void:
	if not state.defeat_causes.is_empty():
		return
	initialize(state, params)
	state.defeat_elapsed_seconds += 1
	if update_coverage:
		update_hunger_coverage(state, params)
	_update_population_history(state, params)
	var stable: bool = is_city_stable(state, params)
	if stable:
		_decay_population_peak(state, params)
	# Defeats off (D-065): coverage and the peak above keep running for growth and stability, but no timer moves.
	if not params.get_value(&"defeat.enabled"):
		return
	var counting: bool = state.defeat_elapsed_seconds > float(params.get_value(&"defeat.grace_seconds"))
	# With a loan unpaid its only way to bankruptcy is the receiver (D-128, D-013, D-131), in arrears or not.
	var bankrupt: bool = state.money < bankruptcy_threshold(state, params, context) and state.loan == null
	_update(state.bankruptcy, &"bankruptcy", bankrupt, bankrupt, counting,
		float(params.get_value(&"defeat.bankruptcy.duration_seconds")))
	var hungry: bool = state.population > 0 and state.hunger_coverage() \
		< float(params.get_value(&"defeat.hunger.threshold"))
	_update(state.hunger, &"hunger", hungry, hungry, counting,
		float(params.get_value(&"defeat.hunger.duration_seconds")))
	var below_minimum: bool = not stable and state.population \
		< int(params.get_value(&"defeat.depopulation.minimum_population"))
	var empty: bool = state.population == 0
	var warning: bool = empty or (state.depopulation_active and (below_minimum or state.population \
		< state.population_peak * float(params.get_value(&"defeat.depopulation.warning_fraction"))))
	var critical: bool = empty or (state.depopulation_active and (below_minimum or state.population \
		< state.population_peak * float(params.get_value(&"defeat.depopulation.defeat_fraction"))))
	if not counting:
		warning = false
	if not depopulation_paused:
		_update(state.depopulation, &"depopulation", warning, critical, counting,
			float(params.get_value(&"defeat.depopulation.duration_seconds")))
	for condition: DefeatState in [state.bankruptcy, state.hunger, state.depopulation]:
		if condition.status == &"defeat":
			state.defeat_causes.append(condition.cause)


# The treasury below which the bankruptcy window opens (D-131, D-133): a multiple of R, the head tax per minute at
# today's rate, in whole pence rounded to the nearest (the multiple of a hard or easy preset is not exact).
static func bankruptcy_threshold(state: EconomyState, params: Params, context: EconomyContext) -> int:
	var multiple: float = float(params.get_value(&"defeat.bankruptcy.threshold_tax_minutes"))
	return roundi(multiple * MoneySystem.tax_per_minute(state, params, context))


# The window of D-133 is running: the treasury is under the threshold, no loan is open and the grace is over, so the
# timer counts. Building is blocked meanwhile. Warning during the grace does not count: nothing is ticking.
static func bankruptcy_window_running(state: EconomyState) -> bool:
	return state.bankruptcy.status == &"warning" and state.bankruptcy.elapsed_seconds > 0


func _update_population_history(state: EconomyState, params: Params) -> void:
	state.population_peak = maxf(state.population_peak, float(state.population))
	if state.population_peak >= int(params.get_value(&"defeat.depopulation.minimum_population")):
		state.depopulation_active = true


# Nobody is leaving: no hunger emigration, smoothed coverage at or above the emigration threshold
# and nobody left for low satisfaction within the stability window (measured on actual departures,
# so a city sitting on the satisfaction edge does not flicker). Every class counts (issue #52): a city
# where artisans are leaving is not stable. Public so balance probes use the same rule as the game.
func is_city_stable(state: EconomyState, params: Params) -> bool:
	var window: int = int(params.get_value(&"defeat.depopulation.stability_window_seconds"))
	var ages: Array[int] = [state.satisfaction_departure_age_seconds]
	var hunger_active: bool = state.hunger_emigration_active
	for entry: ClassState in state.class_states.values():
		ages.append(entry.satisfaction_departure_age_seconds)
		# A class with nobody in it cannot be leaving, whatever its hunger flag says.
		hunger_active = hunger_active or (entry.hunger_emigration_active and entry.population > 0)
	return not hunger_active and state.hunger_coverage() 		>= float(params.get_value(&"population.growth.hunger_emigration_threshold")) 		and ages.all(func(age: int) -> bool: return age < 0 or age >= window)


func _decay_population_peak(state: EconomyState, params: Params) -> void:
	var rate: float = float(params.get_value(&"defeat.depopulation.peak_decay_per_minute"))
	# A tick is one game second; compounding preserves the configured reduction over 60 ticks.
	state.population_peak = maxf(float(state.population), state.population_peak * pow(1.0 - rate, 1.0 / 60.0))


func _update(condition: DefeatState, cause: StringName, warning: bool,
		critical: bool, counting: bool, duration: float) -> void:
	condition.elapsed_seconds = condition.elapsed_seconds + 1 if counting and critical else 0
	condition.status = &"warning" if warning else &"ok"
	condition.cause = cause if warning else &""
	if counting and critical and condition.elapsed_seconds >= duration:
		condition.status = &"defeat"
		condition.cause = cause


const CRITICAL_KEYS: Array[StringName] = [&"bankruptcy", &"hunger", &"depopulation"]

# For #350: readonly derived. base from status (warning/defeat->warning, ok->normal).
# depop warning sin timer: warning but no critical.
# grace blocks only critical (not warning); disabled all normal.
# crit: enabled and not grace and crit num valid and (elapsed>0 or receiver) and seconds_left <= crit.
# float duration, ceil max( ,0). No has_value fallbacks for econ keys (fixtures provide).
static func defeat_state_for_snapshot(state: EconomyState, params: Params, context: EconomyContext = null) -> Dictionary:
	var result: Dictionary = {}
	var enabled: bool = bool(params.get_value(&"defeat.enabled"))
	var grace: float = float(params.get_value(&"defeat.grace_seconds"))
	var in_grace: bool = state.defeat_elapsed_seconds <= grace
	for cond: StringName in CRITICAL_KEYS:
		var level: StringName = &"normal"
		var status: StringName = &"ok"
		if cond == &"bankruptcy":
			status = state.bankruptcy.status
		elif cond == &"hunger":
			status = state.hunger.status
		else:
			status = state.depopulation.status
		var is_receiver_bank: bool = (cond == &"bankruptcy" and state.loan != null and state.loan.receiver)
		if status == &"warning" or status == &"defeat" or is_receiver_bank:
			level = &"warning"
		var seconds_left: int = 0
		var duration: float = 0.0
		var elapsed: float = 0.0
		var timer_active: bool = false
		if cond == &"bankruptcy":
			if is_receiver_bank:
				duration = float(params.get_value(&"loan.receiver_window_s"))
				elapsed = float(state.loan.receiver_seconds)
				timer_active = true
			else:
				duration = float(params.get_value(&"defeat.bankruptcy.duration_seconds"))
				elapsed = float(state.bankruptcy.elapsed_seconds)
				timer_active = elapsed > 0.0
		elif cond == &"hunger":
			duration = float(params.get_value(&"defeat.hunger.duration_seconds"))
			elapsed = float(state.hunger.elapsed_seconds)
			timer_active = elapsed > 0.0
		else:
			duration = float(params.get_value(&"defeat.depopulation.duration_seconds"))
			elapsed = float(state.depopulation.elapsed_seconds)
			timer_active = elapsed > 0.0
		var remaining: float = maxf(0.0, duration - elapsed)
		seconds_left = int(ceil(remaining))
		var crit_key: StringName = StringName("ui.defeat.critical_seconds." + String(cond))
		var crit_num: float = -1.0
		var crit_defined: bool = false
		if params.has_value(crit_key):
			var v: Variant = params.get_value(crit_key)
			if v != null and not (v is String and v == "sin dato"):
				crit_num = float(v)
				crit_defined = true
		var is_crit: bool = enabled and not in_grace and crit_defined and crit_num >= 0 and timer_active and seconds_left <= crit_num
		if is_crit:
			level = &"critical"
		elif not enabled:
			level = &"normal"
		# during grace: keep base level (warning from status/receiver or normal); only criticals blocked (by not in_grace in is_crit)
		# depop warning sin timer: warning pero no critical (ya seteado via base)
		var c: StringName = cond
		if cond == &"bankruptcy":
			if is_receiver_bank:
				c = &"loan_bankruptcy"
			else:
				c = &"bankruptcy"
		result[cond] = {"level": level, "seconds_left": seconds_left, "cause": c}
	return result

static func critical_config_errors(params: Params) -> Array[String]:
	var errs: Array[String] = []
	for cond: StringName in CRITICAL_KEYS:
		var ukey: StringName = StringName("ui.defeat.critical_seconds." + String(cond))
		if not params.has_value(ukey):
			errs.append("ui.defeat.critical_seconds.%s: missing (incomplete)" % cond)
			continue
		var v: Variant = params.get_value(ukey)
		if v == null or (v is String and v == "sin dato"):
			errs.append("ui.defeat.critical_seconds.%s: sin dato or missing (incomplete)" % cond)
	var skey: StringName = &"ui.defeat.critical_sound"
	if not params.has_value(skey):
		errs.append("ui.defeat.critical_sound: missing")
	else:
		var sv: Variant = params.get_value(skey)
		if sv == null or (sv is String and sv == "sin dato"):
			errs.append("ui.defeat.critical_sound: sin dato or missing")
	return errs
