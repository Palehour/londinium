extends SceneTree

# Rebuilds the GeoJSON layers of data/maps/sources/<id>/ from its committed raw downloads (MapSourceConverter); then
# run tools/map_import. With --compare it draws docs/screenshots/<id>_compare.png from the imported map, the image
# Cristian validates the tracing with (MapComparison), and writes nls_report.md beside the sources: the error of every
# control point and where the sheets put each named place. With --check it only compares the layers and the report,
# so CI or a reviewer can tell whether something is out of date. --join builds a committed sheet crop from the IIIF
# tiles downloaded as data/maps/sources/README.md says (issue #170).

const SOURCES: String = "res://data/maps/sources"
const MAPS: String = "res://data/maps/%s.json"
const COMPARISON: String = "res://docs/screenshots/%s_compare.png"
const USAGE: String = """Usage: godot --headless --path . -s tools/map_sources/map_sources.gd -- <map_id>|all [flag]
  <map_id>   a folder of data/maps/sources/ with a sources.json (all: every such folder)
  flag       none (write the layers), --check or --compare
  --check    do not write; exit 1 when a layer or nls_report.md differs from what the raw sources give
  --compare  draw docs/screenshots/<map_id>_compare.png and write nls_report.md from data/maps/<map_id>.json
       or: -- --join <tiles folder> <iiif id> <scale> <x> <y> <width> <height> <out.jpg>
  --join     join the IIIF tiles <iiif id>_<scale>_<x>_<y>.jpg into the crop x, y, width, height (full-resolution
             pixels of the sheet), one pixel per <scale> of them"""
const FLAGS: Array[String] = ["--check", "--compare"]
const JOIN_ARGUMENTS: int = 9
const JPG_QUALITY: float = 0.9


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == JOIN_ARGUMENTS and args[0] == "--join":
		quit(_join(args))
		return
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
		status = maxi(status, _compare(id, folder) if "--compare" in args else _generate(id, folder, "--check" in args))
	quit(status)


func _generate(id: String, folder: String, check: bool) -> int:
	var sources: MapSourceConverter = MapSourceConverter.new()
	var layers: Dictionary[String, String] = sources.generate_folder(folder)
	if not sources.errors.is_empty():
		printerr("map_sources: %s: %s" % [folder, "; ".join(sources.errors)])
		return 2
	if check and FileAccess.file_exists(folder.path_join(MapSourceConverter.REPORT)):
		layers[MapSourceConverter.REPORT] = sources.report(folder, _read(MAPS % id))
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
		if not _write(target, layers[layer]):
			return 2
	return status


func _compare(id: String, folder: String) -> int:
	var grid: Variant = _read(folder.path_join(MapSourceConverter.GRID))
	var map: Variant = _read(MAPS % id)
	if grid is not Dictionary or map is not Dictionary:
		printerr("map_sources: %s needs import.json and data/maps/%s.json" % [folder, id])
		return 2
	var sources: MapSourceConverter = MapSourceConverter.new()
	var sheets: NlsSheets = sources.sheets(folder)
	var text: String = sources.report(folder, map)
	if not sources.errors.is_empty() or sheets.is_empty():
		printerr("map_sources: %s: %s" % [folder, "; ".join(sources.errors) if not sources.errors.is_empty()
			else "sources.json lists no NLS sheets"])
		return 2
	var image: Image = MapComparison.new().render(sheets, grid, map, sources.gap_cells(folder), sheets.place_points(grid))
	var target: String = COMPARISON % id
	if image.save_png(target) != OK:
		printerr("map_sources: cannot write %s" % target)
		return 2
	print("map_sources: wrote %s" % target)
	return 0 if _write(folder.path_join(MapSourceConverter.REPORT), text) else 2


# Joins the tiles of one sheet (the scale the server cut them at) and keeps the crop the map needs.
func _join(args: PackedStringArray) -> int:
	var scale: int = int(args[3])
	var crop: Rect2i = Rect2i(int(args[4]), int(args[5]), int(args[6]), int(args[7]))
	var image: Image = Image.create(ceili(crop.size.x / float(scale)), ceili(crop.size.y / float(scale)), false,
		Image.FORMAT_RGB8)
	var prefix: String = "%s_%d_" % [args[2], scale]
	var joined: int = 0
	for file: String in DirAccess.get_files_at(args[1]):
		var parts: PackedStringArray = file.get_basename().trim_prefix(prefix).split("_")
		if not file.begins_with(prefix) or parts.size() != 2:
			continue
		var tile: Image = Image.load_from_file(ProjectSettings.globalize_path(args[1].path_join(file)))
		if tile == null:
			continue
		tile.convert(Image.FORMAT_RGB8)
		var at: Vector2i = (Vector2i(int(parts[0]), int(parts[1])) - crop.position) / scale
		image.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), at)
		joined += 1
	if joined == 0 or image.save_jpg(args[8], JPG_QUALITY) != OK:
		printerr("map_sources: no tiles %s* in %s, or cannot write %s" % [prefix, args[1], args[8]])
		return 2
	print("map_sources: joined %d tiles into %s" % [joined, args[8]])
	return 0


func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


func _write(target: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		printerr("map_sources: cannot write %s" % target)
		return false
	file.store_string(text)
	print("map_sources: wrote %s" % target)
	return true
