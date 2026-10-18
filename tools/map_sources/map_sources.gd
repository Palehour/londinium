extends SceneTree

# Rebuilds the GeoJSON layers of data/maps/sources/<id>/ from its committed raw downloads (MapSourceConverter).
# With --check it only compares, so CI or a reviewer can tell whether a layer is out of date. Then run
# tools/map_import. With --compare it draws docs/screenshots/<id>_compare.png from the imported map instead, the
# image Cristian validates the tracing with (MapComparison).

const SOURCES: String = "res://data/maps/sources"
const COMPARISON: String = "res://docs/screenshots/%s_compare.png"
const USAGE: String = """Usage: godot --headless --path . -s tools/map_sources/map_sources.gd -- <map_id>|all [flag]
  <map_id>   a folder of data/maps/sources/ with a sources.json (all: every such folder)
  flag       none (write the layers), --check or --compare
  --check    do not write; exit 1 when a layer differs from what the raw sources give
  --compare  draw docs/screenshots/<map_id>_compare.png: the NLS sheet beside the imported data/maps/<map_id>.json"""
const FLAGS: Array[String] = ["--check", "--compare"]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var check: bool = "--check" in args
	var names: Array[String] = []
	for arg: String in args:
		if arg not in FLAGS:
			names.append(arg)
	if names.size() != 1 or names[0] == "--help":
		print(USAGE)
		quit(0 if "--help" in args else 2)
		return
	var ids: PackedStringArray = DirAccess.get_directories_at(SOURCES) if names[0] == "all" else PackedStringArray(names)
	var status: int = 0
	for id: String in ids:
		var folder: String = SOURCES.path_join(id)
		if names[0] == "all" and not FileAccess.file_exists(folder.path_join(MapSourceConverter.MANIFEST)):
			continue
		status = maxi(status, _compare(id, folder) if "--compare" in args else _generate(folder, check))
	quit(status)


func _generate(folder: String, check: bool) -> int:
	var sources: MapSourceConverter = MapSourceConverter.new()
	var layers: Dictionary[String, String] = sources.generate_folder(folder)
	if not sources.errors.is_empty():
		printerr("map_sources: %s: %s" % [folder, "; ".join(sources.errors)])
		return 2
	var status: int = 0
	for layer: String in layers:
		var target: String = folder.path_join(layer)
		if check:
			if FileAccess.get_file_as_string(target) != layers[layer]:
				printerr("map_sources: %s is out of date" % target)
				status = 1
			continue
		var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			printerr("map_sources: cannot write %s" % target)
			return 2
		file.store_string(layers[layer])
		print("map_sources: wrote %s" % target)
	return status


func _compare(id: String, folder: String) -> int:
	var manifest_path: String = folder.path_join(MapSourceConverter.MANIFEST)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var grid: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(MapSourceConverter.GRID)))
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % id))
	if manifest is not Dictionary or manifest.get("nls") is not Dictionary or grid is not Dictionary \
			or map is not Dictionary:
		printerr("map_sources: %s needs sources.json with nls, import.json and data/maps/%s.json" % [folder, id])
		return 2
	var nls: Dictionary = manifest["nls"]
	var mosaic: NlsMosaic = NlsMosaic.load_folder(folder.path_join(nls["tiles"]), int(nls["zoom"]))
	var target: String = COMPARISON % id
	if MapComparison.new().render(mosaic, grid, map).save_png(target) != OK:
		printerr("map_sources: cannot write %s" % target)
		return 2
	print("map_sources: wrote %s" % target)
	return 0
