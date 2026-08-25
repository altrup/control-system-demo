extends RefCounted

const RiverNetwork := preload("res://world/river_network.gd")
const RiverCarver := preload("res://world/river_carver.gd")
const RiverParameters := preload("res://world/river_parameters.gd")
const TerrainElevation := preload("res://world/terrain_elevation.gd")

const DEFAULT_SEED := 22


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
const TERRAIN_SAMPLE_SPACING := 0.5
const TERRAIN_SAMPLE_SIZE := 512
const HYDROLOGY_SAMPLE_SPACING := 4.0
const HYDROLOGY_PADDING := 896
const HYDROLOGY_SIZE := 512
const WORLD_MIN := REGION_SIZE * -0.5
const WORLD_MAX := WORLD_MIN + REGION_SIZE
const FULL_DOMAIN_SIZE := REGION_SIZE + HYDROLOGY_PADDING * 2
const FULL_DOMAIN_MIN := FULL_DOMAIN_SIZE * -0.5
const FULL_TERRAIN_SAMPLE_SPACING := 2.0
const FULL_TERRAIN_SAMPLE_SIZE := roundi(
	FULL_DOMAIN_SIZE / FULL_TERRAIN_SAMPLE_SPACING
)
const TREE_DENSITY := 112.0 / (128.0 * 128.0)
const TREE_MIN_DISTANCE := 3.5
const RIVER_TREE_CLEARANCE := 7.0
const FALLBACK_PLAYER_SPAWN := Vector2(-96.0, 0.0)
const PLAYER_SPAWN_CLEARANCE := 6.0

var _terrain_elevation: TerrainElevation
var _world_seed: int
var _river_parameters: RiverParameters
var _full_domain: bool
var _terrain_size: int
var _terrain_min: float
var _terrain_sample_size: int
var _terrain_sample_spacing: float
var _terrain_heights := PackedFloat32Array()
var _valley_heights := PackedFloat32Array()
var _stream_segments: Array[StreamSegment] = []
var _stream_branches: Array[RiverNetwork.ChannelBranch] = []
var _player_spawn := FALLBACK_PLAYER_SPAWN


func _init(
	world_seed: int,
	river_parameters: RiverParameters = null,
	full_domain: bool = false
) -> void:
	_world_seed = world_seed
	_full_domain = full_domain
	_terrain_size = FULL_DOMAIN_SIZE if full_domain else REGION_SIZE
	_terrain_min = FULL_DOMAIN_MIN if full_domain else WORLD_MIN
	_terrain_sample_size = (
		FULL_TERRAIN_SAMPLE_SIZE if full_domain else TERRAIN_SAMPLE_SIZE
	)
	_terrain_sample_spacing = (
		FULL_TERRAIN_SAMPLE_SPACING if full_domain else TERRAIN_SAMPLE_SPACING
	)
	_river_parameters = (
		river_parameters if river_parameters != null else RiverParameters.new()
	)
	_terrain_elevation = TerrainElevation.new(world_seed)
	_generate_landscape()


func height_at(position: Vector2) -> float:
	if position.x < _terrain_min or position.y < _terrain_min:
		return _base_height_at(position)
	var terrain_max := _terrain_min + _terrain_size
	if (
		position.x > terrain_max - _terrain_sample_spacing
		or position.y > terrain_max - _terrain_sample_spacing
	):
		return _base_height_at(position)

	var grid_position := (
		(position - Vector2.ONE * _terrain_min) / _terrain_sample_spacing
	)
	var x0 := floori(grid_position.x)
	var z0 := floori(grid_position.y)
	var x1 := mini(x0 + 1, _terrain_sample_size - 1)
	var z1 := mini(z0 + 1, _terrain_sample_size - 1)
	var x_blend := grid_position.x - x0
	var z_blend := grid_position.y - z0
	var top := lerpf(_terrain_height(x0, z0), _terrain_height(x1, z0), x_blend)
	var bottom := lerpf(_terrain_height(x0, z1), _terrain_height(x1, z1), x_blend)
	return lerpf(top, bottom, z_blend)


func stream_segments() -> Array[StreamSegment]:
	return _stream_segments


func stream_branches() -> Array[RiverNetwork.ChannelBranch]:
	return _stream_branches


func player_spawn() -> Vector2:
	return _player_spawn


func terrain_size() -> int:
	return _terrain_size


func terrain_min() -> float:
	return _terrain_min


func terrain_sample_size() -> int:
	return _terrain_sample_size


func terrain_sample_spacing() -> float:
	return _terrain_sample_spacing


func tree_positions() -> Array[Vector2]:
	var random := RandomNumberGenerator.new()
	random.seed = _world_seed
	var positions: Array[Vector2] = []
	var target_count := tree_count_for_region_size(REGION_SIZE)
	var attempts := 0
	while positions.size() < target_count and attempts < target_count * 100:
		attempts += 1
		var candidate := Vector2(
			random.randf_range(WORLD_MIN + 4.0, WORLD_MAX - 4.0),
			random.randf_range(WORLD_MIN + 4.0, WORLD_MAX - 4.0)
		)
		if _is_valid_tree_position(candidate, positions):
			positions.append(candidate)
	return positions


func is_ocean(position: Vector2) -> bool:
	return _terrain_elevation.is_ocean(position)


func has_ocean_surface_at(position: Vector2) -> bool:
	return is_ocean(position) or height_at(position) < sea_level()


func sea_level() -> float:
	return TerrainElevation.SEA_LEVEL


static func tree_count_for_region_size(region_size: int) -> int:
	return roundi(region_size * region_size * TREE_DENSITY)


func _generate_landscape() -> void:
	var raw_heights := PackedFloat32Array()
	raw_heights.resize(HYDROLOGY_SIZE * HYDROLOGY_SIZE)
	for z in HYDROLOGY_SIZE:
		for x in HYDROLOGY_SIZE:
			var position := (
				Vector2(x, z) * HYDROLOGY_SAMPLE_SPACING
				+ Vector2.ONE * FULL_DOMAIN_MIN
			)
			raw_heights[z * HYDROLOGY_SIZE + x] = _base_height_at(position)

	var network := RiverNetwork.new(
		REGION_SIZE,
		HYDROLOGY_PADDING,
		_river_parameters,
		HYDROLOGY_SAMPLE_SPACING
	)
	_valley_heights = network.erode_valleys(raw_heights)
	_stream_branches = (
		network.build_full_domain(_valley_heights)
		if _full_domain
		else network.build(_valley_heights)
	)
	_stream_segments = _flatten_stream_branches(_stream_branches)
	_build_terrain()
	_player_spawn = _find_player_spawn()


func _base_height_at(position: Vector2) -> float:
	return _terrain_elevation.height_at(position)


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


func _build_terrain() -> void:
	_terrain_heights.resize(_terrain_sample_size * _terrain_sample_size)
	for z in _terrain_sample_size:
		for x in _terrain_sample_size:
			var position := (
				Vector2(x, z) * _terrain_sample_spacing
				+ Vector2.ONE * _terrain_min
			)
			_terrain_heights[z * _terrain_sample_size + x] = _valley_height_at(position)
	_terrain_heights = RiverCarver.new(
		_terrain_size, _terrain_sample_spacing
	).carve(_terrain_heights, _stream_branches)


func _find_player_spawn() -> Vector2:
	var world_center := Vector2.ZERO
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
			if is_ocean(candidate) or height_at(candidate) <= sea_level() + 0.5:
				continue
			var clearance := _distance_to_stream(candidate)
			if clearance >= 10.0 and clearance <= 18.0:
				return candidate
	return _find_dry_fallback_spawn()


func _is_valid_tree_position(candidate: Vector2, existing_positions: Array[Vector2]) -> bool:
	if is_ocean(candidate) or height_at(candidate) <= sea_level() + 0.3:
		return false
	if _terrain_slope(candidate) > 1.0:
		return false
	if _distance_to_stream(candidate) < RIVER_TREE_CLEARANCE:
		return false
	if candidate.distance_to(player_spawn()) < PLAYER_SPAWN_CLEARANCE:
		return false
	for existing_position in existing_positions:
		if candidate.distance_to(existing_position) < TREE_MIN_DISTANCE:
			return false
	return true


func _find_dry_fallback_spawn() -> Vector2:
	var best := FALLBACK_PLAYER_SPAWN
	var best_distance := INF
	for z in range(floori(WORLD_MIN + 4.0), ceili(WORLD_MAX - 4.0), 4):
		for x in range(floori(WORLD_MIN + 4.0), ceili(WORLD_MAX - 4.0), 4):
			var candidate := Vector2(x, z)
			if is_ocean(candidate) or height_at(candidate) <= sea_level() + 0.5:
				continue
			if _terrain_slope(candidate) > 1.0:
				continue
			var distance := candidate.distance_squared_to(FALLBACK_PLAYER_SPAWN)
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best


func _terrain_slope(position: Vector2) -> float:
	return maxf(
		absf(height_at(position + Vector2.RIGHT) - height_at(position + Vector2.LEFT)) * 0.5,
		absf(height_at(position + Vector2.DOWN) - height_at(position + Vector2.UP)) * 0.5
	)


func _distance_to_stream(position: Vector2) -> float:
	var distance := INF
	for segment in _stream_segments:
		var start := Vector2(segment.start.x, segment.start.z)
		var end := Vector2(segment.end.x, segment.end.z)
		var closest := Geometry2D.get_closest_point_to_segment(position, start, end)
		distance = minf(distance, position.distance_to(closest))
	return distance


func _terrain_height(x: int, z: int) -> float:
	return _terrain_heights[z * _terrain_sample_size + x]


func _valley_height_at(position: Vector2) -> float:
	var grid_position := (
		position - Vector2.ONE * FULL_DOMAIN_MIN
	) / HYDROLOGY_SAMPLE_SPACING
	var x0 := clampi(floori(grid_position.x), 0, HYDROLOGY_SIZE - 1)
	var z0 := clampi(floori(grid_position.y), 0, HYDROLOGY_SIZE - 1)
	var x1 := mini(x0 + 1, HYDROLOGY_SIZE - 1)
	var z1 := mini(z0 + 1, HYDROLOGY_SIZE - 1)
	var x_blend := clampf(grid_position.x - x0, 0.0, 1.0)
	var z_blend := clampf(grid_position.y - z0, 0.0, 1.0)
	var top := lerpf(
		_valley_heights[z0 * HYDROLOGY_SIZE + x0],
		_valley_heights[z0 * HYDROLOGY_SIZE + x1],
		x_blend
	)
	var bottom := lerpf(
		_valley_heights[z1 * HYDROLOGY_SIZE + x0],
		_valley_heights[z1 * HYDROLOGY_SIZE + x1],
		x_blend
	)
	return lerpf(top, bottom, z_blend)


func _is_inside_world(position: Vector2, margin: float = 0.0) -> bool:
	return (
		position.x >= WORLD_MIN + margin
		and position.y >= WORLD_MIN + margin
		and position.x <= WORLD_MAX - 1.0 - margin
		and position.y <= WORLD_MAX - 1.0 - margin
	)
