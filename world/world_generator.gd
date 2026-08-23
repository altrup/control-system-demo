extends RefCounted

const RiverNetwork := preload("res://world/river_network.gd")
const RiverCarver := preload("res://world/river_carver.gd")


class StreamSegment:
	extends RefCounted

	var start: Vector3
	var end: Vector3
	var start_half_width: float
	var end_half_width: float
	var start_depth: float
	var end_depth: float

	func _init(
		segment_start: Vector3,
		segment_end: Vector3,
		segment_start_half_width: float,
		segment_end_half_width: float,
		segment_start_depth: float,
		segment_end_depth: float
	) -> void:
		start = segment_start
		end = segment_end
		start_half_width = segment_start_half_width
		end_half_width = segment_end_half_width
		start_depth = segment_start_depth
		end_depth = segment_end_depth


const REGION_SIZE := 256
const HYDROLOGY_PADDING := 256
const HYDROLOGY_SIZE := REGION_SIZE + HYDROLOGY_PADDING * 2
const CHANNEL_FLOW_THRESHOLD := 4096.0
const TREE_COUNT := 112
const TREE_MIN_DISTANCE := 3.5
const RIVER_TREE_CLEARANCE := 7.0
const FALLBACK_PLAYER_SPAWN := Vector2(16.0, 64.0)
const PLAYER_SPAWN_CLEARANCE := 6.0

var _terrain_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _world_seed: int
var _terrain_heights := PackedFloat32Array()
var _stream_segments: Array[StreamSegment] = []
var _stream_branches: Array[RiverNetwork.ChannelBranch] = []
var _player_spawn := FALLBACK_PLAYER_SPAWN


func _init(world_seed: int) -> void:
	_world_seed = world_seed
	_terrain_noise.seed = world_seed
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.011
	_terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_terrain_noise.fractal_octaves = 5
	_detail_noise.seed = world_seed + 1
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.045
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 3
	_generate_landscape()


func height_at(position: Vector2) -> float:
	if position.x < 0.0 or position.y < 0.0:
		return _base_height_at(position)
	if position.x > REGION_SIZE - 1 or position.y > REGION_SIZE - 1:
		return _base_height_at(position)

	var x0 := floori(position.x)
	var z0 := floori(position.y)
	var x1 := mini(x0 + 1, REGION_SIZE - 1)
	var z1 := mini(z0 + 1, REGION_SIZE - 1)
	var x_blend := position.x - x0
	var z_blend := position.y - z0
	var top := lerpf(_terrain_height(x0, z0), _terrain_height(x1, z0), x_blend)
	var bottom := lerpf(_terrain_height(x0, z1), _terrain_height(x1, z1), x_blend)
	return lerpf(top, bottom, z_blend)


func stream_segments() -> Array[StreamSegment]:
	return _stream_segments


func stream_branches() -> Array[RiverNetwork.ChannelBranch]:
	return _stream_branches


func player_spawn() -> Vector2:
	return _player_spawn


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


func _generate_landscape() -> void:
	var raw_heights := PackedFloat32Array()
	raw_heights.resize(HYDROLOGY_SIZE * HYDROLOGY_SIZE)
	for z in HYDROLOGY_SIZE:
		for x in HYDROLOGY_SIZE:
			var position := Vector2(x - HYDROLOGY_PADDING, z - HYDROLOGY_PADDING)
			raw_heights[z * HYDROLOGY_SIZE + x] = _base_height_at(position)

	var network := RiverNetwork.new(REGION_SIZE, HYDROLOGY_PADDING, CHANNEL_FLOW_THRESHOLD)
	_stream_branches = network.build(raw_heights)
	_stream_segments = _flatten_stream_branches(_stream_branches)
	_build_terrain(raw_heights)
	_player_spawn = _find_player_spawn()


func _base_height_at(position: Vector2) -> float:
	var broad_hills := _terrain_noise.get_noise_2d(position.x, position.y) * 8.5
	var ground_detail := _detail_noise.get_noise_2d(position.x, position.y) * 1.5
	return 9.0 + broad_hills + ground_detail


func _flatten_stream_branches(
	branches: Array[RiverNetwork.ChannelBranch]
) -> Array[StreamSegment]:
	var segments: Array[StreamSegment] = []
	for branch in branches:
		for index in range(branch.points.size() - 1):
			var start := branch.points[index]
			var end := branch.points[index + 1]
			segments.append(StreamSegment.new(
				start.position,
				end.position,
				start.half_width,
				end.half_width,
				start.depth,
				end.depth
			))
	return segments


func _build_terrain(base_heights: PackedFloat32Array) -> void:
	_terrain_heights.resize(REGION_SIZE * REGION_SIZE)
	for z in REGION_SIZE:
		for x in REGION_SIZE:
			var hydrology_cell := (
				(z + HYDROLOGY_PADDING) * HYDROLOGY_SIZE + x + HYDROLOGY_PADDING
			)
			_terrain_heights[z * REGION_SIZE + x] = base_heights[hydrology_cell]
	_terrain_heights = RiverCarver.new(REGION_SIZE).carve(_terrain_heights, _stream_branches)


func _find_player_spawn() -> Vector2:
	if _stream_segments.is_empty():
		return FALLBACK_PLAYER_SPAWN
	var world_center := Vector2(REGION_SIZE * 0.5, REGION_SIZE * 0.5)
	var nearby_segments: Array[StreamSegment] = _stream_segments.duplicate()
	nearby_segments.sort_custom(func(first: StreamSegment, second: StreamSegment) -> bool:
		var first_midpoint := Vector2(
			(first.start.x + first.end.x) * 0.5,
			(first.start.z + first.end.z) * 0.5
		)
		var second_midpoint := Vector2(
			(second.start.x + second.end.x) * 0.5,
			(second.start.z + second.end.z) * 0.5
		)
		var first_score := first_midpoint.distance_squared_to(world_center)
		var second_score := second_midpoint.distance_squared_to(world_center)
		if not is_equal_approx(first_score, second_score):
			return first_score < second_score
		if not is_equal_approx(first.start.x, second.start.x):
			return first.start.x < second.start.x
		return first.start.z < second.start.z
	)
	for segment in nearby_segments:
		var start := Vector2(segment.start.x, segment.start.z)
		var end := Vector2(segment.end.x, segment.end.z)
		var midpoint := (start + end) * 0.5
		var side := Vector2(-(end - start).y, (end - start).x).normalized() * 14.0
		for candidate in [midpoint + side, midpoint - side]:
			if not _is_inside_world(candidate, 4.0):
				continue
			var clearance := _distance_to_stream(candidate)
			if clearance >= 10.0 and clearance <= 18.0:
				return candidate
	return FALLBACK_PLAYER_SPAWN


func _is_valid_tree_position(candidate: Vector2, existing_positions: Array[Vector2]) -> bool:
	if _distance_to_stream(candidate) < RIVER_TREE_CLEARANCE:
		return false
	if candidate.distance_to(player_spawn()) < PLAYER_SPAWN_CLEARANCE:
		return false
	for existing_position in existing_positions:
		if candidate.distance_to(existing_position) < TREE_MIN_DISTANCE:
			return false
	return true


func _distance_to_stream(position: Vector2) -> float:
	var distance := INF
	for segment in _stream_segments:
		var start := Vector2(segment.start.x, segment.start.z)
		var end := Vector2(segment.end.x, segment.end.z)
		var closest := Geometry2D.get_closest_point_to_segment(position, start, end)
		distance = minf(distance, position.distance_to(closest))
	return distance


func _terrain_height(x: int, z: int) -> float:
	return _terrain_heights[z * REGION_SIZE + x]


func _is_inside_world(position: Vector2, margin: float = 0.0) -> bool:
	return (
		position.x >= margin
		and position.y >= margin
		and position.x <= REGION_SIZE - 1 - margin
		and position.y <= REGION_SIZE - 1 - margin
	)
