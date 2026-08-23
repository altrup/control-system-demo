extends GutTest

const GENERATOR_PATH := "res://world/world_generator.gd"


func test_seed_repeats_generated_world() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var first: RefCounted = generator_script.new(103)
	var repeated: RefCounted = generator_script.new(103)
	var changed: RefCounted = generator_script.new(481516)
	var sample := Vector2(25.5, 73.25)

	assert_eq(first.call("height_at", sample), repeated.call("height_at", sample))
	assert_ne(first.call("height_at", sample), changed.call("height_at", sample))
	if not first.has_method("stream_segments"):
		fail_test("Natural stream segments are available")
		return
	assert_eq(_stream_signature(first), _stream_signature(repeated))
	assert_ne(_stream_signature(first), _stream_signature(changed))
	assert_eq(first.call("tree_positions"), repeated.call("tree_positions"))
	assert_ne(first.call("tree_positions"), changed.call("tree_positions"))


func test_terrain_has_large_scale_relief() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516)
	var lowest := INF
	var highest := -INF
	for x in range(0, 128, 4):
		for z in range(0, 128, 4):
			var height := generator.call("height_at", Vector2(x, z)) as float
			lowest = minf(lowest, height)
			highest = maxf(highest, height)

	assert_gte(highest - lowest, 8.0)


func test_hydrology_only_erodes_the_initial_terrain() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516)
	var largest_raise := 0.0
	for x in range(0, 128, 4):
		for z in range(0, 128, 4):
			var position := Vector2(x, z)
			var generated_height := generator.call("height_at", position) as float
			var initial_height := generator.call("_base_height_at", position) as float
			largest_raise = maxf(largest_raise, generated_height - initial_height)

	assert_lte(largest_raise, 0.01)


func test_routing_does_not_carve_dry_terrain() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516)
	var segments: Array = generator.call("stream_segments")
	var deepest_dry_cut := 0.0
	for x in range(0, 128, 4):
		for z in range(0, 128, 4):
			var position := Vector2(x, z)
			if _distance_to_stream(position, segments) <= 8.0:
				continue
			var generated_height := generator.call("height_at", position) as float
			var initial_height := generator.call("_base_height_at", position) as float
			deepest_dry_cut = maxf(deepest_dry_cut, initial_height - generated_height)

	assert_lte(deepest_dry_cut, 0.01)


func test_natural_drainage_keeps_boundary_crossing_channels() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(103)
	assert_true(generator.has_method("stream_segments"))
	if not generator.has_method("stream_segments"):
		return
	var segments: Array = generator.call("stream_segments")
	assert_gte(segments.size(), 20)
	var branches: Array = generator.call("stream_branches")
	for branch in branches:
		assert_false(_is_inside_world(branch.points[0].position))
		assert_false(_is_inside_world(branch.points[-1].position))


func test_stream_network_forms_smooth_branches_that_reach_the_boundary() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(103)
	assert_true(generator.has_method("stream_branches"))
	if not generator.has_method("stream_branches"):
		return
	var branches: Array = generator.call("stream_branches")
	var segments: Array = generator.call("stream_segments")
	var reached_boundary := false
	var longest_branch := 0
	var sharpest_turn := 1.0
	for branch in branches:
		longest_branch = maxi(longest_branch, branch.points.size())
		var first: Vector3 = branch.points[0].position
		var last: Vector3 = branch.points[-1].position
		reached_boundary = reached_boundary or _is_near_world_boundary(first)
		reached_boundary = reached_boundary or _is_near_world_boundary(last)
		for index in range(1, branch.points.size() - 1):
			var previous: Vector3 = branch.points[index - 1].position
			var current: Vector3 = branch.points[index].position
			var following: Vector3 = branch.points[index + 1].position
			var incoming_direction := Vector2(current.x - previous.x, current.z - previous.z).normalized()
			var outgoing_direction := Vector2(following.x - current.x, following.z - current.z).normalized()
			sharpest_turn = minf(sharpest_turn, incoming_direction.dot(outgoing_direction))

	assert_gt(branches.size(), 0)
	assert_lt(branches.size() * 4, segments.size())
	assert_gt(longest_branch, 20)
	assert_gt(sharpest_turn, 0.7)
	assert_true(reached_boundary)


func test_flow_erosion_makes_larger_channels_wider_and_deeper() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(103)
	if not generator.has_method("stream_segments"):
		fail_test("Natural stream segments are available")
		return
	var segments: Array = generator.call("stream_segments")
	assert_false(segments.is_empty())
	if segments.is_empty():
		return
	var playable_segments := segments.filter(
		func(segment) -> bool: return _is_inside_world(segment.start)
	)
	assert_false(playable_segments.is_empty())
	if playable_segments.is_empty():
		return
	var narrow = playable_segments[0]
	var wide = playable_segments[0]
	for segment in playable_segments:
		if segment.start_half_width < narrow.start_half_width:
			narrow = segment
		if segment.start_half_width > wide.start_half_width:
			wide = segment

	assert_gt(wide.start_half_width, narrow.start_half_width)
	assert_gt(wide.start_depth, narrow.start_depth)
	assert_lte(
		generator.call("height_at", Vector2(wide.start.x, wide.start.z)),
		wide.start.y - wide.start_depth + 0.01
	)


func test_player_spawns_near_but_not_inside_a_stream() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(103)
	if not generator.has_method("stream_segments"):
		fail_test("Natural stream segments are available")
		return
	var segments: Array = generator.call("stream_segments")
	var spawn := generator.call("player_spawn") as Vector2

	assert_gte(_distance_to_stream(spawn, segments), 10.0)
	assert_lte(_distance_to_stream(spawn, segments), 18.0)


func test_trees_respect_world_clearances() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(103)
	if not generator.has_method("stream_segments"):
		fail_test("Natural stream segments are available")
		return
	var positions := generator.call("tree_positions") as Array
	var segments: Array = generator.call("stream_segments")
	var spawn := generator.call("player_spawn") as Vector2

	assert_eq(positions.size(), 112)
	for index in positions.size():
		var position := positions[index] as Vector2
		assert_gte(position.x, 4.0)
		assert_lte(position.x, 124.0)
		assert_gte(position.y, 4.0)
		assert_lte(position.y, 124.0)
		assert_gte(_distance_to_stream(position, segments), 7.0)
		assert_gte(position.distance_to(spawn), 6.0)
		for other_index in range(index + 1, positions.size()):
			assert_gte(position.distance_to(positions[other_index]), 3.5)


func _distance_to_stream(position: Vector2, segments: Array) -> float:
	var distance := INF
	for segment in segments:
		var start := Vector2(segment.start.x, segment.start.z)
		var end := Vector2(segment.end.x, segment.end.z)
		var closest := Geometry2D.get_closest_point_to_segment(position, start, end)
		distance = minf(distance, position.distance_to(closest))
	return distance


func _stream_signature(generator: RefCounted) -> PackedFloat32Array:
	var signature := PackedFloat32Array()
	for segment in generator.call("stream_segments") as Array:
		signature.append_array([
			segment.start.x,
			segment.start.y,
			segment.start.z,
			segment.start_half_width,
			segment.start_depth,
			segment.end.x,
			segment.end.y,
			segment.end.z,
			segment.end_half_width,
			segment.end_depth,
		])
	return signature


func _is_near_world_boundary(position: Vector3) -> bool:
	return position.x <= 1.0 or position.z <= 1.0 or position.x >= 126.0 or position.z >= 126.0


func _is_inside_world(position: Vector3) -> bool:
	return position.x >= 0.0 and position.z >= 0.0 and position.x < 128.0 and position.z < 128.0
