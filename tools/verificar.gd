extends SceneTree

# Verification CLI (issue #385, T1: simulation mode only). Plays a scenario, optionally with a recipe of scripted
# actions and expectations, and leaves evidence: resumen.json, estado.json, serie.csv and, with --cada, estados/.
# It only bootstraps from the SceneTree (no UI, no autosave, no game start) and never writes to user://, where the
# player's saves live. The game logic is ScenarioRunner's: validation, commands, rows and CSV.
# tools/verificar.sh and .ps1 copy their log into the folder named by the VERIFICAR_SALIDA= line.

const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
const EXIT_ERROR: int = 2
const MARKER: String = "VERIFICAR_SALIDA="
const DEFAULT_ROOT: String = "build/verificacion"
const EVIDENCE: Array[String] = ["resumen.json", "estado.json", "serie.csv", "estados"]
const OPERATORS: Array[String] = ["==", "!=", ">", ">=", "<", "<="]
const VALUE_FLAGS: Array[String] = ["--escenario", "--acciones", "--ticks", "--cada", "--salida", "--modo"]
# In the spec, not in T1.
const LATER_FLAGS: Array[String] = ["--partida", "--nuevo", "--preset", "--funcion", "--humo", "--captura"]
const RECIPE_KEYS: Array[String] = ["id", "descripcion", "base", "preparar", "acciones", "ticks", "esperar"]
# Forcing commands only prepare the game; a recipe must not use them to make its own result true.
const FORCING_COMMANDS: Array[String] = ["set_stock"]
const USAGE: String = """Usage: godot --headless --path . -s tools/verificar.gd -- [options]   (or tools/verificar.sh [options])
  --escenario <id|path>  scenario JSON (an id of tests/scenarios, or a file)
  --acciones <path.json> recipe: {"id", "base": {"escenario"}, "preparar": [], "acciones": [], "ticks", "esperar": []}
  --ticks <n>            ticks to play (60 = one game minute); default: the recipe's ticks, then duration_ticks. 0 is allowed
  --cada <n>             also keep a snapshot every n ticks in estados/
  --modo sim             simulation only (the default; ui is not supported yet)
  --salida <dir>         evidence folder (default build/verificacion/<date>-<name>, a new one for every run)
Needs --escenario or a recipe with base.escenario. Exit code: 0 all good, 1 a failed expectation or an unexpected
rejected command, 2 usage or data error. VERIFICAR_SALIDA=<absolute folder> is printed once the folder is ready."""

var _fs: DirAccess = DirAccess.open(ProjectSettings.globalize_path("res://"))


func _init() -> void:
	quit(_main(OS.get_cmdline_user_args()))


func _main(args: PackedStringArray) -> int:
	var options: Dictionary = _parse(args)
	if options.has("error"):
		return _usage_error(String(options["error"]))
	if options["help"]:
		print(USAGE)
		return EXIT_OK
	var prepared: Dictionary = _prepare_output(options)
	if prepared.has("error"):
		return _usage_error(String(prepared["error"]))
	print(MARKER + String(prepared["dir"]))
	return _verify(options, prepared["dir"])


# Messages quote user input: one line each, so none of it can look like the marker line.
func _usage_error(message: String) -> int:
	printerr("verificar: %s" % message.replace("\r", " ").replace("\n", " "))
	return EXIT_ERROR


func _parse(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"help": false}
	var index: int = 0
	while index < args.size():
		var flag: String = args[index]
		if flag == "--help":
			return {"help": true} if args.size() == 1 else {"error": "--help must be used alone"}
		if flag in LATER_FLAGS:
			return {"error": "%s is not supported yet" % flag}
		if flag not in VALUE_FLAGS:
			return {"error": "unknown option '%s' (see --help)" % flag}
		if index + 1 >= args.size() or args[index + 1].begins_with("--") or options.has(flag.trim_prefix("--")):
			return {"error": "%s needs one value" % flag}
		var value: String = args[index + 1]
		if (flag == "--ticks" and (not value.is_valid_int() or int(value) < 0)) \
				or (flag == "--cada" and (not value.is_valid_int() or int(value) < 1)):
			return {"error": "%s needs a whole number (>= 0 for --ticks, >= 1 for --cada)" % flag}
		if flag == "--modo" and value != "sim":
			return {"error": "--modo %s is not supported yet, only sim" % value}
		options[flag.trim_prefix("--")] = value
		index += 2
	if not options["help"] and not options.has("escenario") and not options.has("acciones"):
		return {"error": "needs --escenario or --acciones (see --help)"}
	return options


# ---- evidence folder -------------------------------------------------------------------------------------------------


func _prepare_output(options: Dictionary) -> Dictionary:
	if options.has("salida"):
		return _prepare_explicit(String(options["salida"]))
	var root: String = _absolute(DEFAULT_ROOT)
	if _inside_user_data(root) or _linked(root) or DirAccess.make_dir_recursive_absolute(root) != OK:
		return {"error": "cannot use %s (a link, or not writable)" % root}
	# Without this, the editor imports serie.csv as a translation on the next --import.
	var ignore: String = root.path_join(".gdignore")
	if _fs.is_link(ignore) or (not FileAccess.file_exists(ignore) and not _write(ignore, "# CLI evidence, not game assets.\n")):
		return {"error": "cannot exclude %s from Godot imports" % root}
	var source: String = String(options.get("escenario", options.get("acciones", ""))).get_file().get_basename()
	var name: String = RegEx.create_from_string("[^A-Za-z0-9_-]").sub(source, "_", true)
	var now: Dictionary = Time.get_datetime_dict_from_system()
	var stem: String = "%04d%02d%02d-%02d%02d%02d-%s" % [now["year"], now["month"], now["day"], now["hour"],
		now["minute"], now["second"], name]
	# make_dir_absolute fails when the folder exists, so two runs of the same second never share one.
	for attempt: int in range(1000):
		var candidate: String = root.path_join(stem if attempt == 0 else "%s-%d" % [stem, attempt + 1])
		if DirAccess.make_dir_absolute(candidate) == OK:
			return {"dir": candidate}
	return {"error": "cannot find a free folder in %s" % root}


# Refused: control characters (a newline would fake a marker line), every scheme (user://, res:// and aliases such as
# user:/ or USER:///), the user data folder, any link on the way (it could point there) and evidence already there.
func _prepare_explicit(raw: String) -> Dictionary:
	var lowered: String = raw.to_lower()
	if raw.strip_edges().is_empty() or RegEx.create_from_string("[\\x01-\\x1f\\x7f]").search(raw) != null \
			or lowered.begins_with("user:") or lowered.begins_with("res:") or raw.contains("://"):
		return {"error": "--salida needs a folder of the file system, without control characters or user:// or res://"}
	var directory: String = _absolute(raw)
	if _inside_user_data(directory) or _linked(directory):
		return {"error": "--salida is in the user data folder, or goes through a link"}
	for name: String in EVIDENCE:
		if _fs.is_link(directory.path_join(name)) or FileAccess.file_exists(directory.path_join(name)) \
				or DirAccess.dir_exists_absolute(directory.path_join(name)):
			return {"error": "--salida already has evidence of another run (or a link with its name)"}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"error": "--salida: cannot create the folder"}
	return {"dir": directory}


# Absolute, with / separators and without . or .., so the comparisons see the real place. Relative paths start at the
# project folder.
func _absolute(raw: String) -> String:
	var path: String = raw.replace("\\", "/")
	if not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://").path_join(path)
	return path.simplify_path()


func _inside_user_data(path: String) -> bool:
	var lowered: String = path.to_lower()
	for base: String in [OS.get_user_data_dir(), ProjectSettings.globalize_path("user://")]:
		var root: String = base.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
		if not root.is_empty() and (lowered == root or lowered.begins_with(root + "/")):
			return true
	return false


# True when the path, or a folder on the way to it, is a link (a dangling one too): a link may point into the saves.
# The project folder and what is above it are trusted; that is where the default folder lives.
func _linked(path: String) -> bool:
	var project: String = _absolute("")
	var skip: int = project.split("/").size() if path.begins_with(project + "/") else 0
	var parts: PackedStringArray = path.split("/")
	var current: String = ""
	for index: int in range(parts.size()):
		current = parts[0] if index == 0 else current + "/" + parts[index]
		if index >= skip and index > 0 and not parts[index].is_empty() and _fs.is_link(current):
			return true
	return false


# ---- the run ---------------------------------------------------------------------------------------------------------


func _verify(options: Dictionary, directory: String) -> int:
	var runner: ScenarioRunner = ScenarioRunner.create()
	if runner == null:
		return _fail(directory, "data/ did not load (see the errors above)")
	runner.allow_zero_ticks = true
	runner.snapshot_every = int(options.get("cada", 0))
	var loaded: Dictionary = _load_inputs(options, runner)
	if loaded.has("error"):
		return _fail(directory, String(loaded["error"]))
	var scenario: Dictionary = loaded["scenario"]
	var expectations: Array = loaded["expectations"]
	var errors: Array[String] = runner.validate(scenario)
	errors.append_array(_expectation_errors(expectations, runner))
	if not errors.is_empty():
		return _fail(directory, "invalid input: %s" % "; ".join(errors))
	var result: ScenarioResult = runner.run(scenario)
	var state: Dictionary = _plain(result.final_snapshot)
	var checks: Array[Dictionary] = []
	for entry: Dictionary in expectations:
		checks.append(_evaluate(entry, state, runner))
	var failed: int = checks.filter(func(check: Dictionary) -> bool: return check["estado"] == "FALLA").size()
	var rejected: Array[Dictionary] = result.unexpected_rejections()
	var code: int = EXIT_FAILED if failed > 0 or not rejected.is_empty() else EXIT_OK
	var summary: Dictionary = _plain({"resultado": "OK" if code == EXIT_OK else "FALLA", "exit_code": code,
		"escenario": scenario["id"], "base": loaded["base"], "receta": loaded["recipe"], "semilla": scenario["seed"],
		"ticks": scenario["duration_ticks"], "comandos_omitidos_por_ticks": loaded["omitted"],
		"godot": Engine.get_version_info()["string"], "commit": _commit(),
		"derrota": {"tick": result.defeat_tick, "causas": result.defeat_causes}, "expectativas": checks,
		"comandos": result.commands, "comandos_rechazados": rejected})
	if not _write_evidence(directory, summary, state, result):
		return _fail(directory, "cannot write the evidence")
	print("verificar: %s escenario=%s ticks=%d" % [summary["resultado"], summary["escenario"], int(summary["ticks"])])
	for check: Dictionary in checks:
		print("verificar: %s %s %s %s" % [check["estado"], check["ruta"], check["op"], check["esperado"]])
	for entry: Dictionary in rejected:
		printerr("verificar: comando rechazado %s (%s)" % [entry["cmd"], entry["reason"]])
	return code


func _fail(directory: String, message: String) -> int:
	_usage_error(message)
	_write(directory.path_join(EVIDENCE[0]), _json({"resultado": "ERROR", "error": message.replace("\n", " "),
		"exit_code": EXIT_ERROR}))
	return EXIT_ERROR


# Returns {scenario, expectations, base, recipe, omitted} or {error}. The scenario file is validated as declared
# (with the longer of its duration and --ticks) before the recipe is merged in.
func _load_inputs(options: Dictionary, runner: ScenarioRunner) -> Dictionary:
	var recipe: Dictionary = {}
	if options.has("acciones"):
		recipe = ScenarioRunner.load_file(_input_path(String(options["acciones"])))
		var problem: String = _recipe_problem(recipe)
		if not problem.is_empty():
			return {"error": "recipe: %s" % problem}
	var reference: String = String(options.get("escenario", ""))
	if reference.is_empty() and recipe.has("base"):
		var recipe_base: Dictionary = recipe["base"]
		reference = String(recipe_base.get("escenario", ""))
	var base: Dictionary = ScenarioRunner.load_file(_find_scenario(reference)) if not reference.is_empty() else {}
	if base.is_empty():
		return {"error": "cannot find or read the scenario '%s'" % reference}
	if base.get("commands") is not Array:
		return {"error": "the scenario's commands must be a list"}
	var declared: Variant = base.get("duration_ticks", 0)
	if not _whole(declared) or int(declared) < 0:
		return {"error": "the scenario's duration_ticks must be a whole number >= 0"}
	var ticks: int = int(options.get("ticks", recipe.get("ticks", declared)))
	var original: Dictionary = base.duplicate(true)
	original["duration_ticks"] = maxi(int(declared), ticks)
	var errors: Array[String] = runner.validate(original)
	if not errors.is_empty():
		return {"error": "invalid scenario: %s" % "; ".join(errors)}
	var composed: Dictionary = _compose(base, recipe, ticks)
	if composed.has("error"):
		return composed
	return {"scenario": composed["scenario"], "expectations": recipe.get("esperar", []), "omitted": composed["omitted"],
		"recipe": String(options.get("acciones", "")), "base": reference}


# preparar (forces allowed, tick 0) first, then the scenario's commands, then each action after every command of its
# tick or earlier. With fewer ticks than the scenario lasts, its later commands and prices are left out and counted;
# an action outside the run is an error.
func _compose(base: Dictionary, recipe: Dictionary, ticks: int) -> Dictionary:
	var omitted: int = 0
	var kept: Array = []
	var commands: Array = []
	for entry: Variant in recipe.get("preparar", []):
		var setup: Dictionary = (entry as Dictionary).duplicate(true)
		setup["tick"] = 0
		commands.append(setup)
	commands.append_array(base["commands"])
	for entry: Variant in commands:
		omitted += int(_tick_of(entry) >= ticks)
		if _tick_of(entry) < ticks:
			kept.append(entry)
	var previous: int = 0
	for entry: Variant in recipe.get("acciones", []):
		var action: Dictionary = (entry as Dictionary).duplicate(true)
		if String(action.get("cmd", "")) in FORCING_COMMANDS:
			return {"error": "acciones: '%s' forces the game; use it in preparar" % action["cmd"]}
		if not _whole(action.get("tick")) or int(action["tick"]) < previous or int(action["tick"]) >= ticks:
			return {"error": "acciones: every action needs a whole tick, in order, inside the %d ticks" % ticks}
		previous = int(action["tick"])
		var at: int = kept.size()
		while at > 0 and _tick_of(kept[at - 1]) > previous:
			at -= 1
		kept.insert(at, action)
	var scenario: Dictionary = base.duplicate(true)
	scenario["id"] = String(recipe.get("id", base.get("id", "")))
	scenario["duration_ticks"] = ticks
	scenario["commands"] = kept
	scenario.erase("measure")  # its windows belong to balance_report and to the declared length
	if scenario.get("price_schedule") is Array:
		var schedule: Array = scenario["price_schedule"].filter(func(entry: Variant) -> bool: return _tick_of(entry) < ticks)
		omitted += scenario["price_schedule"].size() - schedule.size()
		scenario["price_schedule"] = schedule
	return {"scenario": scenario, "omitted": omitted}


func _tick_of(entry: Variant) -> int:
	return int(entry["tick"]) if entry is Dictionary and _whole(entry.get("tick")) else -1


func _recipe_problem(recipe: Dictionary) -> String:
	if recipe.is_empty():
		return "cannot read it"
	for key: Variant in recipe:
		if str(key) not in RECIPE_KEYS:
			return "unknown key '%s'" % str(key)
	if recipe.has("base") and (recipe["base"] is not Dictionary or recipe["base"].get("escenario") is not String):
		return "base must be {\"escenario\": <id or path>}"
	if recipe.has("ticks") and (not _whole(recipe["ticks"]) or int(recipe["ticks"]) < 0):
		return "ticks must be a whole number >= 0"
	for key: String in ["preparar", "acciones", "esperar"]:
		var list: Variant = recipe.get(key, [])
		if list is not Array or list.any(func(entry: Variant) -> bool: return entry is not Dictionary):
			return "%s must be a list of objects" % key
	return ""


# An input file: never user://, relative ones from the project folder.
func _input_path(raw: String) -> String:
	if raw.begins_with("res://"):
		return raw
	return "" if raw.to_lower().begins_with("user:") or raw.contains("://") else _absolute(raw)


func _find_scenario(reference: String) -> String:
	if reference.ends_with(".json") or reference.contains("/") or reference.contains("\\"):
		return _input_path(reference)
	var paths: Array[String] = ScenarioRunner.scenario_paths()
	for more: Array[String] in [ScenarioRunner.long_scenario_paths(), ScenarioRunner.strip_scenario_paths(),
			ScenarioRunner.strip_long_scenario_paths()]:
		paths.append_array(more)
	for path: String in paths:
		if path.get_file().get_basename() == reference:
			return path
	return ""


# ---- expectations ----------------------------------------------------------------------------------------------------


func _expectation_errors(expectations: Array, runner: ScenarioRunner) -> Array[String]:
	var errors: Array[String] = []
	for index: int in range(expectations.size()):
		var entry: Dictionary = expectations[index]
		var where: String = "esperar[%d]" % index
		if entry.get("ruta") is not String or String(entry["ruta"]).is_empty():
			errors.append("%s: ruta must be a non-empty string" % where)
		if entry.get("op") not in OPERATORS:
			errors.append("%s: op must be one of %s" % [where, ", ".join(OPERATORS)])
		if entry.has("valor") == entry.has("param"):
			errors.append("%s: give exactly one of valor or param" % where)
		elif entry.has("param") and (entry["param"] is not String or not runner.has_param(StringName(entry["param"]))):
			errors.append("%s: param is not a key of data/" % where)
	return errors


func _evaluate(entry: Dictionary, state: Dictionary, runner: ScenarioRunner) -> Dictionary:
	var expected: Variant = runner.param(StringName(entry["param"])) if entry.has("param") else entry["valor"]
	var record: Dictionary = {"ruta": entry["ruta"], "op": entry["op"], "esperado": _plain(expected), "estado": "FALLA"}
	var current: Variant = state
	for step: String in String(entry["ruta"]).split("."):
		if current is Dictionary and current.has(step):
			current = current[step]
		elif current is Array and step.is_valid_int() and int(step) >= 0 and int(step) < current.size():
			current = current[int(step)]
		else:
			record["motivo"] = "ruta no encontrada"
			return record
	record["obtenido"] = current
	var numbers: bool = typeof(current) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]
	var op: String = entry["op"]
	if op in ["==", "!="]:
		var same: bool = float(current) == float(expected) if numbers else typeof(current) == typeof(expected) and current == expected
		record["estado"] = "OK" if same == (op == "==") else "FALLA"
	elif not numbers:
		record["motivo"] = "valores no comparables"
	else:
		var a: float = float(current)
		var b: float = float(expected)
		record["estado"] = "OK" if (a > b if op == ">" else a >= b if op == ">=" else a < b if op == "<" else a <= b) else "FALLA"
	return record


# ---- evidence --------------------------------------------------------------------------------------------------------


func _write_evidence(directory: String, summary: Dictionary, state: Dictionary, result: ScenarioResult) -> bool:
	var lines: Array[String] = [ScenarioResult.csv_header()]
	lines.append_array(result.csv_lines())
	var ok: bool = _write(directory.path_join(EVIDENCE[1]), _json(state))
	ok = _write(directory.path_join(EVIDENCE[2]), "\n".join(lines) + "\n") and ok
	if not result.snapshots.is_empty():
		var folder: String = directory.path_join(EVIDENCE[3])
		if DirAccess.make_dir_absolute(folder) != OK:
			return false
		for item: Dictionary in result.snapshots:
			ok = _write(folder.path_join("estado-%08d.json" % int(item["tick"])), _json(_plain(item["snapshot"]))) and ok
	return ok and _write(directory.path_join(EVIDENCE[0]), _json(summary))


# Keys sorted and floats at full precision, so the same game always gives the same bytes.
func _json(value: Variant) -> String:
	return JSON.stringify(value, "\t", true, true) + "\n"


func _write(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("verificar: cannot write %s" % path)
		return false
	return file.store_string(text)


func _commit() -> String:
	var output: Array = []
	var args: PackedStringArray = PackedStringArray(["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"])
	var text: String = String(output[0]).strip_edges() if OS.execute("git", args, output, true) == 0 and not output.is_empty() else ""
	return text if text.length() >= 7 and text.is_valid_hex_number() else "desconocido"


# What JSON can hold: string keys, no StringName, no vectors, no NaN or infinity.
static func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var safe: Dictionary = {}
		for key: Variant in value:
			safe[str(key)] = _plain(value[key])
		return safe
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return _plain(item))
	if value is Vector2i or value is Vector2:
		return [value.x, value.y]
	if value is float:
		return str(value) if is_nan(value) or is_inf(value) else value
	return value if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING] else str(value)


static func _whole(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_equal_approx(float(value), roundf(float(value)))
