extends GutTest

const GENERATOR_PATH := "res://world/world_generator.gd"


func test_seed_repeats_generated_world() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var first: RefCounted = generator_script.new(481516, true)
	var repeated: RefCounted = generator_script.new(481516, true)
	var changed: RefCounted = generator_script.new(108, true)
	var sample := Vector2(25.5, 73.25)

	assert_eq(first.call("height_at", sample), repeated.call("height_at", sample))
	assert_ne(first.call("height_at", sample), changed.call("height_at", sample))
	assert_eq(first.call("stream_path"), repeated.call("stream_path"))
	assert_ne(first.call("stream_path"), changed.call("stream_path"))
	assert_eq(first.call("tree_positions"), repeated.call("tree_positions"))
	assert_ne(first.call("tree_positions"), changed.call("tree_positions"))


func test_terrain_has_large_scale_relief() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516, true)
	var lowest := INF
	var highest := -INF
	for x in range(0, 128, 4):
		for z in range(0, 128, 4):
			var height := generator.call("height_at", Vector2(x, z)) as float
			lowest = minf(lowest, height)
			highest = maxf(highest, height)

	assert_gte(highest - lowest, 8.0)


func test_forced_stream_crosses_world_and_has_a_carved_bed() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516, true)
	var path := generator.call("stream_path") as PackedVector3Array

	assert_gte(path.size(), 120)
	assert_lte(path[0].z, 4.0)
	assert_gte(path[-1].z, 123.0)
	for point in path:
		assert_lt(generator.call("height_at", Vector2(point.x, point.z)), point.y)


func test_unforced_stream_does_not_correct_an_uphill_route() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var forced: RefCounted = generator_script.new(4, true)
	var natural: RefCounted = generator_script.new(4, false)

	assert_false((forced.call("stream_path") as PackedVector3Array).is_empty())
	assert_true((natural.call("stream_path") as PackedVector3Array).is_empty())


func test_default_seed_has_a_natural_stream_route() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var forced: RefCounted = generator_script.new(481516, true)
	var natural: RefCounted = generator_script.new(481516, false)

	assert_false((natural.call("stream_path") as PackedVector3Array).is_empty())
	assert_eq(natural.call("stream_path"), forced.call("stream_path"))


func test_player_spawns_near_but_not_inside_stream() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516, true)
	var path := generator.call("stream_path") as PackedVector3Array
	var spawn := generator.call("player_spawn") as Vector2

	assert_gte(_distance_to_stream(spawn, path), 10.0)
	assert_lte(_distance_to_stream(spawn, path), 18.0)


func test_trees_respect_world_clearances() -> void:
	var generator_script := load(GENERATOR_PATH) as GDScript
	var generator: RefCounted = generator_script.new(481516, true)
	var positions := generator.call("tree_positions") as Array
	var path := generator.call("stream_path") as PackedVector3Array
	var spawn := generator.call("player_spawn") as Vector2

	assert_eq(positions.size(), 112)
	for index in positions.size():
		var position := positions[index] as Vector2
		assert_gte(position.x, 4.0)
		assert_lte(position.x, 124.0)
		assert_gte(position.y, 4.0)
		assert_lte(position.y, 124.0)
		assert_gte(_distance_to_stream(position, path), 7.0)
		assert_gte(position.distance_to(spawn), 6.0)
		for other_index in range(index + 1, positions.size()):
			assert_gte(position.distance_to(positions[other_index]), 3.5)


func _distance_to_stream(position: Vector2, path: PackedVector3Array) -> float:
	var distance := INF
	for point in path:
		distance = minf(distance, position.distance_to(Vector2(point.x, point.z)))
	return distance
