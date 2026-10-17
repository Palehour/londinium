extends SceneTree

# Parses GDScript files and exits 1 when one does not compile.
# Godot 3 renames are a text scan in check_gdscript.sh / .ps1: they do not need this process.
# Files under a .gdignore directory are still parsed when their path is passed in, via source
# reload, so the bad fixtures never enter --import.

var _failed: bool = false


func _init() -> void:
	var paths: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			paths.append(arg)
	if paths.is_empty():
		paths.append("res://src")
		paths.append("res://tests")
	var files: Array[String] = []
	for path: String in paths:
		_collect(path, files, true)
	files.sort()
	for file_path: String in files:
		if _parse_failed(file_path):
			_failed = true
	# Quit from the main loop. Quitting inside _init skips shutdown and reports every loaded script as a leak.
	call_deferred("quit", 1 if _failed else 0)


func _collect(path: String, into: Array[String], explicit: bool) -> void:
	var abs_path := _norm(_absolute(path)).trim_suffix("/")
	var is_dir := DirAccess.dir_exists_absolute(abs_path)
	if not is_dir and not FileAccess.file_exists(abs_path):
		printerr("check_gdscript: not found: %s" % path)
		_failed = true
		return
	if not is_dir:
		if abs_path.ends_with(".gd"):
			into.append(abs_path)
		return
	# A .gdignore skips the folder on the default walk. The path the user named is still checked.
	if not explicit and (abs_path.get_file() == "addons" or FileAccess.file_exists(abs_path.path_join(".gdignore"))):
		return
	var names: PackedStringArray = DirAccess.get_files_at(abs_path)
	for file_name: String in names:
		if file_name.ends_with(".gd"):
			into.append(_norm(abs_path.path_join(file_name)))
	var dirs: PackedStringArray = DirAccess.get_directories_at(abs_path)
	for dir_name: String in dirs:
		_collect(abs_path.path_join(dir_name), into, false)


func _parse_failed(abs_path: String) -> bool:
	var res_path := _to_res(abs_path)
	var text := FileAccess.get_file_as_string(abs_path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		printerr("check_gdscript: %s: cannot read (%s)" % [abs_path, error_string(FileAccess.get_open_error())])
		return true
	# load() of a test pulls GUT scenes, and Godot then reports those resources as leaks at exit.
	# class_name scripts are already registered, so reload() false-fails with "hides a global script class".
	if not res_path.is_empty() and not _under_gdignore(abs_path) and _declares_class_name(text):
		var loaded: Resource = ResourceLoader.load(res_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if loaded == null:
			printerr("check_gdscript: %s: parse error" % res_path)
			return true
		return false
	return _reload_failed(abs_path, res_path, text)


func _declares_class_name(text: String) -> bool:
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"):
			continue
		if trimmed.begins_with("class_name "):
			return true
	return false


func _reload_failed(abs_path: String, res_path: String, text: String) -> bool:
	var script := GDScript.new()
	# Taking the project path makes reload() load scenes the way load() does, and those leak at exit.
	# Ignored fixtures are not in the class cache, so the path is only there to name the error.
	if not res_path.is_empty() and _under_gdignore(abs_path):
		script.take_over_path(res_path)
	script.source_code = text
	var err: Error = script.reload()
	if err != OK:
		printerr("check_gdscript: %s: parse error" % (res_path if not res_path.is_empty() else abs_path))
		return true
	return false


func _under_gdignore(abs_path: String) -> bool:
	var root := _norm(ProjectSettings.globalize_path("res://")).trim_suffix("/")
	var dir := _norm(abs_path).get_base_dir()
	while dir.begins_with(root):
		if FileAccess.file_exists(dir.path_join(".gdignore")):
			return true
		if dir == root:
			return false
		var parent := dir.get_base_dir()
		if parent == dir:
			return false
		dir = parent
	return false


func _to_res(abs_path: String) -> String:
	var norm := _norm(abs_path)
	if norm.begins_with("res://"):
		return norm
	var root := _norm(ProjectSettings.globalize_path("res://")).trim_suffix("/")
	if norm.begins_with(root + "/"):
		return "res://" + norm.trim_prefix(root + "/")
	return ""


func _absolute(path: String) -> String:
	var norm := path.replace("\\", "/")
	if norm.begins_with("res://"):
		return ProjectSettings.globalize_path(norm)
	if norm.is_absolute_path():
		return norm
	return ProjectSettings.globalize_path("res://").path_join(norm)


func _norm(path: String) -> String:
	return path.replace("\\", "/")
