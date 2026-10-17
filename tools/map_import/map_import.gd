extends SceneTree

# Rebuilds data/maps/<id>.json from data/maps/sources/<id>/ (MapImporter). With --check it only compares, so CI
# or a reviewer can tell whether a committed map is out of date.

const SOURCES: String = "res://data/maps/sources"
const USAGE: String = """Usage: godot --headless --path . -s tools/map_import/map_import.gd -- <map_id>|all [--check]
  <map_id>   a folder of data/maps/sources/ (all: every folder)
  --check    do not write; exit 1 when data/maps/<id>.json differs from what the sources give"""


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var check: bool = "--check" in args
	var names: Array[String] = []
	for arg: String in args:
		if arg != "--check":
			names.append(arg)
	if names.size() != 1 or names[0] == "--help":
		print(USAGE)
		quit(0 if "--help" in args else 2)
		return
	var ids: PackedStringArray = DirAccess.get_directories_at(SOURCES) if names[0] == "all" else PackedStringArray(names)
	var status: int = 0
	for id: String in ids:
		status = maxi(status, _import(id, check))
	quit(status)


func _import(id: String, check: bool) -> int:
	var importer: MapImporter = MapImporter.new()
	var text: String = importer.to_text(importer.import_folder(SOURCES.path_join(id)))
	if not importer.errors.is_empty():
		printerr("map_import: %s: %s" % [id, "; ".join(importer.errors)])
		return 2
	var target: String = "res://data/maps/%s.json" % id
	if check:
		if FileAccess.get_file_as_string(target) != text:
			printerr("map_import: %s is out of date" % target)
			return 1
		print("map_import: %s is up to date" % target)
		return 0
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		printerr("map_import: cannot write %s" % target)
		return 2
	file.store_string(text)
	print("map_import: wrote %s" % target)
	return 0
