extends GutTest

# The boxes of the 3D greybox (issue #65, D-028): each building type has its own height and silhouette, as a small block
# with its leading building among filler houses, inside its footprint. The look lives in data/ui/city.json.

const CELL_M: float = 25.0

var _style: CityPresentation
var _ids: Array[StringName] = []


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_ids.assign(loaded.catalog.buildings.keys())
	_style = CityPresentation.new()
	_style.load_data(_ids)


func _pieces(id: StringName, footprint: Vector2i) -> Array[Dictionary]:
	return CityLayout.pieces(_style.shapes[id], _style.filler, _style.chimney_side, Rect2(Vector2.ZERO, Vector2(footprint) * CELL_M), 0.0, 0)


func _kinds(pieces: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	return pieces.filter(func(piece: Dictionary) -> bool: return piece["kind"] == kind)


func test_the_data_gives_every_building_a_shape_and_a_colour() -> void:
	assert_eq(_style.errors, [] as Array[String])
	for id: StringName in _ids:
		assert_true(_style.shapes.has(id), "%s has a shape" % id)
		assert_true(_style.colors.has(id), "%s has a colour" % id)


func test_a_building_without_a_shape_or_with_a_bad_roof_is_an_error() -> void:
	var json: JSON = JSON.new()
	json.parse(FileAccess.get_file_as_string(CityPresentation.PATH))
	var raw: Dictionary = json.data
	raw["buildings"].erase("mill")
	raw["buildings"]["bakery"]["roof"] = "dome"
	raw["buildings"]["housing"]["width_ratio"] = 1.5
	var style: CityPresentation = CityPresentation.new()
	style.validate(raw, _ids)
	assert_eq(style.errors.size(), 3, str(style.errors))


func test_each_type_reads_by_its_height_and_silhouette() -> void:
	var mill: Array[Dictionary] = _pieces(&"mill", Vector2i(2, 2))
	var housing: Array[Dictionary] = _pieces(&"housing", Vector2i(2, 2))
	assert_gt(CityLayout.bounds(mill).size.y, CityLayout.bounds(housing).size.y, "A mill stands over the houses")
	assert_eq(_kinds(mill, CityLayout.CHIMNEY).size(), 1, "The mill has its chimney")
	assert_eq(_kinds(housing, CityLayout.ROOF).size(), 1, "Houses have a gable roof")
	assert_eq(_kinds(_pieces(&"wheat_field", Vector2i(2, 2)), CityLayout.FILLER).size(), 0, "A field has no houses on it")
	var main: AABB = _kinds(housing, CityLayout.MAIN)[0]["box"]
	assert_eq(main.size.y, float(_style.shapes[&"housing"]["height_m"]))


func test_the_leading_block_is_among_fillers_that_never_cross_it_or_leave_the_footprint() -> void:
	for id: StringName in _ids:
		var footprint: Vector2i = Vector2i(2, 2) if id != &"well" else Vector2i.ONE
		var pieces: Array[Dictionary] = _pieces(id, footprint)
		var main: AABB = _kinds(pieces, CityLayout.MAIN)[0]["box"]
		var ground: AABB = AABB(Vector3.ZERO, Vector3(footprint.x * CELL_M, 1000, footprint.y * CELL_M))
		for piece: Dictionary in pieces:
			assert_true(ground.encloses(piece["box"]), "%s: every box inside the footprint" % id)
		for filler: Dictionary in _kinds(pieces, CityLayout.FILLER):
			assert_false((filler["box"] as AABB).intersects(main), "%s: a filler never crosses the leading block" % id)
		if _style.shapes[id]["fillers"]:
			assert_gt(_kinds(pieces, CityLayout.FILLER).size(), 0, "%s stands among filler houses" % id)


func test_neighbouring_blocks_vary_their_fillers() -> void:
	var area: Rect2 = Rect2(Vector2.ZERO, Vector2(50, 50))
	var heights: Array[float] = []
	for variation: int in range(CityLayout.FILLER_HEIGHT_STEPS):
		var pieces: Array[Dictionary] = CityLayout.pieces(_style.shapes[&"housing"], _style.filler, _style.chimney_side, area, 0.0, variation)
		heights.append((_kinds(pieces, CityLayout.FILLER)[0]["box"] as AABB).size.y)
	assert_ne(heights[0], heights[1])
	assert_ne(heights[1], heights[2])
