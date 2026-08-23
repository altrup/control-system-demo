@tool
extends Node3D

const WorldGenerator := preload("res://world/world_generator.gd")
const TREE_SCENE := preload("res://world/tree.tscn")

@export var world_seed := 481516
@export_tool_button("Regenerate Preview") var regenerate_preview: Callable = _regenerate_preview

@onready var terrain: Terrain3D = $Terrain3D
@onready var water: MeshInstance3D = $Water
@onready var trees: Node3D = $Trees
@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Player/Head/Camera3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_generate_world()


func _regenerate_preview() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		_generate_world()


func _generate_world() -> void:
	var generator := WorldGenerator.new(world_seed)
	terrain.region_size = Terrain3D.SIZE_128
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", 1.5)
	terrain.assets = _create_terrain_assets()
	if not Engine.is_editor_hint():
		terrain.set_camera(camera)
	await get_tree().process_frame
	terrain.data.import_images(
		[_create_height_map(generator), null, null],
		Vector3.ZERO,
		0.0,
		1.0
	)
	water.mesh = _create_water_mesh(generator.stream_branches())
	_place_player(generator)
	_place_trees(generator)


func _create_height_map(generator: WorldGenerator) -> Image:
	var image := Image.create_empty(
		WorldGenerator.REGION_SIZE,
		WorldGenerator.REGION_SIZE,
		false,
		Image.FORMAT_RF
	)
	for x in WorldGenerator.REGION_SIZE:
		for z in WorldGenerator.REGION_SIZE:
			image.set_pixel(x, z, Color(generator.height_at(Vector2(x, z)), 0.0, 0.0, 1.0))
	return image


func _create_water_mesh(branches: Array[WorldGenerator.StreamBranch]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if branches.is_empty():
		return mesh

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var cap_radii: Dictionary[Vector3, float] = {}
	for branch in branches:
		var half_widths := PackedFloat32Array()
		var miters := PackedVector2Array()
		var miter_denominators := PackedFloat32Array()
		half_widths.resize(branch.points.size())
		miters.resize(branch.points.size())
		miter_denominators.resize(branch.points.size())
		for point_index in branch.points.size():
			var point := branch.points[point_index]
			var current := Vector2(point.position.x, point.position.z)
			var previous_position: Vector3 = branch.points[maxi(0, point_index - 1)].position
			var following_position: Vector3 = branch.points[mini(branch.points.size() - 1, point_index + 1)].position
			var previous := Vector2(previous_position.x, previous_position.z)
			var following := Vector2(following_position.x, following_position.z)
			var incoming := (current - previous).normalized()
			var outgoing := (following - current).normalized()
			if point_index == 0:
				incoming = outgoing
			elif point_index == branch.points.size() - 1:
				outgoing = incoming
			var half_width: float = point.half_width
			var turn_sine_half := sqrt(maxf(0.0, (1.0 - incoming.dot(outgoing)) * 0.5))
			if turn_sine_half > 0.001:
				half_width = minf(
					half_width,
					minf(current.distance_to(previous), current.distance_to(following))
						* 0.45 / turn_sine_half
				)
			var incoming_normal := Vector2(-incoming.y, incoming.x)
			var outgoing_normal := Vector2(-outgoing.y, outgoing.x)
			var miter := (incoming_normal + outgoing_normal).normalized()
			half_widths[point_index] = half_width
			miters[point_index] = miter
			miter_denominators[point_index] = maxf(miter.dot(incoming_normal), 0.25)
		for point_index in range(1, branch.points.size()):
			var current: Vector3 = branch.points[point_index].position
			var previous: Vector3 = branch.points[point_index - 1].position
			half_widths[point_index] = minf(
				half_widths[point_index],
				half_widths[point_index - 1]
					+ Vector2(current.x, current.z).distance_to(Vector2(previous.x, previous.z)) * 0.5
			)
		for point_index in range(branch.points.size() - 2, -1, -1):
			var current: Vector3 = branch.points[point_index].position
			var following: Vector3 = branch.points[point_index + 1].position
			half_widths[point_index] = minf(
				half_widths[point_index],
				half_widths[point_index + 1]
					+ Vector2(current.x, current.z).distance_to(Vector2(following.x, following.z)) * 0.5
			)

		var first_vertex := vertices.size()
		var distance := 0.0
		for point_index in branch.points.size():
			var point := branch.points[point_index]
			var previous: Vector3 = branch.points[maxi(0, point_index - 1)].position
			var center: Vector3 = point.position + Vector3.UP * 0.02
			var side := miters[point_index] * half_widths[point_index] / miter_denominators[point_index]
			if point_index > 0:
				distance += Vector2(center.x, center.z).distance_to(Vector2(previous.x, previous.z))
			vertices.append(center + Vector3(side.x, 0.0, side.y))
			vertices.append(center - Vector3(side.x, 0.0, side.y))
			normals.append_array([Vector3.UP, Vector3.UP])
			uvs.append_array([Vector2(0.0, distance * 0.1), Vector2(1.0, distance * 0.1)])
			if point_index > 0:
				var previous_left := first_vertex + (point_index - 1) * 2
				var current_left := first_vertex + point_index * 2
				var current_diagonal_area := minf(
					(vertices[current_left] - vertices[previous_left]).cross(
						vertices[previous_left + 1] - vertices[previous_left]
					).y,
					(vertices[current_left] - vertices[previous_left + 1]).cross(
						vertices[current_left + 1] - vertices[previous_left + 1]
					).y
				)
				var alternate_diagonal_area := minf(
					(vertices[current_left] - vertices[previous_left]).cross(
						vertices[current_left + 1] - vertices[previous_left]
					).y,
					(vertices[current_left + 1] - vertices[previous_left]).cross(
						vertices[previous_left + 1] - vertices[previous_left]
					).y
				)
				if alternate_diagonal_area > current_diagonal_area:
					indices.append_array([
						previous_left,
						current_left,
						current_left + 1,
						previous_left,
						current_left + 1,
						previous_left + 1,
					])
				else:
					indices.append_array([
						previous_left,
						current_left,
						previous_left + 1,
						previous_left + 1,
						current_left,
						current_left + 1,
					])
		for endpoint_index in [0, branch.points.size() - 1]:
			var endpoint := branch.points[endpoint_index]
			cap_radii[endpoint.position] = maxf(
				cap_radii.get(endpoint.position, 0.0),
				endpoint.half_width
			)

	for center in cap_radii:
		_append_water_cap(
			vertices,
			normals,
			uvs,
			indices,
			center + Vector3.UP * 0.025,
			cap_radii[center]
		)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_water_cap(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	center: Vector3,
	radius: float
) -> void:
	var first_vertex := vertices.size()
	vertices.append(center)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for point_index in 8:
		var angle := TAU * point_index / 8.0
		vertices.append(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
		normals.append(Vector3.UP)
		uvs.append(Vector2(cos(angle), sin(angle)) * 0.5 + Vector2(0.5, 0.5))
	for point_index in 8:
		indices.append_array([
			first_vertex,
			first_vertex + 1 + (point_index + 1) % 8,
			first_vertex + 1 + point_index,
		])


func _create_terrain_assets() -> Terrain3DAssets:
	var assets := Terrain3DAssets.new()
	assets.set_texture(0, _create_texture("Earth", Color(0.32, 0.22, 0.14)))
	assets.set_texture(1, _create_texture("Grass", Color(0.25, 0.42, 0.2)))
	return assets


func _create_texture(texture_name: String, color: Color) -> Terrain3DTextureAsset:
	var albedo_image := Image.create_empty(16, 16, true, Image.FORMAT_RGBA8)
	albedo_image.fill(Color(color, 0.5))
	albedo_image.generate_mipmaps()
	var normal_image := Image.create_empty(16, 16, true, Image.FORMAT_RGBA8)
	normal_image.fill(Color(0.5, 0.5, 1.0, 0.9))
	normal_image.generate_mipmaps()

	var texture := Terrain3DTextureAsset.new()
	texture.name = texture_name
	texture.albedo_texture = ImageTexture.create_from_image(albedo_image)
	texture.normal_texture = ImageTexture.create_from_image(normal_image)
	texture.uv_scale = 0.2
	return texture


func _place_player(generator: WorldGenerator) -> void:
	var spawn := generator.player_spawn()
	player.position = Vector3(spawn.x, generator.height_at(spawn) + 0.05, spawn.y)


func _place_trees(generator: WorldGenerator) -> void:
	for child in trees.get_children():
		child.free()
	for tree_position: Vector2 in generator.tree_positions():
		var tree := TREE_SCENE.instantiate() as StaticBody3D
		tree.position = Vector3(
			tree_position.x,
			generator.height_at(tree_position),
			tree_position.y
		)
		trees.add_child(tree)
