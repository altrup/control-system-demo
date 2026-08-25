extends GutTest

const NETWORK_PATH := "res://world/river_network.gd"
const RiverNetwork := preload("res://world/river_network.gd")
const RiverParameters := preload("res://world/river_parameters.gd")


func test_keeps_only_boundary_crossing_channels() -> void:
	assert_true(ResourceLoader.exists(NETWORK_PATH))
	if not ResourceLoader.exists(NETWORK_PATH):
		return
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, _parameters(2.0))
	var branches: Array = network.call("build", _east_facing_slope())

	assert_false(branches.is_empty())
	for branch in branches:
		assert_lt(branch.points[0].position.x, -2.0)
		assert_gte(branch.points[-1].position.x, 2.0)


func test_full_domain_keeps_channels_that_start_inside_the_crop() -> void:
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, _parameters(5.0))
	assert_true(network.has_method("build_full_domain"))
	if not network.has_method("build_full_domain"):
		return

	var cropped: Array = network.call("build", _east_facing_slope())
	var full: Array = network.call("build_full_domain", _east_facing_slope())

	assert_true(cropped.is_empty())
	assert_false(full.is_empty())
	for branch in full:
		assert_gte(branch.points[0].position.x, -2.0)
		assert_lt(branch.points[0].position.x, 2.0)
		assert_gt(branch.points[-1].position.x, 5.0)


func test_cropped_channels_use_full_network_geometry() -> void:
	var network: RefCounted = (load(NETWORK_PATH) as GDScript).new(
		4, 3, _parameters(2.0)
	)
	var cropped: Array = network.call("build", _east_facing_slope())
	var full: Array = network.call("build_full_domain", _east_facing_slope())

	assert_false(cropped.is_empty())
	for branch in cropped:
		for point in branch.points:
			if _is_inside_crop(point.position):
				assert_true(_contains_point(full, point.position))


func test_channel_dimensions_grow_with_accumulated_area() -> void:
	assert_true(ResourceLoader.exists(NETWORK_PATH))
	if not ResourceLoader.exists(NETWORK_PATH):
		return
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 2, _parameters(2.0))
	var small := network.call("dimensions_for_area", 2.0) as Vector3
	var large := network.call("dimensions_for_area", 128.0) as Vector3

	assert_gt(large.x, small.x)
	assert_gt(large.y, small.y)
	assert_lte(large.x, 8.0)
	assert_lte(large.y, 1.8)


func test_channel_dimensions_have_visible_downstream_growth() -> void:
	var parameters := RiverParameters.new()
	var network: RefCounted = (load(NETWORK_PATH) as GDScript).new(4, 2, parameters)
	var headwater := network.call("dimensions_for_area", 65536.0) as Vector3
	var downstream := network.call("dimensions_for_area", 262144.0) as Vector3

	assert_eq(headwater.x, 3.0)
	assert_almost_eq(headwater.y, 0.8, 0.0001)
	assert_almost_eq(downstream.x, 5.5982, 0.0001)
	assert_almost_eq(downstream.y, 1.2996, 0.0001)


func test_small_stream_dimensions_grow_into_the_reference_river_profile() -> void:
	var parameters := RiverParameters.new()
	var network: RefCounted = (load(NETWORK_PATH) as GDScript).new(4, 2, parameters)
	var onset := network.call("dimensions_for_area", parameters.stream_threshold) as Vector3
	var stream := network.call(
		"dimensions_for_area",
		(parameters.stream_threshold + parameters.channel_threshold) * 0.5
	) as Vector3
	var river := network.call("dimensions_for_area", parameters.channel_threshold) as Vector3

	assert_eq(onset, Vector3.ZERO)
	assert_gt(stream.x, 0.0)
	assert_gt(stream.y, 0.0)
	assert_lt(stream.x, river.x)
	assert_lt(stream.y, river.y)


func test_flow_accumulation_uses_physical_cell_area() -> void:
	var network: RefCounted = (load(NETWORK_PATH) as GDScript).new(
		16, 12, _parameters(16.0), 4.0
	)
	var downstream := PackedInt32Array([1, -1])
	var descending_cells: Array[int] = [0, 1]
	var accumulation := network.call(
		"_flow_accumulation", downstream, descending_cells
	) as PackedFloat32Array

	assert_eq(accumulation, PackedFloat32Array([16.0, 32.0]))


func test_cell_positions_use_hydrology_sample_spacing() -> void:
	var network: RefCounted = (load(NETWORK_PATH) as GDScript).new(
		16, 12, _parameters(16.0), 4.0
	)

	assert_eq(network.call("_cell_position", 0), Vector2(-20.0, -20.0))
	assert_eq(network.call("_cell_position", 1), Vector2(-16.0, -20.0))


func test_curved_channel_uses_fine_terrain_samples() -> void:
	var network: RefCounted = (load(NETWORK_PATH) as GDScript).new(
		16,
		12,
		_parameters(16.0),
		4.0,
		Callable(self, "_trough_height")
	)
	var dimensions := Vector3(2.0, 0.5, 2.0)
	var points: Array[RiverNetwork.ChannelPoint] = [
		RiverNetwork.ChannelPoint.new(Vector3(-4.0, 1.0, 0.0), 16.0, dimensions),
		RiverNetwork.ChannelPoint.new(Vector3.ZERO, 32.0, dimensions),
		RiverNetwork.ChannelPoint.new(Vector3(4.0, -1.0, 0.0), 48.0, dimensions),
	]
	var curved := network.call("_curve_branch", points) as Array
	var center = curved[0]
	for point in curved:
		if absf(point.position.x) < absf(center.position.x):
			center = point

	assert_gt(center.position.z, 1.0)


func test_grade_limit_does_not_include_intended_channel_depth() -> void:
	var parameters := _parameters(2.0)
	parameters.minimum_depth = 3.0
	parameters.maximum_depth = 3.0
	parameters.maximum_centerline_cut = 0.1
	var network: RefCounted = (load(NETWORK_PATH) as GDScript).new(4, 3, parameters)
	var branches: Array = network.call("build", _east_facing_slope())

	assert_false(branches.is_empty())


func test_water_never_rises_downstream() -> void:
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, _parameters(2.0))
	var branches: Array = network.call("build", _east_facing_slope())

	for branch in branches:
		for index in range(1, branch.points.size()):
			assert_lte(branch.points[index].position.y, branch.points[index - 1].position.y)
			assert_gt(branch.points[index].depth, 0.0)
			assert_gt(branch.points[index].bank_falloff, 0.0)


func test_water_grade_has_no_abrupt_drops() -> void:
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, _parameters(2.0))
	var branches: Array = network.call("build", _east_facing_slope())

	for branch in branches:
		for index in range(1, branch.points.size()):
			var upstream: Vector3 = branch.points[index - 1].position
			var downstream: Vector3 = branch.points[index].position
			var horizontal_distance := Vector2(
				downstream.x - upstream.x,
				downstream.z - upstream.z
			).length()
			assert_lte((upstream.y - downstream.y) / horizontal_distance, 0.04001)


func test_water_keeps_freeboard_below_outer_banks() -> void:
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, _parameters(2.0))
	var points: Array[RiverNetwork.ChannelPoint] = [
		RiverNetwork.ChannelPoint.new(
			Vector3(-1.0, 6.0, 0.0), 2.0, Vector3(2.0, 0.5, 2.0)
		),
		RiverNetwork.ChannelPoint.new(
			Vector3(1.0, 6.0, 0.0), 2.0, Vector3(2.0, 0.5, 2.0)
		),
	]
	var branches: Array[RiverNetwork.ChannelBranch] = [RiverNetwork.ChannelBranch.new(points)]
	var flat_heights := PackedFloat32Array()
	flat_heights.resize(100)
	flat_heights.fill(5.0)

	network.call("_constrain_water_to_banks", branches, flat_heights)

	for point in points:
		assert_lte(point.position.y, 4.85)


func test_valley_erosion_only_lowers_high_flow_corridors() -> void:
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, _parameters(2.0))
	assert_true(network.has_method("erode_valleys"))
	if not network.has_method("erode_valleys"):
		return
	var initial := _east_facing_slope()
	var eroded := network.call("erode_valleys", initial) as PackedFloat32Array
	var largest_cut := 0.0
	var largest_raise := 0.0
	for cell in initial.size():
		largest_cut = maxf(largest_cut, initial[cell] - eroded[cell])
		largest_raise = maxf(largest_raise, eroded[cell] - initial[cell])

	assert_gt(largest_cut, 0.25)
	assert_lte(largest_raise, 0.0)
	assert_eq(eroded[0], initial[0])


func test_valley_erosion_fades_in_before_the_visible_channel() -> void:
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, _parameters(4.0))
	assert_true(network.has_method("valley_dimensions_for_area"))
	if not network.has_method("valley_dimensions_for_area"):
		return
	var early := network.call("valley_dimensions_for_area", 2.0) as Vector2
	var visible := network.call("valley_dimensions_for_area", 4.0) as Vector2

	assert_gt(early.x, 0.0)
	assert_gt(early.y, 0.0)
	assert_lt(early.x, visible.x)
	assert_lt(early.y, visible.y)


func _east_facing_slope() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(100)
	for z in 10:
		for x in 10:
			heights[z * 10 + x] = 10.0 - x + z * 0.001
	return heights


func _trough_height(position: Vector2) -> float:
	return absf(position.y - 2.0)


func _parameters(threshold: float) -> RiverParameters:
	var parameters := RiverParameters.new()
	parameters.stream_threshold = threshold
	parameters.channel_threshold = threshold
	return parameters


func _contains_point(branches: Array, position: Vector3) -> bool:
	for branch in branches:
		for point in branch.points:
			if point.position.is_equal_approx(position):
				return true
	return false


func _is_inside_crop(position: Vector3) -> bool:
	return position.x >= -2.0 and position.z >= -2.0 and position.x < 2.0 and position.z < 2.0
