extends GutTest

const WorldGenerator := preload("res://world/world_generator.gd")


func test_visible_world_uses_a_four_metre_hydrology_grid() -> void:
	assert_eq(WorldGenerator.REGION_SIZE, 256)
	assert_eq(WorldGenerator.HYDROLOGY_PADDING, 896)
	assert_eq(WorldGenerator.HYDROLOGY_SIZE, 512)
	assert_eq(WorldGenerator.HYDROLOGY_SAMPLE_SPACING, 4.0)
	assert_eq(WorldGenerator.FULL_DOMAIN_SIZE, 2048)
	assert_eq(WorldGenerator.TERRAIN_SAMPLE_SPACING, 0.5)
	assert_eq(WorldGenerator.TERRAIN_SAMPLE_SIZE, 512)
	assert_eq(WorldGenerator.FULL_TERRAIN_SAMPLE_SPACING, 2.0)
	assert_eq(WorldGenerator.FULL_TERRAIN_SAMPLE_SIZE, 1024)
