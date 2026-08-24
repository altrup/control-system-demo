extends RefCounted

const RiverNetwork := preload("res://world/river_network.gd")

const WATER_HEIGHT_OFFSET := 0.02
const SHORE_OVERLAP := 0.5
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
	var clipped := _clip_mesh(vertices, indices)
	vertices = clipped[0]
	indices = clipped[1]
	normals.clear()
	uvs.clear()
	for vertex in vertices:
		normals.append(Vector3.UP)
		uvs.append(Vector2(vertex.x, vertex.z) * UV_SCALE)

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
		var lateral := Vector3(left_direction.x, 0.0, left_direction.y)
		var surface_half_width := point.half_width + SHORE_OVERLAP
		var left := point.position + lateral * surface_half_width
		var right := point.position - lateral * surface_half_width
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
	return position + Vector3.UP * WATER_HEIGHT_OFFSET


func _clip_mesh(
	input_vertices: PackedVector3Array,
	input_indices: PackedInt32Array
) -> Array:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var vertex_indices: Dictionary[Vector3, int] = {}
	var world_min := _region_size * -0.5
	var world_max := world_min + _region_size
	for index in range(0, input_indices.size(), 3):
		var polygon: Array[Vector3] = [
			input_vertices[input_indices[index]],
			input_vertices[input_indices[index + 1]],
			input_vertices[input_indices[index + 2]],
		]
		for boundary in 4:
			polygon = _clip_polygon(polygon, boundary, world_min, world_max)
			if polygon.size() < 3:
				break
		for triangle_index in range(1, polygon.size() - 1):
			_append_triangle(
				_vertex_index(polygon[0], vertices, vertex_indices),
				_vertex_index(polygon[triangle_index], vertices, vertex_indices),
				_vertex_index(polygon[triangle_index + 1], vertices, vertex_indices),
				vertices,
				indices
			)
	return [vertices, indices]


func _clip_polygon(
	polygon: Array[Vector3],
	boundary: int,
	world_min: float,
	world_max: float
) -> Array[Vector3]:
	var clipped: Array[Vector3] = []
	if polygon.is_empty():
		return clipped
	var previous := polygon[-1]
	var previous_inside := _inside_boundary(previous, boundary, world_min, world_max)
	for current in polygon:
		var current_inside := _inside_boundary(current, boundary, world_min, world_max)
		if current_inside != previous_inside:
			clipped.append(_boundary_intersection(
				previous, current, boundary, world_min, world_max
			))
		if current_inside:
			clipped.append(current)
		previous = current
		previous_inside = current_inside
	return clipped


func _inside_boundary(
	vertex: Vector3,
	boundary: int,
	world_min: float,
	world_max: float
) -> bool:
	match boundary:
		0:
			return vertex.x >= world_min
		1:
			return vertex.x <= world_max
		2:
			return vertex.z >= world_min
		_:
			return vertex.z <= world_max


func _boundary_intersection(
	start: Vector3,
	end: Vector3,
	boundary: int,
	world_min: float,
	world_max: float
) -> Vector3:
	var start_value := start.x if boundary < 2 else start.z
	var end_value := end.x if boundary < 2 else end.z
	var boundary_value := world_min if boundary % 2 == 0 else world_max
	return start.lerp(end, (boundary_value - start_value) / (end_value - start_value))


func _vertex_index(
	vertex: Vector3,
	vertices: PackedVector3Array,
	vertex_indices: Dictionary[Vector3, int]
) -> int:
	if vertex_indices.has(vertex):
		return vertex_indices[vertex]
	var index := vertices.size()
	vertices.append(vertex)
	vertex_indices[vertex] = index
	return index


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
