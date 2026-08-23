extends RefCounted

const RiverShoreline := preload("res://world/river_shoreline.gd")

const WATER_HEIGHT_OFFSET := 0.02
const UV_SCALE := 0.1
const MINIMUM_TRIANGLE_AREA := 0.0001


func build(branches: Array[RiverShoreline.ShoreBranch]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for branch in branches:
		_append_branch(branch, vertices, normals, uvs, indices)

	var mesh := ArrayMesh.new()
	if indices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_branch(
	branch: RiverShoreline.ShoreBranch,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> void:
	var first_vertex := vertices.size()
	for point in branch.points:
		for position in [point.left_edge, point.center, point.right_edge]:
			var vertex := Vector3(position.x, point.center.y + WATER_HEIGHT_OFFSET, position.z)
			vertices.append(vertex)
			normals.append(Vector3.UP)
			uvs.append(Vector2(vertex.x, vertex.z) * UV_SCALE)
	for index in range(1, branch.points.size()):
		var previous := first_vertex + (index - 1) * 3
		var current := first_vertex + index * 3
		_append_triangle(previous, current, previous + 1, vertices, indices)
		_append_triangle(previous + 1, current, current + 1, vertices, indices)
		_append_triangle(previous + 1, current + 1, previous + 2, vertices, indices)
		_append_triangle(previous + 2, current + 1, current + 2, vertices, indices)


func _append_triangle(
	first: int,
	second: int,
	third: int,
	vertices: PackedVector3Array,
	indices: PackedInt32Array
) -> void:
	var upward_area := (
		(vertices[second] - vertices[first]).cross(vertices[third] - vertices[first]).y
	)
	if absf(upward_area) <= MINIMUM_TRIANGLE_AREA:
		return
	if upward_area > 0.0:
		indices.append_array([first, second, third])
	else:
		indices.append_array([first, third, second])
