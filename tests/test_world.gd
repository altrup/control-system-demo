extends GutTest

const WORLD_SCENE_PATH := "res://world/world.tscn"
const WorldGenerator := preload("res://world/world_generator.gd")


func test_world_uses_generated_terrain() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	await wait_physics_frames(3)
	_handle_terrain3d_deprecation()

	var terrain := world.get_node_or_null("Terrain3D") as Terrain3D
	assert_not_null(terrain)
	if terrain == null:
		return
	var path: PackedVector3Array = WorldGenerator.new(481516, true).stream_path()
	var midpoint := path[path.size() / 2]
	assert_lt(terrain.data.get_height(midpoint), midpoint.y)
	assert_eq(world.find_children("*", "CSGShape3D", true, false).size(), 0)


func test_world_has_generated_water_and_separate_trees() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var trees := world.get_node_or_null("Trees")
	var water := world.get_node_or_null("Water") as MeshInstance3D
	assert_not_null(trees)
	assert_not_null(water)
	if trees == null or water == null:
		return
	assert_true(await wait_until(func() -> bool: return trees.get_child_count() == 112, 3.0))
	_handle_terrain3d_deprecation()

	assert_true(water.mesh is ArrayMesh)
	assert_gte(water.mesh.get_aabb().size.z, 119.0)
	assert_eq(trees.get_child_count(), 112)


func test_player_lands_in_world() -> void:
	var world := _instantiate_world()
	if world == null:
		return

	var players: Array[Node] = world.find_children("*", "CharacterBody3D", true, false)
	assert_eq(players.size(), 1)
	if players.size() != 1:
		return

	var player := players[0] as CharacterBody3D
	await wait_physics_frames(30)
	_handle_terrain3d_deprecation()
	assert_true(player.is_on_floor())
	assert_gt(player.global_position.y, 1.0)


func _instantiate_world() -> Node3D:
	assert_true(ResourceLoader.exists(WORLD_SCENE_PATH), "World scene exists")
	if not ResourceLoader.exists(WORLD_SCENE_PATH):
		return null

	var world_scene := load(WORLD_SCENE_PATH) as PackedScene
	return add_child_autofree(world_scene.instantiate()) as Node3D


func _handle_terrain3d_deprecation() -> void:
	for error: GutTrackedError in get_errors():
		if error.contains_text("instance_reset_physics_interpolation() is deprecated"):
			error.handled = true
