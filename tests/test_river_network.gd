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
	var headwater := network.call("dimensions_for_area", 4096.0) as Vector3
	var downstream := network.call("dimensions_for_area", 16384.0) as Vector3

	assert_eq(headwater.x, 3.0)
	assert_almost_eq(headwater.y, 0.8, 0.0001)
	assert_almost_eq(downstream.x, 5.5982, 0.0001)
	assert_almost_eq(downstream.y, 1.2996, 0.0001)


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
			assert_gte(branch.points[index].bank_falloff, 2.0)


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


func _east_facing_slope() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(100)
	for z in 10:
		for x in 10:
			heights[z * 10 + x] = 10.0 - x + z * 0.001
	return heights


func _parameters(threshold: float) -> RiverParameters:
	var parameters := RiverParameters.new()
	parameters.channel_threshold = threshold
	return parameters
