extends Node3D

const WorldGenerator := preload("res://world/world_generator.gd")
const TREE_SCENE := preload("res://world/tree.tscn")

@export var world_seed := 481516

@onready var terrain: Terrain3D = $Terrain3D
@onready var water: MeshInstance3D = $Water
@onready var trees: Node3D = $Trees
@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Player/Head/Camera3D


func _ready() -> void:
	var generator := WorldGenerator.new(world_seed)
	terrain.region_size = Terrain3D.SIZE_64
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", 10.0)
	terrain.assets = _create_terrain_assets()
	terrain.set_camera(camera)
	await get_tree().process_frame
	terrain.data.import_images(
		[_create_height_map(generator), null, null],
		Vector3.ZERO,
		0.0,
		1.0
	)
	water.position = Vector3(
		WorldGenerator.REGION_SIZE * 0.5,
		WorldGenerator.WATER_LEVEL,
		WorldGenerator.REGION_SIZE * 0.5
	)
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


func _create_terrain_assets() -> Terrain3DAssets:
	var assets := Terrain3DAssets.new()
	assets.set_texture(0, _create_texture("Grass", Color(0.25, 0.42, 0.2)))
	assets.set_texture(1, _create_texture("Earth", Color(0.32, 0.22, 0.14)))
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
	var spawn: Vector2 = WorldGenerator.PLAYER_SPAWN
	player.position = Vector3(spawn.x, generator.height_at(spawn) + 0.05, spawn.y)


func _place_trees(generator: WorldGenerator) -> void:
	for tree_position: Vector2 in generator.tree_positions():
		var tree := TREE_SCENE.instantiate() as StaticBody3D
		tree.position = Vector3(
			tree_position.x,
			generator.height_at(tree_position),
			tree_position.y
		)
		trees.add_child(tree)
