extends RefCounted

const REGION_SIZE := 64
const WATER_LEVEL := 0.25
const STREAM_HALF_WIDTH := 2.25
const BANK_HALF_WIDTH := 5.5
const TREE_COUNT := 28
const TREE_MIN_DISTANCE := 3.5
const RIVER_TREE_CLEARANCE := 7.0
const PLAYER_SPAWN := Vector2(12.0, 32.0)
const PLAYER_SPAWN_CLEARANCE := 6.0

var _terrain_noise := FastNoiseLite.new()
var _world_seed: int


func _init(world_seed: int) -> void:
	_world_seed = world_seed
	_terrain_noise.seed = world_seed
	_terrain_noise.frequency = 0.035


func height_at(position: Vector2) -> float:
	var variation := _terrain_noise.get_noise_2d(position.x, position.y)
	var land_height := 2.0 + variation
	var river_distance := absf(position.x - _river_center_x(position.y))
	if river_distance >= BANK_HALF_WIDTH:
		return land_height

	var stream_height := -0.65 + variation * 0.1
	var bank_blend := smoothstep(STREAM_HALF_WIDTH, BANK_HALF_WIDTH, river_distance)
	return lerpf(stream_height, land_height, bank_blend)


func _river_center_x(z: float) -> float:
	return REGION_SIZE * 0.5 + sin((z - REGION_SIZE * 0.5) * TAU / REGION_SIZE) * 2.5


func tree_positions() -> Array[Vector2]:
	var random := RandomNumberGenerator.new()
	random.seed = _world_seed
	var positions: Array[Vector2] = []
	var attempts := 0
	while positions.size() < TREE_COUNT and attempts < TREE_COUNT * 100:
		attempts += 1
		var candidate := Vector2(
			random.randf_range(4.0, REGION_SIZE - 4.0),
			random.randf_range(4.0, REGION_SIZE - 4.0)
		)
		if _is_valid_tree_position(candidate, positions):
			positions.append(candidate)
	return positions


func _is_valid_tree_position(candidate: Vector2, existing_positions: Array[Vector2]) -> bool:
	if absf(candidate.x - _river_center_x(candidate.y)) < RIVER_TREE_CLEARANCE:
		return false
	if candidate.distance_to(PLAYER_SPAWN) < PLAYER_SPAWN_CLEARANCE:
		return false
	for existing_position in existing_positions:
		if candidate.distance_to(existing_position) < TREE_MIN_DISTANCE:
			return false
	return true
