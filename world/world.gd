@tool
extends Node3D

const WorldGenerator := preload("res://world/world_generator.gd")
const TREE_SCENE := preload("res://world/tree.tscn")

@export var world_seed := 481516
@export var force_river_route := true
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
	var generator := WorldGenerator.new(world_seed, force_river_route)
	terrain.region_size = Terrain3D.SIZE_128
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", 10.0)
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
	water.mesh = _create_water_mesh(generator.stream_path())
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


func _create_water_mesh(path: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if path.size() < 2:
		return mesh

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index in path.size():
		var previous := path[maxi(0, index - 1)]
		var following := path[mini(path.size() - 1, index + 1)]
		var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
		var side := Vector2(-tangent.y, tangent.x) * WorldGenerator.STREAM_HALF_WIDTH
		var point := path[index] + Vector3.UP * 0.02
		vertices.append(point + Vector3(side.x, 0.0, side.y))
		vertices.append(point - Vector3(side.x, 0.0, side.y))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, index * 0.25))
		uvs.append(Vector2(1.0, index * 0.25))
	for index in path.size() - 1:
		var left := index * 2
		var right := left + 1
		var next_left := left + 2
		var next_right := left + 3
		indices.append_array([left, next_left, right, right, next_left, next_right])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
