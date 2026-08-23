extends RefCounted

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


class StreamPoint:
	extends RefCounted

	var position: Vector3
	var half_width: float
	var depth: float

	func _init(point_position: Vector3, point_half_width: float, point_depth: float) -> void:
		position = point_position
		half_width = point_half_width
		depth = point_depth


class StreamBranch:
	extends RefCounted

	var curve: Curve3D
	var points: Array[StreamPoint]

	func _init(branch_curve: Curve3D, branch_points: Array[StreamPoint]) -> void:
		curve = branch_curve
		points = branch_points


const REGION_SIZE := 128
const HYDROLOGY_PADDING := 32
const HYDROLOGY_SIZE := REGION_SIZE + HYDROLOGY_PADDING * 2
const CHANNEL_FLOW_THRESHOLD := 1200.0
const MINIMUM_STREAM_HALF_WIDTH := 0.65
const MAXIMUM_STREAM_HALF_WIDTH := 2.5
const MINIMUM_STREAM_DEPTH := 0.4
const MAXIMUM_STREAM_DEPTH := 1.4
const BANK_SLOPE_WIDTH := 3.0
const WATER_SURFACE_OFFSET := 0.08
const DEPRESSION_SLOPE := 0.001
const CHANNEL_MINIMUM_DROP := 0.005
const CURVE_SUBDIVISIONS := 4
const MIN_CONTROL_TURN_DOT := 0.5
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
var _stream_branches: Array[StreamBranch] = []
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


func stream_branches() -> Array[StreamBranch]:
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

	var drainage_heights := _fill_depressions(raw_heights)
	var terrain_heights := _breach_depressions(raw_heights, drainage_heights)
	drainage_heights = _fill_depressions(terrain_heights)
	var downstream := _flow_directions(drainage_heights)
	var accumulation := _flow_accumulation(drainage_heights, downstream)
	var water_heights := _water_surface_heights(
		terrain_heights,
		drainage_heights,
		downstream,
		accumulation
	)
	var raw_segments := _build_stream_segments(water_heights, downstream, accumulation)
	_stream_branches = _build_stream_branches(raw_segments)
	_stream_segments = _flatten_stream_branches(_stream_branches)
	_build_terrain(terrain_heights)
	for _iteration in 2:
		_fit_stream_heights_to_banks(_stream_branches, terrain_heights)
		_stream_segments = _flatten_stream_branches(_stream_branches)
		_build_terrain(terrain_heights)
	_player_spawn = _find_player_spawn()


func _base_height_at(position: Vector2) -> float:
	var broad_hills := _terrain_noise.get_noise_2d(position.x, position.y) * 8.5
	var ground_detail := _detail_noise.get_noise_2d(position.x, position.y) * 1.5
	return 9.0 + broad_hills + ground_detail


func _fill_depressions(raw_heights: PackedFloat32Array) -> PackedFloat32Array:
	var filled := raw_heights.duplicate()
	var visited := PackedByteArray()
	visited.resize(filled.size())
	var heap: Array[int] = []
	for z in HYDROLOGY_SIZE:
		for x in HYDROLOGY_SIZE:
			if x != 0 and z != 0 and x != HYDROLOGY_SIZE - 1 and z != HYDROLOGY_SIZE - 1:
				continue
			var cell := z * HYDROLOGY_SIZE + x
			visited[cell] = 1
			_heap_push(heap, cell, filled)

	while not heap.is_empty():
		var cell := _heap_pop(heap, filled)
		var cell_x := cell % HYDROLOGY_SIZE
		var cell_z: int = cell / HYDROLOGY_SIZE
		for neighbor_z in range(maxi(0, cell_z - 1), mini(HYDROLOGY_SIZE - 1, cell_z + 1) + 1):
			for neighbor_x in range(maxi(0, cell_x - 1), mini(HYDROLOGY_SIZE - 1, cell_x + 1) + 1):
				var neighbor := neighbor_z * HYDROLOGY_SIZE + neighbor_x
				if visited[neighbor] == 1:
					continue
				visited[neighbor] = 1
				filled[neighbor] = maxf(filled[neighbor], filled[cell] + DEPRESSION_SLOPE)
				_heap_push(heap, neighbor, filled)
	return filled


func _breach_depressions(
	raw_heights: PackedFloat32Array,
	filled_heights: PackedFloat32Array
) -> PackedFloat32Array:
	var breached := raw_heights.duplicate()
	var raw_downstream := _flow_directions(raw_heights)
	var filled_downstream := _flow_directions(filled_heights)
	for z in range(1, HYDROLOGY_SIZE - 1):
		for x in range(1, HYDROLOGY_SIZE - 1):
			var sink := z * HYDROLOGY_SIZE + x
			if raw_downstream[sink] >= 0:
				continue
			if filled_heights[sink] <= raw_heights[sink] + DEPRESSION_SLOPE:
				continue
			_breach_sink(sink, breached, raw_heights, filled_downstream)
	return breached


func _breach_sink(
	sink: int,
	breached: PackedFloat32Array,
	raw_heights: PackedFloat32Array,
	downstream: PackedInt32Array
) -> void:
	var path := PackedInt32Array([sink])
	var distances := PackedFloat32Array([0.0])
	var cell := sink
	while downstream[cell] >= 0:
		var next := downstream[cell]
		var distance := distances[-1] + _world_position(cell).distance_to(_world_position(next))
		path.append(next)
		distances.append(distance)
		cell = next

	var path_length := distances[-1]
	if path_length <= 0.0:
		return
	var end_height := minf(
		raw_heights[path[-1]],
		raw_heights[sink] - CHANNEL_MINIMUM_DROP * path_length
	)
	for index in path.size():
		var target_height := lerpf(
			raw_heights[sink],
			end_height,
			distances[index] / path_length
		)
		breached[path[index]] = minf(breached[path[index]], target_height)


func _flow_directions(heights: PackedFloat32Array) -> PackedInt32Array:
	var downstream := PackedInt32Array()
	downstream.resize(heights.size())
	downstream.fill(-1)
	for z in range(1, HYDROLOGY_SIZE - 1):
		for x in range(1, HYDROLOGY_SIZE - 1):
			var cell := z * HYDROLOGY_SIZE + x
			var steepest_slope := 0.0
			for neighbor_z in range(z - 1, z + 2):
				for neighbor_x in range(x - 1, x + 2):
					if neighbor_x == x and neighbor_z == z:
						continue
					var neighbor := neighbor_z * HYDROLOGY_SIZE + neighbor_x
					var distance := Vector2(x, z).distance_to(Vector2(neighbor_x, neighbor_z))
					var slope := (heights[cell] - heights[neighbor]) / distance
					if slope > steepest_slope:
						steepest_slope = slope
						downstream[cell] = neighbor
	return downstream


func _flow_accumulation(
	heights: PackedFloat32Array,
	downstream: PackedInt32Array
) -> PackedFloat32Array:
	var accumulation := PackedFloat32Array()
	accumulation.resize(heights.size())
	accumulation.fill(1.0)
	for cell in _cells_by_height(heights):
		if downstream[cell] >= 0:
			accumulation[downstream[cell]] += accumulation[cell]
	return accumulation


func _water_surface_heights(
	terrain_heights: PackedFloat32Array,
	drainage_heights: PackedFloat32Array,
	downstream: PackedInt32Array,
	accumulation: PackedFloat32Array
) -> PackedFloat32Array:
	var water_heights := PackedFloat32Array()
	water_heights.resize(drainage_heights.size())
	water_heights.fill(INF)
	for cell in _cells_by_height(drainage_heights):
		if accumulation[cell] < CHANNEL_FLOW_THRESHOLD:
			continue
		if is_inf(water_heights[cell]):
			water_heights[cell] = terrain_heights[cell] - WATER_SURFACE_OFFSET
		var next := downstream[cell]
		if next >= 0:
			var descending_height := water_heights[cell] - CHANNEL_MINIMUM_DROP
			var natural_height := terrain_heights[next] - WATER_SURFACE_OFFSET
			water_heights[next] = minf(water_heights[next], minf(descending_height, natural_height))
	return water_heights


func _height_from_map(heights: PackedFloat32Array, position: Vector2) -> float:
	var map_position := position + Vector2(HYDROLOGY_PADDING, HYDROLOGY_PADDING)
	var x0 := clampi(floori(map_position.x), 0, HYDROLOGY_SIZE - 1)
	var z0 := clampi(floori(map_position.y), 0, HYDROLOGY_SIZE - 1)
	var x1 := mini(x0 + 1, HYDROLOGY_SIZE - 1)
	var z1 := mini(z0 + 1, HYDROLOGY_SIZE - 1)
	var x_blend := map_position.x - floorf(map_position.x)
	var z_blend := map_position.y - floorf(map_position.y)
	var top := lerpf(heights[z0 * HYDROLOGY_SIZE + x0], heights[z0 * HYDROLOGY_SIZE + x1], x_blend)
	var bottom := lerpf(heights[z1 * HYDROLOGY_SIZE + x0], heights[z1 * HYDROLOGY_SIZE + x1], x_blend)
	return lerpf(top, bottom, z_blend)


func _cells_by_height(heights: PackedFloat32Array) -> Array[int]:
	var cells: Array[int] = []
	cells.resize(heights.size())
	for cell in heights.size():
		cells[cell] = cell
	cells.sort_custom(
		func(first: int, second: int) -> bool: return heights[first] > heights[second]
	)
	return cells


func _build_stream_segments(
	water_heights: PackedFloat32Array,
	downstream: PackedInt32Array,
	accumulation: PackedFloat32Array
) -> Array[StreamSegment]:
	var segments: Array[StreamSegment] = []
	for cell in water_heights.size():
		var next := downstream[cell]
		if next < 0 or accumulation[cell] < CHANNEL_FLOW_THRESHOLD:
			continue
		var cell_position := _world_position(cell)
		var next_position := _world_position(next)
		if not _is_inside_world(cell_position) and not _is_inside_world(next_position):
			continue
		var start := Vector3(cell_position.x, water_heights[cell], cell_position.y)
		var end := Vector3(next_position.x, water_heights[next], next_position.y)
		segments.append(StreamSegment.new(
			start,
			end,
			_channel_half_width(accumulation[cell]),
			_channel_half_width(accumulation[next]),
			_channel_depth(accumulation[cell]),
			_channel_depth(accumulation[next])
		))
	return segments


func _build_stream_branches(segments: Array[StreamSegment]) -> Array[StreamBranch]:
	var outgoing: Dictionary[Vector3, StreamSegment] = {}
	var incoming_count: Dictionary[Vector3, int] = {}
	for segment in segments:
		outgoing[segment.start] = segment
		incoming_count[segment.end] = incoming_count.get(segment.end, 0) + 1

	var branches: Array[StreamBranch] = []
	for segment in segments:
		if incoming_count.get(segment.start, 0) == 1:
			continue
		branches.append(_trace_stream_branch(segment, outgoing, incoming_count))
	return branches


func _fit_stream_heights_to_banks(
	branches: Array[StreamBranch],
	terrain_heights: PackedFloat32Array
) -> void:
	for branch in branches:
		for index in branch.points.size():
			var point := branch.points[index]
			var previous: Vector3 = branch.points[maxi(0, index - 1)].position
			var following: Vector3 = branch.points[mini(branch.points.size() - 1, index + 1)].position
			var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
			var normal := Vector2(-tangent.y, tangent.x)
			var center := Vector2(point.position.x, point.position.z)
			var bank_distance := point.half_width + BANK_SLOPE_WIDTH
			point.position.y = minf(
				point.position.y,
				minf(
					_landscape_height_at(terrain_heights, center + normal * bank_distance),
					_landscape_height_at(terrain_heights, center - normal * bank_distance)
				) - WATER_SURFACE_OFFSET
			)

	for _iteration in branches.size() + 1:
		var junction_heights: Dictionary[Vector2, float] = {}
		for branch in branches:
			for point in [branch.points[0], branch.points[-1]]:
				var position := Vector2(point.position.x, point.position.z)
				junction_heights[position] = minf(
					junction_heights.get(position, INF),
					point.position.y
				)
		for branch in branches:
			var first_position := Vector2(branch.points[0].position.x, branch.points[0].position.z)
			branch.points[0].position.y = junction_heights[first_position]
			for index in range(1, branch.points.size()):
				var previous := branch.points[index - 1]
				var point := branch.points[index]
				var distance := Vector2(
					point.position.x - previous.position.x,
					point.position.z - previous.position.z
				).length()
				point.position.y = minf(
					point.position.y,
					previous.position.y - CHANNEL_MINIMUM_DROP * distance
				)


func _landscape_height_at(terrain_heights: PackedFloat32Array, position: Vector2) -> float:
	if _is_inside_world(position):
		return height_at(position)
	return _height_from_map(terrain_heights, position)


func _trace_stream_branch(
	first_segment: StreamSegment,
	outgoing: Dictionary[Vector3, StreamSegment],
	incoming_count: Dictionary[Vector3, int]
) -> StreamBranch:
	var control_points: Array[StreamPoint] = []
	var source_width := first_segment.start_half_width
	var source_position := Vector2(first_segment.start.x, first_segment.start.z)
	if incoming_count.get(first_segment.start, 0) == 0 and _is_inside_world(source_position, 1.0):
		source_width = 0.05
	control_points.append(StreamPoint.new(
		first_segment.start,
		source_width,
		first_segment.start_depth
	))
	var segment := first_segment
	while segment != null:
		control_points.append(StreamPoint.new(
			segment.end,
			segment.end_half_width,
			segment.end_depth
		))
		if incoming_count.get(segment.end, 0) != 1 or not outgoing.has(segment.end):
			break
		segment = outgoing[segment.end]
	return _smooth_stream_branch(control_points)


func _smooth_stream_branch(control_points: Array[StreamPoint]) -> StreamBranch:
	control_points = _remove_stream_hairpins(control_points)
	var curve := Curve3D.new()
	for point in control_points:
		curve.add_point(point.position)
	for index in control_points.size():
		var current := control_points[index].position
		var previous := control_points[maxi(0, index - 1)].position
		var following := control_points[mini(control_points.size() - 1, index + 1)].position
		var direction := following - previous
		direction.y = 0.0
		direction = direction.normalized()
		var incoming_length := Vector2(current.x, current.z).distance_to(Vector2(previous.x, previous.z))
		var outgoing_length := Vector2(current.x, current.z).distance_to(Vector2(following.x, following.z))
		curve.set_point_in(index, -direction * incoming_length / 3.0)
		curve.set_point_out(index, direction * outgoing_length / 3.0)

	var sampled_points: Array[StreamPoint] = []
	for segment_index in range(control_points.size() - 1):
		for step in CURVE_SUBDIVISIONS:
			var progress := step / float(CURVE_SUBDIVISIONS)
			var position := curve.sample(segment_index, progress)
			position.y = lerpf(
				control_points[segment_index].position.y,
				control_points[segment_index + 1].position.y,
				progress
			)
			sampled_points.append(StreamPoint.new(
				position,
				lerpf(
					control_points[segment_index].half_width,
					control_points[segment_index + 1].half_width,
					progress
				),
				lerpf(
					control_points[segment_index].depth,
					control_points[segment_index + 1].depth,
					progress
				)
			))
	sampled_points.append(control_points[-1])
	return StreamBranch.new(curve, sampled_points)


func _remove_stream_hairpins(control_points: Array[StreamPoint]) -> Array[StreamPoint]:
	var simplified: Array[StreamPoint] = control_points.duplicate()
	var index := 1
	while index < simplified.size() - 1:
		var previous: Vector3 = simplified[index - 1].position
		var current: Vector3 = simplified[index].position
		var following: Vector3 = simplified[index + 1].position
		var incoming := Vector2(current.x - previous.x, current.z - previous.z).normalized()
		var outgoing := Vector2(following.x - current.x, following.z - current.z).normalized()
		if incoming.dot(outgoing) < MIN_CONTROL_TURN_DOT:
			simplified.remove_at(index)
			index = maxi(1, index - 1)
		else:
			index += 1
	return simplified


func _flatten_stream_branches(branches: Array[StreamBranch]) -> Array[StreamSegment]:
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


func _build_terrain(drainage_heights: PackedFloat32Array) -> void:
	_terrain_heights.resize(REGION_SIZE * REGION_SIZE)
	for z in REGION_SIZE:
		for x in REGION_SIZE:
			var drainage_cell := (
				(z + HYDROLOGY_PADDING) * HYDROLOGY_SIZE + x + HYDROLOGY_PADDING
			)
			_terrain_heights[z * REGION_SIZE + x] = drainage_heights[drainage_cell]

	for segment in _stream_segments:
		_carve_segment(segment)


func _carve_segment(segment: StreamSegment) -> void:
	var start := Vector2(segment.start.x, segment.start.z)
	var end := Vector2(segment.end.x, segment.end.z)
	var delta := end - start
	var length_squared := delta.length_squared()
	var bank_radius := maxf(segment.start_half_width, segment.end_half_width) + BANK_SLOPE_WIDTH
	var minimum := Vector2(maxf(0.0, minf(start.x, end.x) - bank_radius), maxf(0.0, minf(start.y, end.y) - bank_radius))
	var maximum := Vector2(
		minf(REGION_SIZE - 1, maxf(start.x, end.x) + bank_radius),
		minf(REGION_SIZE - 1, maxf(start.y, end.y) + bank_radius)
	)
	for z in range(floori(minimum.y), ceili(maximum.y) + 1):
		for x in range(floori(minimum.x), ceili(maximum.x) + 1):
			var position := Vector2(x, z)
			var progress := clampf((position - start).dot(delta) / length_squared, 0.0, 1.0)
			var closest := start + delta * progress
			var half_width := lerpf(segment.start_half_width, segment.end_half_width, progress)
			var distance := position.distance_to(closest)
			if distance >= half_width + BANK_SLOPE_WIDTH:
				continue
			var water_height := lerpf(segment.start.y, segment.end.y, progress)
			var depth := lerpf(segment.start_depth, segment.end_depth, progress)
			var bed_height := water_height - depth
			var blend := smoothstep(half_width, half_width + BANK_SLOPE_WIDTH, distance)
			var terrain_cell := z * REGION_SIZE + x
			var carved_height := lerpf(bed_height, _terrain_heights[terrain_cell], blend)
			_terrain_heights[terrain_cell] = minf(_terrain_heights[terrain_cell], carved_height)


func _channel_half_width(flow: float) -> float:
	var scale := sqrt(flow / CHANNEL_FLOW_THRESHOLD) - 1.0
	return minf(MINIMUM_STREAM_HALF_WIDTH + scale * 0.25, MAXIMUM_STREAM_HALF_WIDTH)


func _channel_depth(flow: float) -> float:
	var scale := sqrt(flow / CHANNEL_FLOW_THRESHOLD) - 1.0
	return minf(MINIMUM_STREAM_DEPTH + scale * 0.2, MAXIMUM_STREAM_DEPTH)


func _find_player_spawn() -> Vector2:
	if _stream_segments.is_empty():
		return FALLBACK_PLAYER_SPAWN
	var world_center := Vector2(REGION_SIZE * 0.5, REGION_SIZE * 0.5)
	var best_spawn := FALLBACK_PLAYER_SPAWN
	var best_score := INF
	for segment in _stream_segments:
		var start := Vector2(segment.start.x, segment.start.z)
		var end := Vector2(segment.end.x, segment.end.z)
		var midpoint := (start + end) * 0.5
		var side := Vector2(-(end - start).y, (end - start).x).normalized() * 14.0
		var candidates: Array[Vector2] = [midpoint + side, midpoint - side]
		for candidate in candidates:
			if not _is_inside_world(candidate, 4.0):
				continue
			var clearance := _distance_to_stream(candidate)
			if clearance < 10.0 or clearance > 18.0:
				continue
			var score: float = candidate.distance_squared_to(world_center)
			if score < best_score:
				best_score = score
				best_spawn = candidate
	return best_spawn


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


func _world_position(cell: int) -> Vector2:
	return Vector2(
		cell % HYDROLOGY_SIZE - HYDROLOGY_PADDING,
		cell / HYDROLOGY_SIZE - HYDROLOGY_PADDING
	)


func _is_inside_world(position: Vector2, margin: float = 0.0) -> bool:
	return (
		position.x >= margin
		and position.y >= margin
		and position.x <= REGION_SIZE - 1 - margin
		and position.y <= REGION_SIZE - 1 - margin
	)


func _heap_push(heap: Array[int], cell: int, heights: PackedFloat32Array) -> void:
	heap.append(cell)
	var index := heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if heights[heap[parent]] <= heights[cell]:
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = cell


func _heap_pop(heap: Array[int], heights: PackedFloat32Array) -> int:
	var root := heap[0]
	var last: int = heap.pop_back()
	if heap.is_empty():
		return root
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and heights[heap[child + 1]] < heights[heap[child]]:
			child += 1
		if heights[last] <= heights[heap[child]]:
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return root
