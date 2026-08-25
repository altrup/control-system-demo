extends GutTest

const BUILDER_PATH := "res://world/ocean_mesh_builder.gd"


func test_builds_ocean_cells_in_world_space() -> void:
	assert_true(ResourceLoader.exists(BUILDER_PATH))
	if not ResourceLoader.exists(BUILDER_PATH):
		return
	var builder_script := load(BUILDER_PATH) as GDScript
	var mask := PackedByteArray([
		1, 1, 1,
		0, 0, 0,
		0, 0, 0,
	])
	var mesh := builder_script.new().call("build", mask, 3, -1.0, 1.0, 0.0) as ArrayMesh

	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(mesh.get_aabb().position, Vector3(-1.0, 0.0, -1.0))
	assert_eq(mesh.get_aabb().size.x, 2.0)
	assert_lte(mesh.get_aabb().size.y, 0.0001)
	assert_eq(mesh.get_aabb().size.z, 1.0)


func test_does_not_build_water_over_land_only_cells() -> void:
	assert_true(ResourceLoader.exists(BUILDER_PATH))
	if not ResourceLoader.exists(BUILDER_PATH):
		return
	var builder_script := load(BUILDER_PATH) as GDScript
	var mask := PackedByteArray()
	mask.resize(9)
	var mesh := builder_script.new().call("build", mask, 3, -1.0, 1.0, 0.0) as ArrayMesh

	assert_eq(mesh.get_surface_count(), 0)
