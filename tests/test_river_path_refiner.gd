extends GutTest

const REFINER_PATH := "res://world/river_path_refiner.gd"


func test_refines_a_coarse_route_toward_fine_terrain() -> void:
	assert_true(ResourceLoader.exists(REFINER_PATH))
	if not ResourceLoader.exists(REFINER_PATH):
		return
	var refiner: RefCounted = (load(REFINER_PATH) as GDScript).new(1.0, 3.0)
	var coarse := PackedVector2Array([
		Vector2(-4.0, 0.0),
		Vector2.ZERO,
		Vector2(4.0, 0.0),
	])
	var refined := refiner.call(
		"refine", coarse, Callable(self, "_trough_height")
	) as PackedVector2Array

	assert_gt(refined.size(), coarse.size())
	assert_eq(refined[0], coarse[0])
	assert_eq(refined[-1], coarse[-1])
	var center := refined[0]
	for point in refined:
		if absf(point.x) < absf(center.x):
			center = point
	assert_gt(center.y, 1.0)
	assert_lte(center.y, 3.0)


func test_adds_subcell_curvature_on_a_uniform_slope() -> void:
	var refiner: RefCounted = (load(REFINER_PATH) as GDScript).new(1.0, 3.0)
	var coarse := PackedVector2Array([
		Vector2(-12.0, 0.0),
		Vector2.ZERO,
		Vector2(12.0, 0.0),
	])
	var refined := refiner.call(
		"refine", coarse, Callable(self, "_flat_height")
	) as PackedVector2Array
	var largest_offset := 0.0
	for point in refined:
		largest_offset = maxf(largest_offset, absf(point.y))

	assert_gt(largest_offset, 0.25)
	assert_lte(largest_offset, 0.75)


func _trough_height(position: Vector2) -> float:
	return absf(position.y - 2.0)


func _flat_height(_position: Vector2) -> float:
	return 0.0
