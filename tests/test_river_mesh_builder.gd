extends GutTest

const BUILDER_PATH := "res://world/river_mesh_builder.gd"
const RiverShoreline := preload("res://world/river_shoreline.gd")


func test_crossing_channels_have_complete_valid_surfaces() -> void:
	assert_true(ResourceLoader.exists(BUILDER_PATH))
	if not ResourceLoader.exists(BUILDER_PATH):
		return
	var branches: Array[RiverShoreline.ShoreBranch] = [
		_branch([
			_point(Vector3(-2.0, 0.0, 0.0), Vector3(-2.0, 0.0, 1.0), Vector3(-2.0, 0.0, -1.0)),
			_point(Vector3(2.0, 0.0, 0.0), Vector3(2.0, 0.0, 1.0), Vector3(2.0, 0.0, -1.0)),
		]),
		_branch([
			_point(Vector3(0.0, 0.0, -2.0), Vector3(-1.0, 0.0, -2.0), Vector3(1.0, 0.0, -2.0)),
			_point(Vector3(0.0, 0.0, 2.0), Vector3(-1.0, 0.0, 2.0), Vector3(1.0, 0.0, 2.0)),
		]),
	]
	var mesh := load(BUILDER_PATH).new().build(branches) as ArrayMesh
	assert_eq(mesh.get_surface_count(), 1)
	if mesh.get_surface_count() != 1:
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var area := 0.0
	for index in range(0, indices.size(), 3):
		var triangle_area := (
			(vertices[indices[index + 1]] - vertices[indices[index]])
				.cross(vertices[indices[index + 2]] - vertices[indices[index]]).y
		) * 0.5
		assert_gt(triangle_area, 0.0001)
		area += triangle_area

	assert_gte(area, 12.0)
	assert_lte(area, 16.01)


func test_mesh_keeps_centerline_height_samples() -> void:
	var points: Array[RiverShoreline.ShorePoint] = [
		_point(Vector3(-2.0, 1.0, 0.0), Vector3(-2.0, 1.0, 1.0), Vector3(-2.0, 1.0, -1.0)),
		_point(Vector3(0.0, 2.0, 0.0), Vector3(0.0, 2.0, 1.0), Vector3(0.0, 2.0, -1.0)),
		_point(Vector3(2.0, 3.0, 0.0), Vector3(2.0, 3.0, 1.0), Vector3(2.0, 3.0, -1.0)),
	]
	var branches: Array[RiverShoreline.ShoreBranch] = [_branch(points)]
	var mesh := load(BUILDER_PATH).new().build(branches) as ArrayMesh
	var vertices := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for point in points:
		assert_true(vertices.has(point.center + Vector3.UP * 0.02))


func _point(center: Vector3, left: Vector3, right: Vector3) -> RiverShoreline.ShorePoint:
	return RiverShoreline.ShorePoint.new(center, left, right, left, right, 1.0)


func _branch(points: Array[RiverShoreline.ShorePoint]) -> RiverShoreline.ShoreBranch:
	return RiverShoreline.ShoreBranch.new(points)
