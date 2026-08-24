extends GutTest

const RiverNetwork := preload("res://world/river_network.gd")
const CARVER_PATH := "res://world/river_carver.gd"


func test_carves_bed_and_banks_without_changing_dry_terrain() -> void:
	assert_true(ResourceLoader.exists(CARVER_PATH))
	if not ResourceLoader.exists(CARVER_PATH):
		return
	var carver: RefCounted = (load(CARVER_PATH) as GDScript).new(8)
	var branches: Array[RiverNetwork.ChannelBranch] = [_horizontal_branch()]
	var carved := carver.call("carve", _flat_terrain(), branches) as PackedFloat32Array

	assert_lte(carved[4 * 8 + 3], 8.75)
	assert_lt(carved[5 * 8 + 3], 10.0)
	assert_eq(carved[0 * 8 + 3], 10.0)


func test_carved_bank_meets_water_at_the_mesh_edge() -> void:
	var carver: RefCounted = (load(CARVER_PATH) as GDScript).new(8)
	var branches: Array[RiverNetwork.ChannelBranch] = [_horizontal_branch()]
	var carved := carver.call("carve", _flat_terrain(), branches) as PackedFloat32Array

	assert_almost_eq(carved[3 * 8 + 3], 8.8, 0.001)
	assert_gt(carved[2 * 8 + 3], 8.8)


func test_carved_channel_keeps_a_full_depth_riverbed() -> void:
	var carver: RefCounted = (load(CARVER_PATH) as GDScript).new(8)
	var branches: Array[RiverNetwork.ChannelBranch] = [RiverNetwork.ChannelBranch.new([
		RiverNetwork.ChannelPoint.new(
			Vector3(-3.0, 9.0, 0.0), 4096.0, Vector3(4.0, 1.0, 2.0)
		),
		RiverNetwork.ChannelPoint.new(
			Vector3(2.0, 9.0, 0.0), 4096.0, Vector3(4.0, 1.0, 2.0)
		),
	])]
	var carved := carver.call("carve", _flat_terrain(), branches) as PackedFloat32Array

	assert_almost_eq(carved[4 * 8 + 3], 8.0, 0.001)
	assert_almost_eq(carved[3 * 8 + 3], 8.0, 0.001)
	assert_almost_eq(carved[2 * 8 + 3], 9.0, 0.001)


func test_confluence_uses_union_of_branch_corridors() -> void:
	assert_true(ResourceLoader.exists(CARVER_PATH))
	if not ResourceLoader.exists(CARVER_PATH):
		return
	var carver: RefCounted = (load(CARVER_PATH) as GDScript).new(8)
	var tributary := RiverNetwork.ChannelBranch.new([
		_point(Vector3(-1.0, 9.0, -3.0)),
		_point(Vector3(-1.0, 8.75, 0.0)),
	])
	var branches: Array[RiverNetwork.ChannelBranch] = [_horizontal_branch(), tributary]
	var carved := carver.call(
		"carve",
		_flat_terrain(),
		branches
	) as PackedFloat32Array

	assert_lt(carved[2 * 8 + 3], 10.0)
	assert_lt(carved[4 * 8 + 3], 10.0)


func test_overlapping_sections_do_not_compound_bank_erosion() -> void:
	var carver: RefCounted = (load(CARVER_PATH) as GDScript).new(8)
	var branch := _horizontal_branch()
	var once_branches: Array[RiverNetwork.ChannelBranch] = [branch]
	var repeated_branches: Array[RiverNetwork.ChannelBranch] = [branch, branch]
	var once := carver.call(
		"carve", _flat_terrain(), once_branches
	) as PackedFloat32Array
	var repeated := carver.call(
		"carve", _flat_terrain(), repeated_branches
	) as PackedFloat32Array

	assert_eq(repeated, once)


func _flat_terrain() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(64)
	heights.fill(10.0)
	return heights


func _horizontal_branch() -> RiverNetwork.ChannelBranch:
	return RiverNetwork.ChannelBranch.new([
		_point(Vector3(-3.0, 9.0, 0.0)),
		_point(Vector3(2.0, 8.5, 0.0)),
	])


func _point(position: Vector3) -> RiverNetwork.ChannelPoint:
	return RiverNetwork.ChannelPoint.new(position, 4096.0, Vector3(2.0, 0.5, 2.0))
