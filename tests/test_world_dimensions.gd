extends GutTest

const WorldGenerator := preload("res://world/world_generator.gd")


func test_visible_world_and_hydrology_padding_are_128_metres() -> void:
	assert_eq(WorldGenerator.REGION_SIZE, 128)
	assert_eq(WorldGenerator.HYDROLOGY_PADDING, 128)
	assert_eq(WorldGenerator.HYDROLOGY_SIZE, 384)
	assert_eq(WorldGenerator.TERRAIN_SAMPLE_SPACING, 0.5)
	assert_eq(WorldGenerator.TERRAIN_SAMPLE_SIZE, 256)
