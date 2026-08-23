extends RefCounted

const REGION_SIZE := 128
const STREAM_HALF_WIDTH := 2.0
const BANK_HALF_WIDTH := 6.0
const TREE_COUNT := 112
const TREE_MIN_DISTANCE := 3.5
const RIVER_TREE_CLEARANCE := 7.0
const FALLBACK_PLAYER_SPAWN := Vector2(16.0, 64.0)
const PLAYER_SPAWN_CLEARANCE := 6.0

const STREAM_START_Z := 4
const STREAM_END_Z := REGION_SIZE - 5
const STREAM_MIN_X := REGION_SIZE / 4
const STREAM_MAX_X := REGION_SIZE * 3 / 4
const STREAM_DEPTH := 0.65
const MINIMUM_FORCED_DROP := 0.01

var _terrain_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _world_seed: int
var _stream_path := PackedVector3Array()


func _init(world_seed: int, force_river_route: bool = true) -> void:
	_world_seed = world_seed
	_terrain_noise.seed = world_seed
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.012
	_terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_terrain_noise.fractal_octaves = 4
	_detail_noise.seed = world_seed + 1
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.055
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 3
	_stream_path = _build_stream_path(force_river_route)


func height_at(position: Vector2) -> float:
	var land_height := _base_height_at(position)
	if _stream_path.is_empty():
		return land_height

	var nearest_distance := INF
	var stream_height := 0.0
	for point in _stream_path:
		var distance := position.distance_to(Vector2(point.x, point.z))
		if distance < nearest_distance:
			nearest_distance = distance
			stream_height = point.y
	if nearest_distance >= BANK_HALF_WIDTH:
		return land_height

	var stream_bed := stream_height - STREAM_DEPTH
	var bank_blend := smoothstep(STREAM_HALF_WIDTH, BANK_HALF_WIDTH, nearest_distance)
	return lerpf(stream_bed, land_height, bank_blend)


func stream_path() -> PackedVector3Array:
	return _stream_path


func player_spawn() -> Vector2:
	if _stream_path.is_empty():
		return FALLBACK_PLAYER_SPAWN
	var crossing := _stream_path[_stream_path.size() / 2]
	return Vector2(crossing.x - 16.0, crossing.z)


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


func _base_height_at(position: Vector2) -> float:
	var broad_hills := _terrain_noise.get_noise_2d(position.x, position.y) * 4.0
	var ground_detail := _detail_noise.get_noise_2d(position.x, position.y) * 0.75
	var drainage_slope := lerpf(14.0, 0.0, position.y / float(REGION_SIZE - 1))
	return drainage_slope + broad_hills + ground_detail


func _build_stream_path(force_river_route: bool) -> PackedVector3Array:
	var route := _find_downhill_route()
	var requires_correction := route.is_empty()
	if requires_correction:
		if not force_river_route:
			return PackedVector3Array()
		route = _find_low_route()

	var path := PackedVector3Array()
	var water_height := _base_height_at(route[0]) - 0.1
	for position in route:
		var natural_height := _base_height_at(position) - 0.1
		if requires_correction:
			water_height = minf(natural_height, water_height - MINIMUM_FORCED_DROP)
		else:
			water_height = natural_height
		path.append(Vector3(position.x, water_height, position.y))
	return path


func _find_downhill_route() -> Array[Vector2]:
	var width := STREAM_MAX_X - STREAM_MIN_X + 1
	var previous_costs := PackedFloat32Array()
	previous_costs.resize(width)
	for index in width:
		previous_costs[index] = _base_height_at(Vector2(STREAM_MIN_X + index, STREAM_START_Z))

	var parent_rows: Array[PackedInt32Array] = []
	var first_parents := PackedInt32Array()
	first_parents.resize(width)
	first_parents.fill(-1)
	parent_rows.append(first_parents)
	for z in range(STREAM_START_Z + 1, STREAM_END_Z + 1):
		var current_costs := PackedFloat32Array()
		current_costs.resize(width)
		current_costs.fill(INF)
		var parents := PackedInt32Array()
		parents.resize(width)
		parents.fill(-1)
		for index in width:
			var x := STREAM_MIN_X + index
			var height := _base_height_at(Vector2(x, z))
			for previous_index in range(maxi(0, index - 2), mini(width - 1, index + 2) + 1):
				if is_inf(previous_costs[previous_index]):
					continue
				var previous_x := STREAM_MIN_X + previous_index
				var previous_height := _base_height_at(Vector2(previous_x, z - 1))
				if height > previous_height:
					continue
				var cost := previous_costs[previous_index] + height
				cost += absf(index - previous_index) * 0.03
				if cost < current_costs[index]:
					current_costs[index] = cost
					parents[index] = previous_index
		previous_costs = current_costs
		parent_rows.append(parents)

	var final_index := -1
	var final_cost := INF
	for index in width:
		if previous_costs[index] < final_cost:
			final_cost = previous_costs[index]
			final_index = index
	if final_index < 0:
		return []

	var route: Array[Vector2] = []
	route.resize(parent_rows.size())
	for row in range(parent_rows.size() - 1, -1, -1):
		route[row] = Vector2(STREAM_MIN_X + final_index, STREAM_START_Z + row)
		if row > 0:
			final_index = parent_rows[row][final_index]
	return route


func _find_low_route() -> Array[Vector2]:
	var route: Array[Vector2] = []
	var current_x := STREAM_MIN_X
	var lowest_height := INF
	for x in range(STREAM_MIN_X, STREAM_MAX_X + 1):
		var height := _base_height_at(Vector2(x, STREAM_START_Z))
		if height < lowest_height:
			lowest_height = height
			current_x = x
	route.append(Vector2(current_x, STREAM_START_Z))

	for z in range(STREAM_START_Z + 1, STREAM_END_Z + 1):
		var next_x := current_x
		var lowest_score := INF
		for candidate_x in range(
			maxi(STREAM_MIN_X, current_x - 2),
			mini(STREAM_MAX_X, current_x + 2) + 1
		):
			var position := Vector2(candidate_x, z)
			var turn_cost := absf(candidate_x - current_x) * 0.03
			var score := _base_height_at(position) + turn_cost
			if score < lowest_score:
				lowest_score = score
				next_x = candidate_x
		current_x = next_x
		route.append(Vector2(current_x, z))
	return route


func _is_valid_tree_position(candidate: Vector2, existing_positions: Array[Vector2]) -> bool:
	for point in _stream_path:
		if candidate.distance_to(Vector2(point.x, point.z)) < RIVER_TREE_CLEARANCE:
			return false
	if candidate.distance_to(player_spawn()) < PLAYER_SPAWN_CLEARANCE:
		return false
	for existing_position in existing_positions:
		if candidate.distance_to(existing_position) < TREE_MIN_DISTANCE:
			return false
	return true
