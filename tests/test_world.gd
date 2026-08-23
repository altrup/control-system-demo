extends GutTest

const WORLD_SCENE_PATH := "res://world/world.tscn"
const WorldGenerator := preload("res://world/world_generator.gd")
const RiverShoreline := preload("res://world/river_shoreline.gd")


func test_world_uses_128_metre_terrain() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var terrain := world.get_node_or_null("Terrain3D") as Terrain3D
	assert_not_null(terrain)
	if terrain == null:
		return
	_handle_terrain3d_deprecation()

	assert_eq(terrain.region_size, Terrain3D.SIZE_128)


func test_world_uses_generated_terrain() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var terrain := world.get_node_or_null("Terrain3D") as Terrain3D
	assert_not_null(terrain)
	if terrain == null:
		return
	var segments: Array = WorldGenerator.new(103).stream_segments()
	var midpoint: Vector3 = segments[segments.size() / 2].start
	assert_true(await wait_until(
		func() -> bool: return not is_nan(terrain.data.get_height(midpoint)),
		3.0
	))
	_handle_terrain3d_deprecation()
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
	var water_size := water.mesh.get_aabb().size
	assert_gt(maxf(water_size.x, water_size.z), 20.0)
	assert_eq(trees.get_child_count(), 112)


func test_generated_water_has_no_folded_or_degenerate_triangles() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var water := world.get_node_or_null("Water") as MeshInstance3D
	assert_not_null(water)
	if water == null:
		return
	assert_true(await wait_until(
		func() -> bool: return water.mesh is ArrayMesh and water.mesh.get_surface_count() > 0,
		3.0
	))
	_handle_terrain3d_deprecation()
	var arrays := water.mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var minimum_upward_area := INF
	for index in range(0, indices.size(), 3):
		var first := vertices[indices[index]]
		var second := vertices[indices[index + 1]]
		var third := vertices[indices[index + 2]]
		minimum_upward_area = minf(minimum_upward_area, (second - first).cross(third - first).y)

	assert_gt(minimum_upward_area, 0.0001)


func test_generated_water_reaches_the_sampled_banks() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var water := world.get_node_or_null("Water") as MeshInstance3D
	assert_not_null(water)
	if water == null:
		return
	assert_true(await wait_until(
		func() -> bool: return water.mesh is ArrayMesh and water.mesh.get_surface_count() > 0,
		3.0
	))
	_handle_terrain3d_deprecation()
	var generator := WorldGenerator.new(103)
	var shore_branches := RiverShoreline.new().build(
		generator.stream_branches(),
		Callable(generator, "height_at")
	)
	var widest_point: RiverShoreline.ShorePoint
	var widest_distance := 0.0
	for branch in shore_branches:
		for point in branch.points:
			if not _is_inside_world(point.center, 6.0):
				continue
			var distance := maxf(
				_point_distance(point.center, point.left_shore),
				_point_distance(point.center, point.right_shore)
			)
			if distance > widest_distance:
				widest_point = point
				widest_distance = distance

	assert_not_null(widest_point)
	if widest_point == null:
		return
	var arrays := water.mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	assert_true(_mesh_covers(
		widest_point.center.lerp(widest_point.left_edge, 0.95),
		vertices,
		indices
	))
	assert_true(_mesh_covers(
		widest_point.center.lerp(widest_point.right_edge, 0.95),
		vertices,
		indices
	))


func test_water_mesh_reuses_vertices_inside_each_stream_branch() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var water := world.get_node_or_null("Water") as MeshInstance3D
	assert_not_null(water)
	if water == null:
		return
	assert_true(await wait_until(
		func() -> bool: return water.mesh is ArrayMesh and water.mesh.get_surface_count() > 0,
		3.0
	))
	_handle_terrain3d_deprecation()
	var arrays := water.mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var point_count := 0
	for branch in WorldGenerator.new(103).stream_branches():
		point_count += branch.points.size()

	assert_lt(vertices.size(), point_count * 6)


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


func _is_inside_world(position: Vector3, margin: float) -> bool:
	return (
		position.x >= margin
		and position.z >= margin
		and position.x <= WorldGenerator.REGION_SIZE - 1 - margin
		and position.z <= WorldGenerator.REGION_SIZE - 1 - margin
	)


func _point_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))


func _mesh_covers(
	point: Vector3,
	vertices: PackedVector3Array,
	indices: PackedInt32Array
) -> bool:
	var target := Vector2(point.x, point.z)
	for index in range(0, indices.size(), 3):
		var first := Vector2(vertices[indices[index]].x, vertices[indices[index]].z)
		var second := Vector2(vertices[indices[index + 1]].x, vertices[indices[index + 1]].z)
		var third := Vector2(vertices[indices[index + 2]].x, vertices[indices[index + 2]].z)
		var first_side := (second - first).cross(target - first)
		var second_side := (third - second).cross(target - second)
		var third_side := (first - third).cross(target - third)
		if (
			(first_side >= -0.001 and second_side >= -0.001 and third_side >= -0.001)
			or (first_side <= 0.001 and second_side <= 0.001 and third_side <= 0.001)
		):
			return true
	return false
