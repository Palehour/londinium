class_name SimTestParams
extends RefCounted


static func isolated_params(catalog: DataCatalog, role: RoleDef = null) -> Params:
	# These fixtures test production/building rules independently of needs and finance.
	var isolated: RoleDef = RoleDef.new()
	if role != null:
		isolated.modifiers.assign(role.modifiers)
	for key: StringName in [&"population.bread_per_person_per_minute",
			&"population.bread_decay_fraction_per_minute", &"population.tax.rate",
			&"population.satisfaction.overcrowding_weight",
			&"population.growth.immigration_per_minute", &"population.growth.emigration_per_minute"]:
		isolated.modifiers.append(Modifier.new(key, &"set", 0))
	for id: StringName in catalog.buildings:
		for suffix: String in ["wage_per_worker_per_minute", "upkeep_per_minute"]:
			isolated.modifiers.append(Modifier.new(StringName("building.%s.%s" % [id, suffix]), &"set", 0))
	return Params.new(catalog, isolated)
