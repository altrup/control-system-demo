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


func test_confluence_uses_union_of_branch_corridors() -> void:
	assert_true(ResourceLoader.exists(CARVER_PATH))
	if not ResourceLoader.exists(CARVER_PATH):
		return
	var carver: RefCounted = (load(CARVER_PATH) as GDScript).new(8)
	var tributary := RiverNetwork.ChannelBranch.new([
		_point(Vector3(3.0, 9.0, 1.0)),
		_point(Vector3(3.0, 8.75, 4.0)),
	])
	var branches: Array[RiverNetwork.ChannelBranch] = [_horizontal_branch(), tributary]
	var carved := carver.call(
		"carve",
		_flat_terrain(),
		branches
	) as PackedFloat32Array

	assert_lt(carved[2 * 8 + 3], 10.0)
	assert_lt(carved[4 * 8 + 3], 10.0)


func _flat_terrain() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(64)
	heights.fill(10.0)
	return heights


func _horizontal_branch() -> RiverNetwork.ChannelBranch:
	return RiverNetwork.ChannelBranch.new([
		_point(Vector3(1.0, 9.0, 4.0)),
		_point(Vector3(6.0, 8.5, 4.0)),
	])


func _point(position: Vector3) -> RiverNetwork.ChannelPoint:
	return RiverNetwork.ChannelPoint.new(position, 4096.0, Vector3(2.0, 0.5, 2.0))
