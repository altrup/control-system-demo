extends GutTest

const NETWORK_PATH := "res://world/river_network.gd"


func test_keeps_only_boundary_crossing_channels() -> void:
	assert_true(ResourceLoader.exists(NETWORK_PATH))
	if not ResourceLoader.exists(NETWORK_PATH):
		return
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, 2.0)
	var branches: Array = network.call("build", _east_facing_slope())

	assert_false(branches.is_empty())
	for branch in branches:
		assert_lt(branch.points[0].position.x, 0.0)
		assert_gte(branch.points[-1].position.x, 4.0)


func test_channel_dimensions_grow_with_accumulated_area() -> void:
	assert_true(ResourceLoader.exists(NETWORK_PATH))
	if not ResourceLoader.exists(NETWORK_PATH):
		return
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 2, 2.0)
	var small := network.call("dimensions_for_area", 2.0) as Vector2
	var large := network.call("dimensions_for_area", 128.0) as Vector2

	assert_gt(large.x, small.x)
	assert_gt(large.y, small.y)
	assert_lte(large.x, 6.0)
	assert_lte(large.y, 1.2)


func test_water_never_rises_downstream() -> void:
	var network_script := load(NETWORK_PATH) as GDScript
	var network: RefCounted = network_script.new(4, 3, 2.0)
	var branches: Array = network.call("build", _east_facing_slope())

	for branch in branches:
		for index in range(1, branch.points.size()):
			assert_lte(branch.points[index].position.y, branch.points[index - 1].position.y)
			assert_gt(branch.points[index].depth, 0.0)
			assert_gte(branch.points[index].bank_falloff, 2.0)


func _east_facing_slope() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(100)
	for z in 10:
		for x in 10:
			heights[z * 10 + x] = 10.0 - x + z * 0.001
	return heights
