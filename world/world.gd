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
	water.mesh = _create_water_mesh(generator.stream_segments())
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


func _create_water_mesh(segments: Array[WorldGenerator.StreamSegment]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if segments.is_empty():
		return mesh

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for segment in segments:
		var tangent := Vector2(
			segment.end.x - segment.start.x,
			segment.end.z - segment.start.z
		).normalized()
		var perpendicular := Vector2(-tangent.y, tangent.x)
		var start_side := perpendicular * segment.start_half_width
		var end_side := perpendicular * segment.end_half_width
		var start := segment.start + Vector3.UP * 0.02
		var end := segment.end + Vector3.UP * 0.02
		var first_vertex := vertices.size()
		vertices.append_array([
			start + Vector3(start_side.x, 0.0, start_side.y),
			start - Vector3(start_side.x, 0.0, start_side.y),
			end + Vector3(end_side.x, 0.0, end_side.y),
			end - Vector3(end_side.x, 0.0, end_side.y),
		])
		normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE])
		indices.append_array([
			first_vertex,
			first_vertex + 2,
			first_vertex + 1,
			first_vertex + 1,
			first_vertex + 2,
			first_vertex + 3,
		])
		_append_water_cap(
			vertices,
			normals,
			uvs,
			indices,
			segment.start + Vector3.UP * 0.025,
			segment.start_half_width
		)
		_append_water_cap(
			vertices,
			normals,
			uvs,
			indices,
			segment.end + Vector3.UP * 0.025,
			segment.end_half_width
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
