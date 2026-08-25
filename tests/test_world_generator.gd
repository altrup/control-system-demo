extends GutTest

const GENERATOR_PATH := "res://world/world_generator.gd"
const TERRAIN_ELEVATION_PATH := "res://world/terrain_elevation.gd"


func test_seed_repeats_generated_world() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var first: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	var repeated: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	var changed: RefCounted = generator_script.new(481516)
	var sample := Vector2(-38.5, 9.25)

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
	for x in range(-64, 64, 4):
		for z in range(-64, 64, 4):
			var height := generator.call("height_at", Vector2(x, z)) as float
			lowest = minf(lowest, height)
			highest = maxf(highest, height)

	assert_gte(highest - lowest, 6.0)


func test_landforms_include_mountain_relief_and_stable_ocean_areas() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var normal: RefCounted = generator_script.new(481516)
	var full_domain: RefCounted = generator_script.new(481516, null, true)
	assert_true(normal.has_method("is_ocean"))
	if not normal.has_method("is_ocean"):
		return
	var lowest := INF
	var highest := -INF
	var ocean_samples := 0
	var land_samples := 0
	for x in range(-1024, 1024, 64):
		for z in range(-1024, 1024, 64):
			var position := Vector2(x, z)
			var height := normal.call("_base_height_at", position) as float
			lowest = minf(lowest, height)
			highest = maxf(highest, height)
			if normal.call("is_ocean", position):
				ocean_samples += 1
			else:
				land_samples += 1
			assert_eq(
				normal.call("is_ocean", position),
				full_domain.call("is_ocean", position)
			)

	assert_gt(ocean_samples, 0)
	assert_gt(land_samples, 0)
	assert_gte(highest - lowest, 35.0)


func test_lowered_sea_exposes_shallow_coastal_land() -> void:
	var elevation_script := load(TERRAIN_ELEVATION_PATH) as GDScript
	var elevation: RefCounted = elevation_script.new(22)
	var shallow_coast := Vector2.INF
	var deep_ocean := Vector2.INF
	for x in range(-1024, 1024, 16):
		for z in range(-1024, 1024, 16):
			var position := Vector2(x, z)
			var height := elevation.call("height_at", position) as float
			if shallow_coast == Vector2.INF and height > -4.5 and height < -0.5:
				shallow_coast = position
			if deep_ocean == Vector2.INF and height < -5.5:
				deep_ocean = position

	assert_ne(shallow_coast, Vector2.INF)
	assert_ne(deep_ocean, Vector2.INF)
	if shallow_coast != Vector2.INF:
		assert_false(elevation.call("is_ocean", shallow_coast))
	if deep_ocean != Vector2.INF:
		assert_true(elevation.call("is_ocean", deep_ocean))


func test_ocean_surface_includes_submerged_river_mouths() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(
		generator_script.DEFAULT_SEED, null, false, 0.0
	)
	assert_true(generator.has_method("has_ocean_surface_at"))
	if not generator.has_method("has_ocean_surface_at"):
		return
	var found_mouth := false
	for segment in generator.call("stream_segments"):
		var midpoint: Vector3 = (segment.start + segment.end) * 0.5
		var position := Vector2(midpoint.x, midpoint.z)
		var terrain_min := generator.call("terrain_min") as float
		var terrain_max := terrain_min + (
			generator.call("terrain_sample_size") as int - 1
		) * 0.5
		var inside := (
			position.x >= terrain_min
			and position.y >= terrain_min
			and position.x < terrain_max
			and position.y < terrain_max
		)
		if (
			inside
			and midpoint.y <= generator.call("sea_level")
			and generator.call("height_at", position) < generator.call("sea_level")
			and not generator.call("is_ocean", position)
		):
			found_mouth = true
			assert_true(generator.call("has_ocean_surface_at", position))
			break
	assert_true(found_mouth)


func test_hydrology_only_erodes_the_initial_terrain() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516)
	var largest_raise := 0.0
	for x in range(-64, 64, 4):
		for z in range(-64, 64, 4):
			var position := Vector2(x, z)
			var generated_height := generator.call("height_at", position) as float
			var initial_height := generator.call("_base_height_at", position) as float
			largest_raise = maxf(largest_raise, generated_height - initial_height)

	assert_lte(largest_raise, 0.01)


func test_valley_erosion_reaches_beyond_the_final_riverbed() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516)
	var segments: Array = generator.call("stream_segments")
	var broadest_cut := 0.0
	for x in range(-128, 128, 2):
		for z in range(-128, 128, 2):
			var position := Vector2(x, z)
			if _distance_to_stream(position, segments) <= 8.0:
				continue
			var generated_height := generator.call("height_at", position) as float
			var initial_height := generator.call("_base_height_at", position) as float
			broadest_cut = maxf(broadest_cut, initial_height - generated_height)

	assert_gt(broadest_cut, 0.2)


func test_natural_drainage_keeps_boundary_crossing_channels() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	assert_true(generator.has_method("stream_segments"))
	if not generator.has_method("stream_segments"):
		return
	var segments: Array = generator.call("stream_segments")
	assert_gte(segments.size(), 20)
	var branches: Array = generator.call("stream_branches")
	var has_entry := false
	var has_exit := false
	for branch in branches:
		has_entry = has_entry or not _is_inside_world(branch.points[0].position)
		has_exit = has_exit or not _is_inside_world(branch.points[-1].position)
	assert_true(has_entry)
	assert_true(has_exit)


func test_boundary_channels_keep_their_full_profile_outside_the_crop() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	var branches: Array = generator.call("stream_branches")

	for branch in branches:
		var first = branch.points[0]
		var last = branch.points[-1]
		if not _is_inside_world(first.position):
			assert_gte(
				_distance_outside_world(first.position),
				first.half_width + first.bank_falloff
			)
		if not _is_inside_world(last.position):
			assert_gte(
				_distance_outside_world(last.position),
				last.half_width + last.bank_falloff
			)


func test_water_surface_edges_are_supported_by_terrain_or_water() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	var branches: Array = generator.call("stream_branches")
	var segments: Array = generator.call("stream_segments")

	for branch in branches:
		for index in branch.points.size():
			var point = branch.points[index]
			var previous: Vector3 = branch.points[maxi(0, index - 1)].position
			var following: Vector3 = branch.points[mini(branch.points.size() - 1, index + 1)].position
			var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
			var edge_direction: Vector2 = (
				Vector2(-tangent.y, tangent.x)
				* (point.half_width + 0.6)
			)
			for edge in [
				Vector2(point.position.x, point.position.z) + edge_direction,
				Vector2(point.position.x, point.position.z) - edge_direction,
			]:
				if not _is_inside_world(Vector3(edge.x, 0.0, edge.y)):
					continue
				assert_true(
					generator.call("height_at", edge) >= point.position.y - 0.03
					or _water_covers(edge, segments),
					"Unsupported shoreline at %s: terrain %.3f, water %.3f" % [
						edge,
						generator.call("height_at", edge),
						point.position.y,
					]
				)


func test_stream_network_forms_smooth_branches_that_reach_the_boundary() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
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


func test_rendered_channel_paths_are_smooth_and_subcell_sampled() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	var sharpest_turn := 1.0
	var longest_straight_run := 0.0
	var longest_interior_segment := 0.0
	for branch in generator.call("stream_branches") as Array:
		var straight_run := 0.0
		for index in range(1, branch.points.size() - 1):
			var previous: Vector3 = branch.points[index - 1].position
			var current: Vector3 = branch.points[index].position
			var following: Vector3 = branch.points[index + 1].position
			var incoming := Vector2(current.x - previous.x, current.z - previous.z)
			var outgoing := Vector2(following.x - current.x, following.z - current.z)
			var alignment := incoming.normalized().dot(outgoing.normalized())
			sharpest_turn = minf(sharpest_turn, alignment)
			if alignment > 0.9999:
				straight_run += outgoing.length()
			else:
				longest_straight_run = maxf(longest_straight_run, straight_run)
				straight_run = 0.0
			if _is_inside_world(current) and _is_inside_world(following):
				longest_interior_segment = maxf(longest_interior_segment, outgoing.length())
		longest_straight_run = maxf(longest_straight_run, straight_run)

	assert_gt(sharpest_turn, 0.85)
	assert_lt(longest_straight_run, 64.0)
	assert_lte(longest_interior_segment, 0.75)


func test_flow_erosion_makes_larger_channels_wider_and_deeper() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	if not generator.has_method("stream_segments"):
		fail_test("Natural stream segments are available")
		return
	var segments: Array = generator.call("stream_segments")
	assert_false(segments.is_empty())
	if segments.is_empty():
		return
	var playable_segments := segments.filter(
		func(segment) -> bool: return _is_inside_terrain_samples(segment.start)
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
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	if not generator.has_method("stream_segments"):
		fail_test("Natural stream segments are available")
		return
	var segments: Array = generator.call("stream_segments")
	var spawn := generator.call("player_spawn") as Vector2

	assert_gte(_distance_to_stream(spawn, segments), 10.0)
	assert_lte(_distance_to_stream(spawn, segments), 18.0)
	assert_false(generator.call("is_ocean", spawn))


func test_trees_respect_world_clearances() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)
	if not generator.has_method("stream_segments"):
		fail_test("Natural stream segments are available")
		return
	var positions := generator.call("tree_positions") as Array
	var segments: Array = generator.call("stream_segments")
	var spawn := generator.call("player_spawn") as Vector2

	assert_eq(positions.size(), 448)
	for index in positions.size():
		var position := positions[index] as Vector2
		assert_gte(position.x, -124.0)
		assert_lte(position.x, 124.0)
		assert_gte(position.y, -124.0)
		assert_lte(position.y, 124.0)
		assert_false(generator.call("is_ocean", position))
		assert_gte(_distance_to_stream(position, segments), 7.0)
		assert_gte(position.distance_to(spawn), 6.0)
		for other_index in range(index + 1, positions.size()):
			assert_gte(position.distance_to(positions[other_index]), 3.5)


func test_tree_count_scales_with_visible_area() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(generator_script.DEFAULT_SEED)

	assert_eq(generator.call("tree_count_for_region_size", 128), 112)
	assert_eq(generator.call("tree_count_for_region_size", 256), 448)


func _distance_to_stream(position: Vector2, segments: Array) -> float:
	var distance := INF
	for segment in segments:
		var start := Vector2(segment.start.x, segment.start.z)
		var end := Vector2(segment.end.x, segment.end.z)
		var closest := Geometry2D.get_closest_point_to_segment(position, start, end)
		distance = minf(distance, position.distance_to(closest))
	return distance


func _water_covers(position: Vector2, segments: Array) -> bool:
	for segment in segments:
		var start := Vector2(segment.start.x, segment.start.z)
		var end := Vector2(segment.end.x, segment.end.z)
		var delta := end - start
		var progress := clampf((position - start).dot(delta) / delta.length_squared(), 0.0, 1.0)
		var closest := start + delta * progress
		var half_width := lerpf(
			segment.start_half_width,
			segment.end_half_width,
			progress
		) + 0.74
		if position.distance_to(closest) <= half_width:
			return true
	return false


func _distance_outside_world(position: Vector3) -> float:
	return maxf(
		maxf(-128.0 - position.x, position.x - 128.0),
		maxf(-128.0 - position.z, position.z - 128.0)
	)


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
	return position.x <= -127.0 or position.z <= -127.0 or position.x >= 126.0 or position.z >= 126.0


func _is_inside_world(position: Vector3) -> bool:
	return position.x >= -128.0 and position.z >= -128.0 and position.x < 128.0 and position.z < 128.0


func _is_inside_terrain_samples(position: Vector3) -> bool:
	return (
		position.x >= -128.0
		and position.z >= -128.0
		and position.x <= 127.5
		and position.z <= 127.5
	)
