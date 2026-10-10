extends SceneTree

# Per-minute CSV of the scripted 15-minute games in tests/scenarios/, for tuning data/.
# Run with --help for the options. Godot prints its version banner on stdout, so use --out for clean
# files (balance_all.csv and balance_<id>.csv); the same CSV is also printed.

const ALL: String = "all"
const SUMMARY_HEADER: String = "scenario,metric,min,median,mean,max"
const REFUSED_HEADER: String = "scenario,seed,tick,cmd,reason,money_at_start_of_minute"
const LAST_MINUTES_FROM: int = 13
const USAGE: String = """Usage: godot --headless --path . -s tools/balance_report.gd -- [options]
  --scenario <id>|all   scenario to run (default all)
  --out <dir>           also write the CSV files into <dir>
  --seeds <n>           run every scenario with seeds 1..n instead of the seed in its file
                        (needs --summary when n is above 1)
  --summary             one row per scenario and metric (min, median, mean, max over the seeds)
                        instead of the per-minute CSV; with --out it also writes
                        balance_summary.csv, balance_seeds.csv and balance_refused.csv
  --tax <rate>          replace the rate of every set_tax command, 0 to 1. Scenarios whose JSON has
                        "tax_override": false (the defeat_* ones) are left alone: their tax rate is
                        part of how they lose
  --wheat-price <n>     fix the market price of wheat at n
  --help                show this text
A run in which a scripted command is refused (or never runs) is left out of the summary, counted in
runs_refused and listed in balance_refused.csv. Nothing here changes data/ or the scenario files."""


func _init() -> void:
	var options: Dictionary = _parse(OS.get_cmdline_user_args())
	if options.has("error"):
		printerr("balance_report: %s" % options["error"])
		quit(2)
		return
	if options["help"]:
		print(USAGE)
		quit(0)
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
	var refused_rows: Array[String] = [REFUSED_HEADER]
	for scenario: Dictionary in scenarios:
		var id: String = String(scenario["id"])
		var samples: Dictionary[String, Array] = {}
		var used: int = 0
		var refused_seeds: Array[int] = []
		for variant: Dictionary in _variants(scenario, options):
			var result: ScenarioResult = runner.run(variant)
			var rejections: Array[Dictionary] = result.unexpected_rejections()
			# A refused command means this run no longer plays the scripted scenario, so it must
			# not be mixed into the aggregates; it is reported on its own below.
			if not rejections.is_empty():
				refused_seeds.append(int(variant["seed"]))
				refused_rows.append_array(_refused_lines(id, int(variant["seed"]), result, rejections))
				continue
			used += 1
			var metrics: Dictionary = _metrics(runner, result)
			if per_seed.is_empty():
				per_seed.append("scenario,seed,%s" % ",".join(PackedStringArray(metrics.keys())))
			var cells: PackedStringArray = PackedStringArray()
			for metric: String in metrics:
				cells.append("%.2f" % float(metrics[metric]))
			per_seed.append("%s,%d,%s" % [id, int(variant["seed"]), ",".join(cells)])
			for metric: String in metrics:
				if not samples.has(metric):
					samples[metric] = []
				samples[metric].append(float(metrics[metric]))
		lines.append(_summary_line(id, "runs_used", [float(used)]))
		lines.append(_summary_line(id, "runs_refused", [float(refused_seeds.size())]))
		for metric: String in samples:
			lines.append(_summary_line(id, metric, samples[metric]))
		if not refused_seeds.is_empty():
			printerr("balance_report: %s: %d run(s) left out of the summary because a scripted command was refused (seeds %s)"
				% [id, refused_seeds.size(), str(refused_seeds)])
	print("\n".join(lines))
	if refused_rows.size() > 1:
		print("\n# Runs left out of the summary (a scripted command was refused)\n%s" % "\n".join(refused_rows))
	if options["out"] != "" and not _write_summary(options["out"], lines, per_seed, refused_rows):
		quit(1)
		return
	quit(0)


# One row per refused command: the treasury of the minute before shows whether it was a cash problem.
func _refused_lines(scenario_id: String, seed_value: int, result: ScenarioResult,
		rejections: Array[Dictionary]) -> Array[String]:
	var found: Array[String] = []
	for entry: Dictionary in rejections:
		var tick: int = int(entry["executed_tick"]) if int(entry["executed_tick"]) >= 0 else int(entry["tick"])
		var minute: int = mini(tick / ScenarioRunner.TICKS_PER_MINUTE, result.rows.size() - 1)
		found.append("%s,%d,%d,%s,%s,%d" % [scenario_id, seed_value, tick, entry["cmd"],
			entry["reason"], int(result.row(minute)["money"])])
	return found


# One scenario copy per seed; the original file is never modified.
func _variants(scenario: Dictionary, options: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seeds: int = options["seeds"]
	for index: int in range(maxi(seeds, 1)):
		var copy: Dictionary = scenario.duplicate(true)
		if seeds > 0:
			copy["seed"] = index + 1
		if options["tax"] >= 0.0:
			copy = ScenarioRunner.with_tax(copy, options["tax"])
		found.append(copy)
	return found


# Everything the issue's acceptance criteria ask about, for one finished game.
func _metrics(runner: ScenarioRunner, result: ScenarioResult) -> Dictionary:
	var final: Dictionary = result.final_row()
	var balance: float = result.mean("operating_balance_pm", LAST_MINUTES_FROM, result.rows.size() - 1)
	# "Stable" is the simulation's own rule (DefeatSystem.is_city_stable) on the final state.
	var stable: bool = result.survived() and runner.is_stable(result)
	# The financing event is the purchase itself: its real tick, not a per-minute row, because a
	# purchase that waits for its money happens between two rows.
	var purchase_tick: int = result.second_chain_purchase_tick()
	return {
		"survived": 1 if result.survived() else 0,
		"defeat_tick": result.defeat_tick,
		"population": final["population"],
		"money": final["money"],
		"bread_coverage": final["bread_coverage"],
		"satisfaction": final["satisfaction"],
		"operating_balance_last3": balance,
		"stable": 1 if stable else 0,
		"stable_and_losing_money": 1 if stable and balance < 0.0 else 0,
		"rule_commands": result.rule_command_count(),
		"second_chain_tick": purchase_tick,
		"second_chain_minute": float(purchase_tick) / float(ScenarioRunner.TICKS_PER_MINUTE) if purchase_tick >= 0 else -1.0,
	}


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
		"tax": -1.0, "wheat_price": 0, "help": false}
	var index: int = 0
	while index < args.size():
		var flag: String = args[index]
		if flag in ["--summary", "--help"]:
			options[flag.trim_prefix("--")] = true
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


func _write_summary(out: String, lines: Array[String], per_seed: Array[String],
		refused_rows: Array[String]) -> bool:
	var directory: String = _directory(out)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("balance_report: cannot create %s" % directory)
		return false
	var ok: bool = _write(directory.path_join("balance_summary.csv"), lines)
	ok = _write(directory.path_join("balance_seeds.csv"), per_seed) and ok
	return _write(directory.path_join("balance_refused.csv"), refused_rows) and ok


func _directory(out: String) -> String:
	return out if out.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out)


func _write(path: String, lines: Array[String]) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("balance_report: cannot write %s" % path)
		return false
	file.store_string("\n".join(lines) + "\n")
	return true
