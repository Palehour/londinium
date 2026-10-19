class_name ClassStates
extends RefCounted

# Access to the state of every class through one door (issue #52). The base class (ClassDef.base) keeps its
# values in the flat fields of EconomyState; the other classes keep them in EconomyState.class_states.
# state.population is always the total of every class.


# The classes the systems loop over, in declaration order. A context without classes (a bare test fixture)
# behaves as one legacy class, so the engine has a single path.
static func defs(context: EconomyContext) -> Array[ClassDef]:
	var found: Array[ClassDef] = []
	if context != null:
		found.assign(context.classes.values())
	if found.is_empty():
		found.append(ClassDef.legacy())
	return found


static func is_base(def: ClassDef) -> bool:
	return def.base


# Residents of the classes that are not the base one.
static func others_total(state: EconomyState) -> int:
	var total: int = 0
	for entry: ClassState in state.class_states.values():
		total += entry.population
	return total


# Capacity of the housing of the classes that are not the base one.
static func others_capacity(state: EconomyState) -> int:
	var total: int = 0
	for entry: ClassState in state.class_states.values():
		total += entry.housing_capacity
	return total


static func population_of(state: EconomyState, def: ClassDef) -> int:
	if def.base:
		return state.population - others_total(state)
	return state.class_states[def.id].population if state.class_states.has(def.id) else 0


# People who look for a job: every resident except those of classes that do not take jobs (D-021).
static func job_seekers(state: EconomyState) -> int:
	var seekers: int = state.population
	for entry: ClassState in state.class_states.values():
		if not entry.takes_jobs:
			seekers -= entry.population
	return seekers


# Makes sure every non-base class of the context has its state (a state saved before the class existed).
# Returns the classes it had to create.
static func ensure(state: EconomyState, context: EconomyContext) -> Array[ClassDef]:
	var created: Array[ClassDef] = []
	for def: ClassDef in defs(context):
		if not def.base and not state.class_states.has(def.id):
			var entry: ClassState = ClassState.new()
			entry.takes_jobs = def.takes_jobs
			state.class_states[def.id] = entry
			created.append(def)
	return created


# The state of a class to work on. For the base class it is a copy of the flat fields: write it back with commit().
static func checkout(state: EconomyState, def: ClassDef) -> ClassState:
	if not def.base:
		if not state.class_states.has(def.id):
			var created: ClassState = ClassState.new()
			created.takes_jobs = def.takes_jobs
			state.class_states[def.id] = created
		return state.class_states[def.id]
	var entry: ClassState = ClassState.new()
	entry.population = state.population - others_total(state)
	entry.satisfaction = state.satisfaction
	entry.satisfaction_target = state.satisfaction_target
	entry.satisfaction_breakdown.assign(state.satisfaction_breakdown)
	# state.housing_capacity is the total of every class, so the base class has what the others leave.
	entry.housing_capacity = state.housing_capacity - others_capacity(state)
	entry.overcrowding = state.overcrowding
	entry.immigration_fraction = state.immigration_fraction
	entry.emigration_fraction = state.emigration_fraction
	entry.hunger_emigration_active = state.hunger_emigration_active
	entry.satisfaction_departure_age_seconds = state.satisfaction_departure_age_seconds
	return entry


# Writes a checked-out base class back. The population and the capacity are not written: they change the
# totals through grow() and SatisfactionSystem.
static func commit(state: EconomyState, def: ClassDef, entry: ClassState) -> void:
	if not def.base:
		return
	state.satisfaction = entry.satisfaction
	state.satisfaction_target = entry.satisfaction_target
	state.satisfaction_breakdown.assign(entry.satisfaction_breakdown)
	state.overcrowding = entry.overcrowding
	state.immigration_fraction = entry.immigration_fraction
	state.emigration_fraction = entry.emigration_fraction
	state.hunger_emigration_active = entry.hunger_emigration_active
	state.satisfaction_departure_age_seconds = entry.satisfaction_departure_age_seconds


# Moves residents in (positive) or out (negative) of the class and of the total.
static func grow(state: EconomyState, def: ClassDef, entry: ClassState, change: int) -> void:
	state.population += change
	entry.population += change
