extends GutTest

const GENERATOR_PATH := "res://world/world_generator.gd"


func test_seed_repeats_height_generation() -> void:
	assert_true(ResourceLoader.exists(GENERATOR_PATH), "World generator exists")
	if not ResourceLoader.exists(GENERATOR_PATH):
		return

	var generator_script := load(GENERATOR_PATH) as GDScript
	var first: RefCounted = generator_script.new(481516)
	var repeated: RefCounted = generator_script.new(481516)
	var changed: RefCounted = generator_script.new(108)
	var sample := Vector2(12.5, 19.25)

	assert_eq(first.call("height_at", sample), repeated.call("height_at", sample))
	assert_ne(first.call("height_at", sample), changed.call("height_at", sample))


func test_stream_bed_is_below_water_and_banks_are_above_it() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516)
	var water_level := 0.25

	assert_lt(generator.call("height_at", Vector2(32.0, 32.0)), water_level)
	assert_gt(generator.call("height_at", Vector2(24.0, 32.0)), water_level)
	assert_gt(generator.call("height_at", Vector2(40.0, 32.0)), water_level)


func test_seed_repeats_tree_placement() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var first: RefCounted = generator_script.new(481516)
	var repeated: RefCounted = generator_script.new(481516)
	var changed: RefCounted = generator_script.new(108)

	assert_true(first.has_method("tree_positions"))
	if not first.has_method("tree_positions"):
		return

	assert_eq(first.call("tree_positions"), repeated.call("tree_positions"))
	assert_ne(first.call("tree_positions"), changed.call("tree_positions"))


func test_trees_respect_world_clearances() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516)
	var positions := generator.call("tree_positions") as Array
	var spawn := Vector2(12.0, 32.0)

	assert_eq(positions.size(), 28)
	for index in positions.size():
		var position := positions[index] as Vector2
		var river_center := 32.0 + sin((position.y - 32.0) * TAU / 64.0) * 2.5
		assert_gte(position.x, 4.0)
		assert_lte(position.x, 60.0)
		assert_gte(position.y, 4.0)
		assert_lte(position.y, 60.0)
		assert_gte(absf(position.x - river_center), 7.0)
		assert_gte(position.distance_to(spawn), 6.0)
		for other_index in range(index + 1, positions.size()):
			assert_gte(position.distance_to(positions[other_index]), 3.5)
