extends SceneTree

# Per-minute CSV of the scripted 15-minute games in tests/scenarios/, for tuning data/.
# Usage: godot --headless --path . -s tools/balance_report.gd -- [--scenario <id>|all] [--out <dir>]
#        [--seeds <n>] [--summary] [--tax <rate>] [--wheat-price <whole>]
# Godot prints its version banner on stdout, so use --out for clean files (balance_all.csv and
# balance_<id>.csv); the same CSV is also printed.
#
# Probe mode: --seeds n runs each scenario with seeds 1..n instead of the seed in its file, and
# --summary prints one row per scenario and metric (min, median, mean, max over the seeds) instead
# of the per-minute CSV; with --out it is also written to balance_summary.csv, next to
# balance_seeds.csv (one row per scenario and seed). --tax replaces the
# rate of every set_tax command and --wheat-price fixes the market price; both only change the
# probe, never data/ or the scenario files.

const ALL: String = "all"
const SUMMARY_HEADER: String = "scenario,metric,min,median,mean,max"
const LAST_MINUTES_FROM: int = 13
const CHAIN_BUILDINGS: Array[String] = ["wharf", "mill", "bakery"]
# Same threshold the hunger-emigration rule uses (population.growth.hunger_emigration_threshold).
const STABLE_COVERAGE_KEY: StringName = &"population.growth.hunger_emigration_threshold"


func _init() -> void:
	var options: Dictionary = _parse(OS.get_cmdline_user_args())
	if options.has("error"):
		printerr("balance_report: %s" % options["error"])
		quit(2)
		return
	if options["seeds"] > 1 and not options["summary"]:
		printerr("balance_report: --seeds above 1 needs --summary (the per-minute CSV is for one run)")
		quit(2)
		return
	var runner: ScenarioRunner = ScenarioRunner.create()
	if runner == null:
		quit(1)
		return
	if options["wheat_price"] > 0:
		runner.pin_wheat_price(options["wheat_price"])
	var wanted: String = options["scenario"]
	var scenarios: Array[Dictionary] = []
	for path: String in ScenarioRunner.scenario_paths():
		var scenario: Dictionary = ScenarioRunner.load_file(path)
		var errors: Array[String] = runner.validate(scenario)
		if not errors.is_empty():
			printerr("balance_report: %s is invalid: %s" % [path, str(errors)])
			quit(1)
			return
		if wanted == ALL or wanted == scenario["id"]:
			scenarios.append(scenario)
	if scenarios.is_empty():
		printerr("balance_report: no scenario named '%s'" % wanted)
		quit(2)
		return
	if options["summary"]:
		_run_summary(runner, scenarios, options)
		return
	_run_csv(runner, scenarios, options)


func _run_csv(runner: ScenarioRunner, scenarios: Array[Dictionary], options: Dictionary) -> void:
	var results: Array[ScenarioResult] = []
	for scenario: Dictionary in scenarios:
		var variants: Array[Dictionary] = _variants(scenario, options)
		for variant: Dictionary in variants:
			results.append(runner.run(variant))
	var combined: Array[String] = [ScenarioResult.csv_header()]
	for result: ScenarioResult in results:
		combined.append_array(result.csv_lines())
		if not result.unexpected_rejections().is_empty():
			printerr("balance_report: %s: a scripted command was refused (script out of date?)" % result.id)
	print("\n".join(combined))
	if options["out"] != "" and not _write_files(options["out"], results, combined):
		quit(1)
		return
	quit(0)


func _run_summary(runner: ScenarioRunner, scenarios: Array[Dictionary], options: Dictionary) -> void:
	var lines: Array[String] = [SUMMARY_HEADER]
	var per_seed: Array[String] = []
	var refused: bool = false
	for scenario: Dictionary in scenarios:
		var samples: Dictionary[String, Array] = {}
		for variant: Dictionary in _variants(scenario, options):
			var result: ScenarioResult = runner.run(variant)
			refused = refused or not result.unexpected_rejections().is_empty()
			var metrics: Dictionary = _metrics(runner, result)
			if per_seed.is_empty():
				per_seed.append("scenario,seed,%s" % ",".join(PackedStringArray(metrics.keys())))
			var cells: PackedStringArray = PackedStringArray()
			for metric: String in metrics:
				cells.append("%.2f" % float(metrics[metric]))
			per_seed.append("%s,%d,%s" % [scenario["id"], int(variant["seed"]), ",".join(cells)])
			for metric: String in metrics:
				if not samples.has(metric):
					samples[metric] = []
				samples[metric].append(float(metrics[metric]))
		for metric: String in samples:
			lines.append(_summary_line(String(scenario["id"]), metric, samples[metric]))
	if refused:
		printerr("balance_report: a scripted command was refused in some run (script out of date?)")
	print("\n".join(lines))
	if options["out"] != "" and not _write_summary(options["out"], lines, per_seed):
		quit(1)
		return
	quit(0)


# One scenario copy per seed; the original file is never modified.
func _variants(scenario: Dictionary, options: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seeds: int = options["seeds"]
	for index: int in range(maxi(seeds, 1)):
		var copy: Dictionary = scenario.duplicate(true)
		if seeds > 0:
			copy["seed"] = index + 1
		if options["tax"] >= 0.0:
			for command: Dictionary in copy["commands"]:
				if command["cmd"] == "set_tax":
					command["rate"] = options["tax"]
		found.append(copy)
	return found


# Everything the issue's acceptance criteria ask about, for one finished game.
func _metrics(runner: ScenarioRunner, result: ScenarioResult) -> Dictionary:
	var final: Dictionary = result.final_row()
	var chain_cost: int = 0
	for building: String in CHAIN_BUILDINGS:
		chain_cost += int(runner.param(StringName("building.%s.cost" % building)))
	var balance: float = result.mean("operating_balance_pm", LAST_MINUTES_FROM, result.rows.size() - 1)
	var coverage: float = float(final["bread_coverage"])
	var shrinking: bool = int(final["population"]) < int(result.row(LAST_MINUTES_FROM - 1)["population"])
	var funded_minute: int = _first_minute_with_money(result, chain_cost)
	var housing_cost: int = int(runner.param(&"building.housing.cost"))
	var stage_minute: int = _first_minute_with_money(result, chain_cost + housing_cost)
	var stable: bool = result.survived() and not shrinking \
		and coverage >= float(runner.param(STABLE_COVERAGE_KEY))
	return {
		"survived": 1 if result.survived() else 0,
		"defeat_tick": result.defeat_tick,
		"population": final["population"],
		"money": final["money"],
		"bread_coverage": coverage,
		"satisfaction": final["satisfaction"],
		"operating_balance_last3": balance,
		"stable": 1 if stable else 0,
		"stable_and_losing_money": 1 if stable and balance < 0.0 else 0,
		"commands_refused": result.unexpected_rejections().size(),
		"chain_cost": chain_cost,
		"chain_funded": 1 if funded_minute > 0 else 0,
		"chain_funded_minute": funded_minute,
		# Second chain plus the second housing block, bought together (big_tight_r06).
		"chain_housing_funded": 1 if stage_minute > 0 else 0,
		"chain_housing_funded_minute": stage_minute,
	}


# First minute, counted from the first complete chain (wharf, mill and bakery all standing), with
# a treasury that pays for one more chain; -1 if there is no first chain or it never gets there.
func _first_minute_with_money(result: ScenarioResult, cost: int) -> int:
	var built_from: int = -1
	for minute: int in range(1, result.rows.size()):
		var row: Dictionary = result.row(minute)
		if built_from < 0 and row["n_wharf"] > 0 and row["n_mill"] > 0 and row["n_bakery"] > 0:
			built_from = minute
		if built_from >= 0 and int(row["money"]) >= cost:
			return minute
	return -1


func _summary_line(scenario_id: String, metric: String, values: Array) -> String:
	var sorted: Array = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in sorted:
		total += value
	var middle: int = sorted.size() / 2
	var median: float = sorted[middle] if sorted.size() % 2 == 1 else (sorted[middle - 1] + sorted[middle]) / 2.0
	return "%s,%s,%.2f,%.2f,%.2f,%.2f" % [scenario_id, metric, sorted[0], median,
		total / float(sorted.size()), sorted[sorted.size() - 1]]


func _parse(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"scenario": ALL, "out": "", "seeds": 0, "summary": false,
		"tax": -1.0, "wheat_price": 0}
	var index: int = 0
	while index < args.size():
		var flag: String = args[index]
		if flag == "--summary":
			options["summary"] = true
			index += 1
			continue
		if flag not in ["--scenario", "--out", "--seeds", "--tax", "--wheat-price"] or index + 1 >= args.size():
			return {"error": "unknown or incomplete option '%s'" % flag}
		var value: String = args[index + 1]
		match flag:
			"--seeds":
				if not value.is_valid_int() or int(value) < 1:
					return {"error": "--seeds needs a whole number >= 1"}
				options["seeds"] = int(value)
			"--tax":
				if not value.is_valid_float() or float(value) < 0.0 or float(value) > 1.0:
					return {"error": "--tax needs a rate between 0 and 1"}
				options["tax"] = float(value)
			"--wheat-price":
				if not value.is_valid_int() or int(value) < 1:
					return {"error": "--wheat-price needs a whole number >= 1"}
				options["wheat_price"] = int(value)
			_:
				options[flag.trim_prefix("--")] = value
		index += 2
	return options


func _write_files(out: String, results: Array[ScenarioResult], combined: Array[String]) -> bool:
	var directory: String = _directory(out)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("balance_report: cannot create %s" % directory)
		return false
	var ok: bool = _write(directory.path_join("balance_all.csv"), combined)
	for result: ScenarioResult in results:
		var lines: Array[String] = [ScenarioResult.csv_header()]
		lines.append_array(result.csv_lines())
		ok = _write(directory.path_join("balance_%s.csv" % result.id), lines) and ok
	return ok


func _write_summary(out: String, lines: Array[String], per_seed: Array[String]) -> bool:
	var directory: String = _directory(out)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("balance_report: cannot create %s" % directory)
		return false
	var ok: bool = _write(directory.path_join("balance_summary.csv"), lines)
	return _write(directory.path_join("balance_seeds.csv"), per_seed) and ok


func _directory(out: String) -> String:
	return out if out.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out)


func _write(path: String, lines: Array[String]) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("balance_report: cannot write %s" % path)
		return false
	file.store_string("\n".join(lines) + "\n")
	return true
