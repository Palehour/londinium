extends GutTest

func test_every_project_script_parses_and_instantiates() -> void:
	var paths: Array[String] = _collect("res://src")
	paths.append_array(_collect("res://tests"))
	assert_gt(paths.size(), 0, "Expected at least one project script.")
	for path: String in paths:
		var script: GDScript = load(path) as GDScript
		assert_not_null(script, "Did not parse: %s" % path)
		if script == null:
			continue
		assert_true(script.can_instantiate(), "Cannot instantiate: %s" % path)
		var instance: Object = script.new()
		assert_not_null(instance, "new() returned null: %s" % path)
		if instance is Node:
			(instance as Node).free()


func _collect(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path: String = root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_collect(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	return found