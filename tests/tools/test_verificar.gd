extends GutTest

# Issue #385 (T1): tools/verificar.gd run as the real process, the way an agent runs it. Each case starts a headless
# Godot on this project, so the exit code, the VERIFICAR_SALIDA= line and the files are what a caller sees.

const MARKER: String = "VERIFICAR_SALIDA="
const SAVES_DIR: String = "user://saves"
const SCENARIO: String = "small_rich"
# small_rich lasts 900 ticks = 15 minutes: the rows of minute 0..15.
const SCENARIO_ROWS: int = 16
const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
const EXIT_ERROR: int = 2

var _counter: int = 0
var _work_dir: String = ProjectSettings.globalize_path("res://build").path_join(
	"test_verificar_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])


func after_all() -> void:
	_remove_tree(_work_dir)


# ---- helpers ---------------------------------------------------------------------------------------------------------


# Runs the CLI; {code, output (stdout+stderr), marker ("" when absent), lines}.
func _run(args: Array[String]) -> Dictionary:
	var arguments: PackedStringArray = PackedStringArray(["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "tools/verificar.gd", "--"])
	arguments.append_array(PackedStringArray(args))
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), arguments, output, true)
	var text: String = String(output[0]) if not output.is_empty() else ""
	var marker: String = ""
	for line: String in text.split("\n"):
		if line.begins_with(MARKER):
			marker = line.trim_prefix(MARKER).strip_edges()
			break
	return {"code": code, "output": text, "marker": marker}


func _new_dir() -> String:
	_counter += 1
	return _work_dir.path_join("%d_%d" % [Time.get_ticks_usec(), _counter])


func _write_recipe(content: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(_work_dir)
	_counter += 1
	var path: String = _work_dir.path_join("recipe_%d.json" % _counter)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(content))
	file.close()
	return path


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read(path))
	return parsed if parsed is Dictionary else {}


func _recipe(extra: Dictionary) -> Dictionary:
	var recipe: Dictionary = {"id": "receta_test", "base": {"escenario": SCENARIO}}
	recipe.merge(extra, true)
	return recipe


func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if dir.is_link(sub):
			dir.remove(sub)
		else:
			_remove_tree(path.path_join(sub))
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)


# Name, size and content hash of everything under the saves folder; empty when it does not exist.
func _saves_listing() -> Array[String]:
	var found: Array[String] = []
	_list(SAVES_DIR, found)
	found.sort()
	return found


func _list(path: String, found: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub: String in DirAccess.get_directories_at(path):
		_list(path.path_join(sub), found)
	for file: String in DirAccess.get_files_at(path):
		found.append("%s %s" % [path.path_join(file), FileAccess.get_md5(path.path_join(file))])


# ---- the contract ----------------------------------------------------------------------------------------------------


func test_scenario_run_leaves_the_evidence_and_prints_the_marker_first() -> void:
	var directory: String = _new_dir()
	var run: Dictionary = _run(["--escenario", SCENARIO, "--salida", directory])
	assert_eq(run["code"], EXIT_OK, run["output"])
	assert_eq(run["marker"], directory, "the marker names the absolute folder")
	assert_eq(String(run["output"]).count(MARKER), 1, "printed once")
	for name: String in ["resumen.json", "estado.json", "serie.csv"]:
		assert_true(FileAccess.file_exists(directory.path_join(name)), name)
	assert_eq(_read(directory.path_join("serie.csv")).strip_edges().split("\n").size(), SCENARIO_ROWS + 1,
		"a header and one row per minute")
	var summary: Dictionary = _json(directory.path_join("resumen.json"))
	assert_eq(summary["resultado"], "OK")
	assert_eq(int(summary["exit_code"]), EXIT_OK)
	assert_eq(int(summary["ticks"]), 900, "the scenario's duration_ticks")
	assert_eq(int(summary["semilla"]), 42)
	assert_eq(int(_json(directory.path_join("estado.json"))["tick_count"]), 900,
		"estado.json is the whole snapshot at the final tick")


func test_default_folder_is_new_for_every_run() -> void:
	var first: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "1"])
	var second: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "1"])
	assert_eq(first["code"], EXIT_OK, first["output"])
	assert_eq(second["code"], EXIT_OK, second["output"])
	assert_ne(first["marker"], second["marker"])
	for marker: String in [first["marker"], second["marker"]]:
		assert_true(marker.is_absolute_path())
		assert_true(marker.contains("/build/verificacion/"), marker)
		assert_true(marker.ends_with(SCENARIO) or marker.contains(SCENARIO + "-"), marker)
		assert_true(FileAccess.file_exists(marker.path_join("resumen.json")))
		_remove_tree(marker)


func test_same_seed_and_recipe_give_the_same_bytes() -> void:
	var recipe: String = _write_recipe(_recipe({"ticks": 300, "acciones": [
		{"tick": 120, "cmd": "set_tax", "rate": 0.5}]}))
	var first: String = _new_dir()
	var second: String = _new_dir()
	assert_eq(_run(["--acciones", recipe, "--cada", "100", "--salida", first])["code"], EXIT_OK)
	assert_eq(_run(["--acciones", recipe, "--cada", "100", "--salida", second])["code"], EXIT_OK)
	for name: String in ["estado.json", "serie.csv", "resumen.json", "estados/estado-00000100.json",
			"estados/estado-00000300.json"]:
		assert_eq(_read(first.path_join(name)), _read(second.path_join(name)), name)
	assert_false(_read(first.path_join("estado.json")).is_empty())
	assert_eq(DirAccess.get_files_at(first.path_join("estados")).size(), 3, "--cada 100 over 300 ticks")


func test_a_recipe_action_changes_the_game() -> void:
	var plain: String = _new_dir()
	var acted: String = _new_dir()
	_run(["--escenario", SCENARIO, "--ticks", "300", "--salida", plain])
	var recipe: String = _write_recipe(_recipe({"ticks": 300, "acciones": [
		{"tick": 60, "cmd": "set_tax", "rate": 0.1}]}))
	var run: Dictionary = _run(["--acciones", recipe, "--salida", acted])
	assert_eq(run["code"], EXIT_OK, run["output"])
	assert_ne(_read(plain.path_join("estado.json")), _read(acted.path_join("estado.json")))
	var summary: Dictionary = _json(acted.path_join("resumen.json"))
	assert_eq(summary["escenario"], "receta_test")
	assert_eq(summary["comandos"].size(), 5, "the four of the scenario and the action")


func test_expectations_pass_and_a_failed_one_exits_1_and_is_marked() -> void:
	var good: String = _write_recipe(_recipe({"ticks": 60, "esperar": [
		{"ruta": "tick_count", "op": "==", "valor": 60},
		{"ruta": "economy.stocks.bread", "op": ">=", "valor": 0},
		{"ruta": "economy.tax_rate", "op": "==", "valor": 0.7}]}))
	var good_dir: String = _new_dir()
	assert_eq(_run(["--acciones", good, "--salida", good_dir])["code"], EXIT_OK)
	var passed: Array = _json(good_dir.path_join("resumen.json"))["expectativas"]
	assert_eq(passed.size(), 3)
	for check: Dictionary in passed:
		assert_eq(check["estado"], "OK")
	var bad: String = _write_recipe(_recipe({"ticks": 60, "esperar": [
		{"ruta": "tick_count", "op": "==", "valor": 60},
		{"ruta": "economy.stocks.bread", "op": ">", "valor": 1000000},
		{"ruta": "economy.no_such_key", "op": ">", "valor": 0}]}))
	var bad_dir: String = _new_dir()
	var run: Dictionary = _run(["--acciones", bad, "--salida", bad_dir])
	assert_eq(run["code"], EXIT_FAILED, run["output"])
	var summary: Dictionary = _json(bad_dir.path_join("resumen.json"))
	assert_eq(summary["resultado"], "FALLA")
	assert_eq(int(summary["exit_code"]), EXIT_FAILED)
	assert_eq(summary["expectativas"][0]["estado"], "OK")
	assert_eq(summary["expectativas"][1]["estado"], "FALLA")
	assert_eq(summary["expectativas"][2]["estado"], "FALLA")
	assert_eq(summary["expectativas"][2]["motivo"], "ruta no encontrada")
	assert_true(FileAccess.file_exists(bad_dir.path_join("estado.json")), "the evidence is left on a failure too")
	assert_eq(run["marker"], bad_dir, "the marker is published on exit 1")


func test_an_expectation_can_name_a_param_of_data() -> void:
	var recipe: String = _write_recipe(_recipe({"ticks": 60, "esperar": [
		{"ruta": "economy.money", "op": ">", "param": "startup.money"}]}))
	var run: Dictionary = _run(["--acciones", recipe, "--salida", _new_dir()])
	assert_eq(run["code"], EXIT_FAILED, "the city spent its money on three buildings: " + run["output"])
	var unknown: String = _write_recipe(_recipe({"ticks": 60, "esperar": [
		{"ruta": "economy.money", "op": ">", "param": "no.such.key"}]}))
	assert_eq(_run(["--acciones", unknown, "--salida", _new_dir()])["code"], EXIT_ERROR)


func test_an_unexpected_rejected_command_exits_1() -> void:
	# The wharf of the scenario already stands on that cell.
	var recipe: String = _write_recipe(_recipe({"ticks": 60, "acciones": [
		{"tick": 1, "cmd": "build", "building": "wharf", "cell": [4, 13]}]}))
	var directory: String = _new_dir()
	var run: Dictionary = _run(["--acciones", recipe, "--salida", directory])
	assert_eq(run["code"], EXIT_FAILED, run["output"])
	var summary: Dictionary = _json(directory.path_join("resumen.json"))
	assert_eq(summary["resultado"], "FALLA")
	assert_eq(summary["comandos_rechazados"].size(), 1)
	assert_false(summary["comandos_rechazados"][0]["accepted"])
	assert_ne(summary["comandos_rechazados"][0]["reason"], "")


func test_forcing_commands_work_in_preparar_but_not_in_acciones() -> void:
	var prepared: String = _write_recipe(_recipe({"ticks": 1, "preparar": [
		{"cmd": "set_stock", "good": "barley", "amount": 7}],
		"esperar": [{"ruta": "economy.stocks.barley", "op": "==", "valor": 7}]}))
	var run: Dictionary = _run(["--acciones", prepared, "--salida", _new_dir()])
	assert_eq(run["code"], EXIT_OK, run["output"])
	var forced: String = _write_recipe(_recipe({"ticks": 60, "acciones": [
		{"tick": 1, "cmd": "set_stock", "good": "barley", "amount": 7}]}))
	var directory: String = _new_dir()
	assert_eq(_run(["--acciones", forced, "--salida", directory])["code"], EXIT_ERROR)
	assert_eq(_json(directory.path_join("resumen.json"))["resultado"], "ERROR")


func test_zero_ticks_dumps_the_starting_state() -> void:
	var directory: String = _new_dir()
	var run: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "0", "--salida", directory])
	assert_eq(run["code"], EXIT_OK, run["output"])
	assert_eq(int(_json(directory.path_join("estado.json"))["tick_count"]), 0)
	assert_eq(_read(directory.path_join("serie.csv")).strip_edges().split("\n").size(), 2, "header and minute 0")
	var summary: Dictionary = _json(directory.path_join("resumen.json"))
	assert_eq(int(summary["ticks"]), 0)
	assert_eq(int(summary["comandos_omitidos_por_ticks"]), 4, "the four commands of the scenario never start")


func test_ticks_overrides_the_duration_and_a_late_action_is_an_error() -> void:
	var directory: String = _new_dir()
	var run: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "120", "--salida", directory])
	assert_eq(run["code"], EXIT_OK, run["output"])
	assert_eq(int(_json(directory.path_join("estado.json"))["tick_count"]), 120)
	var recipe: String = _write_recipe(_recipe({"ticks": 900, "acciones": [
		{"tick": 600, "cmd": "set_tax", "rate": 0.5}]}))
	var shorter: Dictionary = _run(["--acciones", recipe, "--ticks", "120", "--salida", _new_dir()])
	assert_eq(shorter["code"], EXIT_ERROR, "the action would never run: " + shorter["output"])
	var longer: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "1200", "--salida", _new_dir()])
	assert_eq(longer["code"], EXIT_OK, "more ticks than the scenario declares is fine")


func test_a_scenario_can_be_a_file() -> void:
	var run: Dictionary = _run(["--escenario", "tests/scenarios/%s.json" % SCENARIO, "--ticks", "1",
		"--salida", _new_dir()])
	assert_eq(run["code"], EXIT_OK, run["output"])


# ---- usage errors ----------------------------------------------------------------------------------------------------


func test_invalid_usage_exits_2_without_a_marker() -> void:
	var cases: Array[Array] = [[], ["--bogus"], ["--ticks", "abc", "--escenario", SCENARIO],
		["--ticks", "-1", "--escenario", SCENARIO], ["--cada", "0", "--escenario", SCENARIO],
		["--escenario"], ["--escenario", SCENARIO, "--escenario", SCENARIO],
		["--modo", "ui"], ["--modo", "bogus"], ["--partida", "x.sav"], ["--nuevo"], ["--funcion", "cadena_pan"], ["--humo"]]
	for args: Array in cases:
		var typed: Array[String] = []
		typed.assign(args)
		var run: Dictionary = _run(typed)
		assert_eq(run["code"], EXIT_ERROR, "%s: %s" % [str(args), run["output"]])
		assert_eq(run["marker"], "", str(args))


func test_help_exits_0() -> void:
	var run: Dictionary = _run(["--help"])
	assert_eq(run["code"], EXIT_OK)
	assert_true(String(run["output"]).contains("--escenario"))
	assert_eq(run["marker"], "")


func test_unknown_scenario_exits_2_with_the_marker_and_an_error_summary() -> void:
	var directory: String = _new_dir()
	var run: Dictionary = _run(["--escenario", "no_such_scenario", "--salida", directory])
	assert_eq(run["code"], EXIT_ERROR, run["output"])
	assert_eq(run["marker"], directory, "the folder was prepared, so it is published")
	assert_eq(_json(directory.path_join("resumen.json"))["resultado"], "ERROR")
	assert_false(FileAccess.file_exists(directory.path_join("estado.json")))


func test_invalid_recipe_exits_2() -> void:
	var cases: Array[Dictionary] = [{"bogus": 1}, {"ticks": -5}, {"esperar": [{"ruta": "tick_count", "op": "~"}]},
		{"esperar": [{"ruta": "tick_count", "op": "==", "valor": 1, "param": "startup.money"}]},
		{"acciones": [{"tick": 1, "cmd": "no_such_command"}]}, {"acciones": [{"cmd": "set_tax", "rate": 0.5}]},
		{"preparar": "x"}]
	for extra: Dictionary in cases:
		var run: Dictionary = _run(["--acciones", _write_recipe(_recipe(extra)), "--salida", _new_dir()])
		assert_eq(run["code"], EXIT_ERROR, "%s: %s" % [str(extra), run["output"]])


func test_a_recipe_without_base_needs_the_flag() -> void:
	var recipe: String = _write_recipe({"id": "sin_base", "ticks": 1})
	assert_eq(_run(["--acciones", recipe, "--salida", _new_dir()])["code"], EXIT_ERROR)
	assert_eq(_run(["--acciones", recipe, "--escenario", SCENARIO, "--salida", _new_dir()])["code"], EXIT_OK)


# ---- output folder safety --------------------------------------------------------------------------------------------


func test_output_with_a_newline_is_refused_and_never_echoed_as_a_marker() -> void:
	var run: Dictionary = _run(["--escenario", SCENARIO, "--salida", "x\n" + MARKER + "/etc/pwned"])
	assert_eq(run["code"], EXIT_ERROR, run["output"])
	assert_eq(run["marker"], "", "no line of the log may start with the marker")
	var carriage: Dictionary = _run(["--escenario", SCENARIO, "--salida", "x\r" + MARKER + "/etc/pwned"])
	assert_eq(carriage["code"], EXIT_ERROR)
	assert_eq(carriage["marker"], "")


func test_output_into_the_user_data_folder_is_refused() -> void:
	var user_dir: String = OS.get_user_data_dir()
	var cases: Array[String] = ["user://saves", "user://", "USER://saves", "user:/saves", "user:///saves", "user:saves",
		"res://build/x", user_dir, user_dir.path_join("saves"), user_dir.path_join("a/../saves"),
		user_dir.to_upper().path_join("saves"), user_dir + "//saves/./"]
	for case: String in cases:
		var run: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "1", "--salida", case])
		assert_eq(run["code"], EXIT_ERROR, "%s: %s" % [case, run["output"]])
		assert_eq(run["marker"], "", case)


func test_output_folder_with_evidence_of_another_run_is_refused() -> void:
	var directory: String = _new_dir()
	assert_eq(_run(["--escenario", SCENARIO, "--ticks", "1", "--salida", directory])["code"], EXIT_OK)
	var again: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "1", "--salida", directory])
	assert_eq(again["code"], EXIT_ERROR)
	assert_eq(again["marker"], "")


func test_runs_never_touch_the_saves_of_the_player() -> void:
	var before: Array[String] = _saves_listing()
	var run: Dictionary = _run(["--escenario", SCENARIO, "--salida", _new_dir()])
	assert_eq(run["code"], EXIT_OK, run["output"])
	var recipe: String = _write_recipe(_recipe({"ticks": 120}))
	var default_run: Dictionary = _run(["--acciones", recipe, "--cada", "60"])
	assert_eq(default_run["code"], EXIT_OK, default_run["output"])
	if not String(default_run["marker"]).is_empty():
		_remove_tree(default_run["marker"])
	assert_eq(_saves_listing(), before, "user://saves is as it was")


func test_explicit_sim_mode_is_accepted() -> void:
	var run: Dictionary = _run(["--escenario", SCENARIO, "--modo", "sim", "--ticks", "1", "--salida", _new_dir()])
	assert_eq(run["code"], EXIT_OK, run["output"])


# ---- the scenario file as declared -----------------------------------------------------------------------------------


func test_a_scenario_without_duration_plays_the_ticks_asked_or_zero() -> void:
	var file: String = _write_recipe({"id": "sin_duracion", "seed": 1, "commands": []})
	var directory: String = _new_dir()
	assert_eq(_run(["--escenario", file, "--ticks", "60", "--salida", directory])["code"], EXIT_OK)
	assert_eq(int(_json(directory.path_join("estado.json"))["tick_count"]), 60)
	var zero: String = _new_dir()
	assert_eq(_run(["--escenario", file, "--salida", zero])["code"], EXIT_OK)
	assert_eq(int(_json(zero.path_join("estado.json"))["tick_count"]), 0)


func test_a_malformed_scenario_exits_2_instead_of_being_normalized() -> void:
	var cases: Array[Dictionary] = [{"id": "a", "seed": 1, "duration_ticks": 60},
		{"id": "b", "seed": 1, "duration_ticks": 60, "commands": "x"},
		{"id": "c", "seed": 1, "duration_ticks": "abc", "commands": []},
		{"id": "d", "seed": 1, "duration_ticks": -5, "commands": []},
		{"id": "e", "seed": 1, "duration_ticks": 900, "commands": [{"tick": 500, "cmd": "bogus"}]}]
	for scenario: Dictionary in cases:
		var run: Dictionary = _run(["--escenario", _write_recipe(scenario), "--ticks", "60", "--salida", _new_dir()])
		assert_eq(run["code"], EXIT_ERROR, "%s: %s" % [str(scenario), run["output"]])


# ---- links -----------------------------------------------------------------------------------------------------------


func _link(target: String, link: String) -> bool:
	return OS.get_name() != "Windows" and OS.execute("ln", ["-s", target, link], []) == 0


func test_output_through_a_link_to_the_saves_is_refused() -> void:
	if OS.get_name() == "Windows":
		pending("symlinks need privileges on Windows")
		return
	var user_dir: String = OS.get_user_data_dir()
	var base: String = _new_dir()
	DirAccess.make_dir_recursive_absolute(base)
	var alias: String = base.path_join("alias")
	var evidence: String = "evidence_" + _work_dir.get_file()
	assert_true(_link(user_dir, alias))
	var run: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "1", "--salida", alias.path_join(evidence)])
	DirAccess.remove_absolute(alias)
	assert_eq(run["code"], EXIT_ERROR, run["output"])
	assert_eq(run["marker"], "")
	assert_false(DirAccess.dir_exists_absolute(user_dir.path_join(evidence)), "nothing was created behind the link")


func test_evidence_names_that_are_links_are_refused_even_dangling() -> void:
	if OS.get_name() == "Windows":
		pending("symlinks need privileges on Windows")
		return
	var outside: String = _new_dir()
	DirAccess.make_dir_recursive_absolute(outside)
	for name: String in ["resumen.json", "estado.json", "serie.csv", "estados"]:
		var directory: String = _new_dir()
		DirAccess.make_dir_recursive_absolute(directory)
		var target: String = outside.path_join("target_" + name)
		assert_true(_link(target, directory.path_join(name)))
		var run: Dictionary = _run(["--escenario", SCENARIO, "--ticks", "60", "--cada", "30", "--salida", directory])
		assert_eq(run["code"], EXIT_ERROR, "%s: %s" % [name, run["output"]])
		assert_eq(run["marker"], "", name)
		assert_false(FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target), "never written through " + name)
