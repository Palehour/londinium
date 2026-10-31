class_name TaxBase
extends RefCounted

# D-134 refuses a building with upkeep when the city's delta per minute would stay below 0. Tests that build services
# (they open no jobs) start from a city that already collects tax: a rate and some staffed wheat fields far from the
# map the test uses (a field is no link of the chains, so it takes no worker from them once the sim ticks).
const FIELD: StringName = &"wheat_field"
const FIELDS: int = 6
const ARTISAN: StringName = &"artisan"
const ARTISANS: int = 6


static func fund(state: EconomyState, params: Params) -> void:
	state.tax_rate = float(params.get_value(&"population.tax.rate"))
	var workers: int = WorkersSystem.job_capacity(params, FIELD)
	for index: int in range(FIELDS):
		state.buildings.append({"definition_id": FIELD, "cell": [-50 - index, -50], "workers": workers})


# The same for a test that ticks between its builds: staffed wheat fields lose their workers without a street, so the tax
# comes from artisans, who pay on residents (D-134 looks at the head tax of the class definitions).
static func fund_with_artisans(state: EconomyState, params: Params, context: EconomyContext) -> void:
	state.tax_rate = float(params.get_value(&"population.tax.rate"))
	ClassStates.ensure(state, context)
	state.class_states[ARTISAN].population += ARTISANS
	state.population += ARTISANS


# The same for a running game (a GameSession), with no building added: its simulation is rebuilt from its own save
# with the artisans in it.
static func fund_session(session: GameSession) -> void:
	var params: Params = session.get("_params") as Params
	var saved: Dictionary = session.simulation.to_save()
	var state: EconomyState = EconomyState.from_dict(saved["economy"])
	fund_with_artisans(state, params, session.context)
	saved["economy"] = state.to_dict()
	var stages: Array[Dictionary] = []
	stages.assign(session.get("_victory_stages"))
	session.simulation = Simulation.from_save(params, session.context, stages, saved)
