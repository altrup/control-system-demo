extends RefCounted

const RiverNetwork := preload("res://world/river_network.gd")

const WATER_HEIGHT_OFFSET := 0.02
const UV_SCALE := 0.1
const MINIMUM_TRIANGLE_AREA := 0.0001

var _region_size: float


func _init(region_size: float) -> void:
	_region_size = region_size


func build(branches: Array[RiverNetwork.ChannelBranch]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var junction_edges: Dictionary[Vector3, Array] = {}
	for branch in branches:
		_append_branch(branch, vertices, normals, uvs, indices, junction_edges)
	for center in junction_edges:
		var edges: Array = junction_edges[center]
		if edges.size() >= 6:
			_append_junction(center, edges, vertices, normals, uvs, indices)

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
	branch: RiverNetwork.ChannelBranch,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	junction_edges: Dictionary[Vector3, Array]
) -> void:
	if branch.points.size() < 2:
		return
	var first_vertex := vertices.size()
	for index in branch.points.size():
		var point := branch.points[index]
		var previous: Vector3 = branch.points[maxi(0, index - 1)].position
		var following: Vector3 = branch.points[mini(branch.points.size() - 1, index + 1)].position
		var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
		var left_direction := Vector2(-tangent.y, tangent.x)
		var left := point.position + Vector3(left_direction.x, 0.0, left_direction.y) * point.half_width
		var right := point.position - Vector3(left_direction.x, 0.0, left_direction.y) * point.half_width
		_append_vertex(left, vertices, normals, uvs)
		_append_vertex(point.position, vertices, normals, uvs)
		_append_vertex(right, vertices, normals, uvs)
		if index == 0 or index == branch.points.size() - 1:
			_register_junction_edges(point.position, left, right, junction_edges)
	for index in range(1, branch.points.size()):
		var previous := first_vertex + (index - 1) * 3
		var current := first_vertex + index * 3
		_append_triangle(previous, current, previous + 1, vertices, indices)
		_append_triangle(previous + 1, current, current + 1, vertices, indices)
		_append_triangle(previous + 1, current + 1, previous + 2, vertices, indices)
		_append_triangle(previous + 2, current + 1, current + 2, vertices, indices)


func _register_junction_edges(
	center: Vector3,
	left: Vector3,
	right: Vector3,
	junction_edges: Dictionary[Vector3, Array]
) -> void:
	if not junction_edges.has(center):
		junction_edges[center] = []
	junction_edges[center].append(left)
	junction_edges[center].append(right)


func _append_junction(
	center: Vector3,
	edges: Array,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> void:
	var junction_center := _water_vertex(center)
	edges.sort_custom(func(first: Vector3, second: Vector3) -> bool:
		var first_vertex := _water_vertex(first)
		var second_vertex := _water_vertex(second)
		return atan2(first_vertex.z - junction_center.z, first_vertex.x - junction_center.x) < atan2(
			second_vertex.z - junction_center.z,
			second_vertex.x - junction_center.x
		)
	)
	var center_index := vertices.size()
	_append_vertex(center, vertices, normals, uvs)
	var first_edge := vertices.size()
	for edge: Vector3 in edges:
		_append_vertex(edge, vertices, normals, uvs)
	for index in edges.size():
		_append_triangle(
			center_index,
			first_edge + index,
			first_edge + (index + 1) % edges.size(),
			vertices,
			indices
		)


func _append_vertex(
	position: Vector3,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array
) -> void:
	var vertex := _water_vertex(position)
	vertices.append(vertex)
	normals.append(Vector3.UP)
	uvs.append(Vector2(vertex.x, vertex.z) * UV_SCALE)


func _water_vertex(position: Vector3) -> Vector3:
	return Vector3(
		clampf(position.x, 0.0, _region_size),
		position.y + WATER_HEIGHT_OFFSET,
		clampf(position.z, 0.0, _region_size)
	)


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
