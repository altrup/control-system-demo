extends GutTest

const SHORELINE_PATH := "res://world/river_shoreline.gd"
const WorldGenerator := preload("res://world/world_generator.gd")


func test_shorelines_follow_the_carved_terrain_waterline() -> void:
	assert_true(ResourceLoader.exists(SHORELINE_PATH))
	if not ResourceLoader.exists(SHORELINE_PATH):
		return
	var shoreline_script := load(SHORELINE_PATH) as GDScript
	var generator := WorldGenerator.new(481516)
	var branches: Array = shoreline_script.new().build(
		generator.stream_branches(),
		Callable(generator, "height_at")
	)
	var checked_points := 0
	for branch in branches:
		for point in branch.points:
			if not _is_inside_world(point.center, 6.0):
				continue
			checked_points += 1
			assert_almost_eq(
				generator.height_at(Vector2(point.left_shore.x, point.left_shore.z)),
				point.center.y,
				0.01
			)
			assert_almost_eq(
				generator.height_at(Vector2(point.right_shore.x, point.right_shore.z)),
				point.center.y,
				0.01
			)
			assert_gt(
				Vector2(point.center.x, point.center.z).distance_to(
					Vector2(point.left_shore.x, point.left_shore.z)
				),
				point.bed_half_width
			)
			assert_gt(
				Vector2(point.center.x, point.center.z).distance_to(
					Vector2(point.right_shore.x, point.right_shore.z)
				),
				point.bed_half_width
			)

	assert_gt(checked_points, 100)


func test_water_edges_extend_under_both_banks() -> void:
	var generator := WorldGenerator.new(481516)
	var branches: Array = load(SHORELINE_PATH).new().build(
		generator.stream_branches(),
		Callable(generator, "height_at")
	)
	var checked_points := 0
	for branch in branches:
		for point in branch.points:
			if not _is_inside_world(point.center, 6.0):
				continue
			checked_points += 1
			assert_gt(
				_point_distance(point.center, point.left_edge),
				_point_distance(point.center, point.left_shore) + 0.05
			)
			assert_gt(
				_point_distance(point.center, point.right_edge),
				_point_distance(point.center, point.right_shore) + 0.05
			)

	assert_gt(checked_points, 100)


func _is_inside_world(position: Vector3, margin: float) -> bool:
	return (
		position.x >= margin
		and position.z >= margin
		and position.x <= WorldGenerator.REGION_SIZE - 1 - margin
		and position.z <= WorldGenerator.REGION_SIZE - 1 - margin
	)


func _point_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))
