extends SceneTree

# Per-minute CSV of the scripted 15-minute games in tests/scenarios/, for tuning data/.
# Usage: godot --headless --path . -s tools/balance_report.gd -- [--scenario <id>|all] [--out <dir>]
# Godot prints its version banner on stdout, so use --out for clean files (balance_all.csv and
# balance_<id>.csv); the same CSV is also printed.

const ALL: String = "all"


func _init() -> void:
	var options: Dictionary = _parse(OS.get_cmdline_user_args())
	if options.has("error"):
		printerr("balance_report: %s" % options["error"])
		quit(2)
		return
	var runner: ScenarioRunner = ScenarioRunner.create()
	if runner == null:
		quit(1)
		return
	var wanted: String = options["scenario"]
	var results: Array[ScenarioResult] = []
	for path: String in ScenarioRunner.scenario_paths():
		var scenario: Dictionary = ScenarioRunner.load_file(path)
		var errors: Array[String] = runner.validate(scenario)
		if not errors.is_empty():
			printerr("balance_report: %s is invalid: %s" % [path, str(errors)])
			quit(1)
			return
		if wanted == ALL or wanted == scenario["id"]:
			results.append(runner.run(scenario))
	if results.is_empty():
		printerr("balance_report: no scenario named '%s'" % wanted)
		quit(2)
		return
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


func _parse(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"scenario": ALL, "out": ""}
	var index: int = 0
	while index < args.size():
		var flag: String = args[index]
		if flag not in ["--scenario", "--out"] or index + 1 >= args.size():
			return {"error": "unknown or incomplete option '%s'" % flag}
		options[flag.trim_prefix("--")] = args[index + 1]
		index += 2
	return options


func _write_files(out: String, results: Array[ScenarioResult], combined: Array[String]) -> bool:
	var directory: String = out if out.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("balance_report: cannot create %s" % directory)
		return false
	var ok: bool = _write(directory.path_join("balance_all.csv"), combined)
	for result: ScenarioResult in results:
		var lines: Array[String] = [ScenarioResult.csv_header()]
		lines.append_array(result.csv_lines())
		ok = _write(directory.path_join("balance_%s.csv" % result.id), lines) and ok
	return ok


func _write(path: String, lines: Array[String]) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("balance_report: cannot write %s" % path)
		return false
	file.store_string("\n".join(lines) + "\n")
	return true
