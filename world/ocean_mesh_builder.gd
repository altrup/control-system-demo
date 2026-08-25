extends RefCounted


func build(
	ocean_mask: PackedByteArray,
	sample_size: int,
	terrain_min: float,
	sample_spacing: float,
	sea_level: float
) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if ocean_mask.size() != sample_size * sample_size:
		push_error("Ocean mask dimensions do not match the terrain grid.")
		return mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var vertex_indices: Dictionary[Vector2i, int] = {}
	for z in range(sample_size - 1):
		for x in range(sample_size - 1):
			if not _cell_has_ocean(ocean_mask, sample_size, x, z):
				continue
			var top_left := _vertex_index(
				vertex_indices, vertices, normals, x, z, terrain_min, sample_spacing, sea_level
			)
			var top_right := _vertex_index(
				vertex_indices, vertices, normals, x + 1, z, terrain_min, sample_spacing, sea_level
			)
			var bottom_left := _vertex_index(
				vertex_indices, vertices, normals, x, z + 1, terrain_min, sample_spacing, sea_level
			)
			var bottom_right := _vertex_index(
				vertex_indices, vertices, normals, x + 1, z + 1, terrain_min, sample_spacing, sea_level
			)
			indices.append_array([
				top_left, bottom_left, bottom_right,
				top_left, bottom_right, top_right,
			])
	if indices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _cell_has_ocean(
	ocean_mask: PackedByteArray,
	sample_size: int,
	x: int,
	z: int
) -> bool:
	return (
		ocean_mask[z * sample_size + x] == 1
		or ocean_mask[z * sample_size + x + 1] == 1
		or ocean_mask[(z + 1) * sample_size + x] == 1
		or ocean_mask[(z + 1) * sample_size + x + 1] == 1
	)


func _vertex_index(
	vertex_indices: Dictionary[Vector2i, int],
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	x: int,
	z: int,
	terrain_min: float,
	sample_spacing: float,
	sea_level: float
) -> int:
	var coordinate := Vector2i(x, z)
	if vertex_indices.has(coordinate):
		return vertex_indices[coordinate]
	var index := vertices.size()
	vertex_indices[coordinate] = index
	vertices.append(Vector3(
		terrain_min + x * sample_spacing,
		sea_level,
		terrain_min + z * sample_spacing
	))
	normals.append(Vector3.UP)
	return index
