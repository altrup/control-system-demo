extends GutTest

const WORLD_SCENE_PATH := "res://world/world.tscn"
const WorldGenerator := preload("res://world/world_generator.gd")


func test_world_uses_half_meter_regions_centered_on_the_origin() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var terrain := world.get_node_or_null("Terrain3D") as Terrain3D
	assert_not_null(terrain)
	if terrain == null:
		return
	_handle_terrain3d_deprecation()

	assert_eq(terrain.region_size, Terrain3D.SIZE_64)
	assert_eq(terrain.vertex_spacing, 0.5)
	assert_true(await wait_until(func() -> bool: return terrain.data.get_region_count() == 64, 5.0))


func test_world_exposes_river_tuning_as_normal_inspector_fields() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var property_names: Array[StringName] = []
	for property in world.get_property_list():
		property_names.append(property.name)
	_handle_terrain3d_deprecation()

	assert_has(property_names, &"river_minimum_visible_flow")
	assert_has(property_names, &"river_reference_flow")
	assert_has(property_names, &"river_discharge_scale")
	assert_has(property_names, &"river_reference_width")
	assert_has(property_names, &"river_reference_depth")
	assert_has(property_names, &"river_bank_falloff_ratio")
	assert_has(property_names, &"sea_level")
	assert_has(property_names, &"global_relief")
	assert_has(property_names, &"preview_full_generation_domain")
	assert_does_not_have(property_names, &"river_parameters")
	assert_does_not_have(property_names, &"river_stream_threshold")


func test_sea_level_controls_the_generated_ocean_surface() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var property_names: Array[StringName] = []
	for property in world.get_property_list():
		property_names.append(property.name)
	if not property_names.has(&"sea_level"):
		fail_test("The world exposes sea level")
		return

	world.set("sea_level", -2.0)
	await world.call("_generate_world")
	var ocean := world.get_node_or_null("Ocean") as MeshInstance3D
	assert_not_null(ocean)
	if ocean == null or not ocean.mesh is ArrayMesh:
		return
	_handle_terrain3d_deprecation()
	assert_almost_eq(ocean.mesh.get_aabb().position.y, -2.0, 0.001)
	assert_gt(ocean.mesh.get_surface_count(), 0)


func test_global_relief_controls_generated_terrain() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var terrain := world.get_node("Terrain3D") as Terrain3D
	var trees := world.get_node("Trees") as Node3D
	assert_true(await wait_until(func() -> bool: return trees.get_child_count() == 448, 5.0))

	world.set("river_discharge_scale", 1.0)
	world.set("global_relief", 40.0)
	await world.call("_generate_world")
	var low_relief_range := _terrain_height_range(terrain)
	world.set("global_relief", 200.0)
	await world.call("_generate_world")
	var high_relief_range := _terrain_height_range(terrain)
	_handle_terrain3d_deprecation()

	assert_gt(high_relief_range, low_relief_range * 1.5)


func test_world_maps_inspector_fields_to_generation_parameters() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	world.set("river_minimum_visible_flow", 16384.0)
	world.set("river_reference_flow", 32768.0)
	world.set("river_discharge_scale", 1.5)
	world.set("river_reference_width", 7.0)
	world.set("river_reference_depth", 1.5)

	var parameters: Resource = world.call("_create_river_parameters")
	_handle_terrain3d_deprecation()

	assert_eq(parameters.get("minimum_visible_flow"), 16384.0)
	assert_eq(parameters.get("reference_flow"), 32768.0)
	assert_eq(parameters.get("discharge_scale"), 1.5)
	assert_eq(parameters.get("reference_width"), 7.0)
	assert_eq(parameters.get("reference_depth"), 1.5)


func test_world_configures_terrain_data_storage() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var terrain := world.get_node("Terrain3D") as Terrain3D
	_handle_terrain3d_deprecation()

	assert_false(terrain.data_directory.is_empty())


func test_world_uses_generated_terrain() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var terrain := world.get_node_or_null("Terrain3D") as Terrain3D
	assert_not_null(terrain)
	if terrain == null:
		return
	var generator := WorldGenerator.new(WorldGenerator.DEFAULT_SEED)
	var segments: Array = generator.stream_segments()
	var midpoint: Vector3 = segments[segments.size() / 2].start
	var expected_height := generator.height_at(Vector2(midpoint.x, midpoint.z))
	assert_true(await wait_until(
		func() -> bool:
			return absf(terrain.data.get_height(midpoint) - expected_height) < 0.1,
		5.0
	))
	_handle_terrain3d_deprecation()
	assert_lt(terrain.data.get_height(midpoint), midpoint.y)
	assert_almost_eq(
		terrain.data.get_height(midpoint),
		expected_height,
		0.1
	)
	assert_eq(world.find_children("*", "CSGShape3D", true, false).size(), 0)


func test_regeneration_removes_stale_terrain_regions() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var terrain := world.get_node("Terrain3D") as Terrain3D
	assert_true(await wait_until(func() -> bool: return terrain.data.get_region_count() == 64, 5.0))
	var stale_region := terrain.data.get_regions_active()[0].duplicate(true) as Terrain3DRegion
	stale_region.location = Vector2i(4, 0)
	assert_eq(terrain.data.add_region(stale_region), OK)
	assert_eq(terrain.data.get_region_count(), 65)

	await world.call("_generate_world")

	assert_eq(terrain.data.get_region_count(), 64)


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
	assert_true(await wait_until(func() -> bool: return trees.get_child_count() == 448, 5.0))
	_handle_terrain3d_deprecation()

	assert_true(water.mesh is ArrayMesh)
	var water_size := water.mesh.get_aabb().size
	assert_gt(maxf(water_size.x, water_size.z), 20.0)
	assert_eq(trees.get_child_count(), 448)


func test_full_preview_shows_the_hydrology_domain_without_trees() -> void:
	var world := _instantiate_world()
	if world == null:
		return
	var property_names: Array[StringName] = []
	for property in world.get_property_list():
		property_names.append(property.name)
	if not property_names.has(&"preview_full_generation_domain"):
		fail_test("The world exposes the full-domain preview toggle")
		return

	await world.call("_generate_world", true)
	var terrain := world.get_node("Terrain3D") as Terrain3D
	var water := world.get_node("Water") as MeshInstance3D
	var trees := world.get_node("Trees") as Node3D
	var preview_bounds := world.get_node_or_null("PreviewBounds") as MeshInstance3D
	_handle_terrain3d_deprecation()

	assert_eq(terrain.data.get_region_count(), 256)
	assert_gte(water.mesh.get_aabb().position.x, -1024.0)
	assert_lte(water.mesh.get_aabb().end.x, 1024.0)
	assert_false(trees.visible)
	assert_not_null(preview_bounds)
	if preview_bounds == null:
		return
	assert_true(preview_bounds.visible)

	await world.call("_generate_world", false)
	_handle_terrain3d_deprecation()
	assert_eq(terrain.data.get_region_count(), 64)
	assert_true(trees.visible)
	assert_false(preview_bounds.visible)


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


func test_generated_water_stays_inside_world_bounds() -> void:
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
	var bounds := water.mesh.get_aabb()
	assert_gte(bounds.position.x, -128.0)
	assert_gte(bounds.position.z, -128.0)
	assert_lte(bounds.end.x, 128.0)
	assert_lte(bounds.end.z, 128.0)


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
	for branch in WorldGenerator.new(WorldGenerator.DEFAULT_SEED).stream_branches():
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
	var terrain := world.get_node("Terrain3D") as Terrain3D
	_handle_terrain3d_deprecation()
	assert_true(player.is_on_floor())
	assert_almost_eq(
		player.global_position.y,
		terrain.data.get_height(player.global_position),
		0.1
	)


func _instantiate_world() -> Node3D:
	assert_true(ResourceLoader.exists(WORLD_SCENE_PATH), "World scene exists")
	if not ResourceLoader.exists(WORLD_SCENE_PATH):
		return null

	var world_scene := load(WORLD_SCENE_PATH) as PackedScene
	return add_child_autofree(world_scene.instantiate()) as Node3D


func _terrain_height_range(terrain: Terrain3D) -> float:
	var lowest := INF
	var highest := -INF
	for x in range(-128, 128, 8):
		for z in range(-128, 128, 8):
			var height := terrain.data.get_height(Vector3(x, 0.0, z))
			lowest = minf(lowest, height)
			highest = maxf(highest, height)
	return highest - lowest


func _handle_terrain3d_deprecation() -> void:
	for error: GutTrackedError in get_errors():
		if error.contains_text("instance_reset_physics_interpolation() is deprecated"):
			error.handled = true
