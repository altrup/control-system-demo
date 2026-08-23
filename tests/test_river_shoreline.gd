extends GutTest

const SHORELINE_PATH := "res://world/river_shoreline.gd"
const WorldGenerator := preload("res://world/world_generator.gd")
const SOURCE_HALF_WIDTH := 0.05


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


func test_stream_sources_taper_to_the_centerline() -> void:
	var generator := WorldGenerator.new(481516)
	var branches: Array = load(SHORELINE_PATH).new().build(
		generator.stream_branches(),
		Callable(generator, "height_at")
	)
	var source_count := 0
	for branch in branches:
		var source = branch.points[0]
		if source.bed_half_width > SOURCE_HALF_WIDTH:
			continue
		source_count += 1
		assert_eq(source.left_edge, source.center)
		assert_eq(source.right_edge, source.center)

	assert_gt(source_count, 0)


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
			if point.bed_half_width <= SOURCE_HALF_WIDTH:
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


func test_demo_seed_does_not_flood_a_broad_basin() -> void:
	var generator := WorldGenerator.new(481516)
	var branches: Array = load(SHORELINE_PATH).new().build(
		generator.stream_branches(),
		Callable(generator, "height_at")
	)
	var widest_distance := 0.0
	for branch in branches:
		for point in branch.points:
			if not _is_inside_world(point.center, 6.0):
				continue
			widest_distance = maxf(
				widest_distance,
				maxf(
					_point_distance(point.center, point.left_shore),
					_point_distance(point.center, point.right_shore)
				)
			)

	assert_lt(widest_distance, 30.0)


func _is_inside_world(position: Vector3, margin: float) -> bool:
	return (
		position.x >= margin
		and position.z >= margin
		and position.x <= WorldGenerator.REGION_SIZE - 1 - margin
		and position.z <= WorldGenerator.REGION_SIZE - 1 - margin
	)


func _point_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))
