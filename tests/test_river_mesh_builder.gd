extends GutTest

const BUILDER_PATH := "res://world/river_mesh_builder.gd"
const RiverNetwork := preload("res://world/river_network.gd")


func test_builds_profile_widths_and_clips_to_world_bounds() -> void:
	var branches: Array[RiverNetwork.ChannelBranch] = [RiverNetwork.ChannelBranch.new([
		_point(Vector3(-1.0, 2.0, 4.0)),
		_point(Vector3(4.0, 1.5, 4.0)),
		_point(Vector3(9.0, 1.0, 4.0)),
	])]
	var mesh := load(BUILDER_PATH).new(8.0).build(branches) as ArrayMesh

	assert_eq(mesh.get_surface_count(), 1)
	var arrays := mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	assert_false(indices.is_empty())
	for vertex in vertices:
		assert_gte(vertex.x, 0.0)
		assert_lte(vertex.x, 8.0)
		assert_gte(vertex.z, 0.0)
		assert_lte(vertex.z, 8.0)
	assert_true(vertices.has(Vector3(4.0, 1.52, 4.0)))
	assert_true(vertices.has(Vector3(4.0, 1.52, 3.0)))
	assert_true(vertices.has(Vector3(4.0, 1.52, 5.0)))


func test_fills_confluence_between_three_branch_ribbons() -> void:
	var junction := _point(Vector3(4.0, 1.0, 4.0))
	var branches: Array[RiverNetwork.ChannelBranch] = [
		RiverNetwork.ChannelBranch.new([
			_point(Vector3(1.0, 1.2, 1.0)),
			junction,
		]),
		RiverNetwork.ChannelBranch.new([
			_point(Vector3(7.0, 1.2, 1.0)),
			junction,
		]),
		RiverNetwork.ChannelBranch.new([
			junction,
			_point(Vector3(4.0, 0.8, 7.0)),
		]),
	]
	var mesh := load(BUILDER_PATH).new(8.0).build(branches) as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array

	for point in [Vector2(4.0, 3.7), Vector2(3.7, 4.0), Vector2(4.3, 4.0), Vector2(4.0, 4.3)]:
		assert_true(_mesh_covers(point, vertices, indices))


func _point(position: Vector3) -> RiverNetwork.ChannelPoint:
	return RiverNetwork.ChannelPoint.new(position, 4096.0, Vector3(2.0, 0.5, 2.0))


func _mesh_covers(
	point: Vector2,
	vertices: PackedVector3Array,
	indices: PackedInt32Array
) -> bool:
	for index in range(0, indices.size(), 3):
		var first := Vector2(vertices[indices[index]].x, vertices[indices[index]].z)
		var second := Vector2(vertices[indices[index + 1]].x, vertices[indices[index + 1]].z)
		var third := Vector2(vertices[indices[index + 2]].x, vertices[indices[index + 2]].z)
		var first_side := (second - first).cross(point - first)
		var second_side := (third - second).cross(point - second)
		var third_side := (first - third).cross(point - third)
		if (
			(first_side >= -0.001 and second_side >= -0.001 and third_side >= -0.001)
			or (first_side <= 0.001 and second_side <= 0.001 and third_side <= 0.001)
		):
			return true
	return false
