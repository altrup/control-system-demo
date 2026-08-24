extends RefCounted

const RiverParameters := preload("res://world/river_parameters.gd")

class ChannelPoint:
	extends RefCounted

	var position: Vector3
	var accumulated_area: float
	var half_width: float
	var depth: float
	var bank_falloff: float

	func _init(point_position: Vector3, area: float, dimensions: Vector3) -> void:
		position = point_position
		accumulated_area = area
		half_width = dimensions.x * 0.5
		depth = dimensions.y
		bank_falloff = dimensions.z


class ChannelBranch:
	extends RefCounted

	var points: Array[ChannelPoint]

	func _init(branch_points: Array[ChannelPoint]) -> void:
		points = branch_points


const DEPRESSION_SLOPE := 0.001
const WATER_SURFACE_OFFSET := 0.08
const CHANNEL_MINIMUM_DROP := 0.005

var _region_size: int
var _padding: int
var _grid_size: int
var _parameters: RiverParameters


func _init(region_size: int, padding: int, parameters: RiverParameters = null) -> void:
	_region_size = region_size
	_padding = padding
	_grid_size = region_size + padding * 2
	_parameters = parameters if parameters != null else RiverParameters.new()


func build(base_heights: PackedFloat32Array) -> Array[ChannelBranch]:
	if base_heights.size() != _grid_size * _grid_size:
		push_error("River height map dimensions do not match the generation domain.")
		return []

	var ascending_cells: Array[int] = []
	var routing_heights := _fill_depressions(base_heights, ascending_cells)
	var downstream := _flow_directions(routing_heights)
	ascending_cells.reverse()
	var accumulation := _flow_accumulation(downstream, ascending_cells)
	var retained: Dictionary[int, bool] = {}
	var water_heights: Dictionary[int, float] = {}
	for cell in downstream.size():
		var next := downstream[cell]
		if (
			next >= 0
			and accumulation[cell] >= _parameters.channel_threshold
			and not _is_inside(cell)
			and _is_inside(next)
		):
			_retain_crossing(cell, base_heights, downstream, accumulation, retained, water_heights)
	return _build_branches(retained, water_heights, downstream, accumulation)


func dimensions_for_area(area: float) -> Vector3:
	var ratio := maxf(area / _parameters.channel_threshold, 1.0)
	var minimum_width := minf(_parameters.minimum_width, _parameters.maximum_width)
	var maximum_width := maxf(_parameters.minimum_width, _parameters.maximum_width)
	var minimum_depth := minf(_parameters.minimum_depth, _parameters.maximum_depth)
	var maximum_depth := maxf(_parameters.minimum_depth, _parameters.maximum_depth)
	var minimum_bank := minf(
		_parameters.minimum_bank_falloff,
		_parameters.maximum_bank_falloff
	)
	var maximum_bank := maxf(
		_parameters.minimum_bank_falloff,
		_parameters.maximum_bank_falloff
	)
	var depth := clampf(
		minimum_depth * pow(ratio, 0.2),
		minimum_depth,
		maximum_depth
	)
	return Vector3(
		clampf(
			minimum_width * pow(ratio, 0.3),
			minimum_width,
			maximum_width
		),
		depth,
		clampf(depth * 4.0, minimum_bank, maximum_bank)
	)


func _retain_crossing(
	entry: int,
	base_heights: PackedFloat32Array,
	downstream: PackedInt32Array,
	accumulation: PackedFloat32Array,
	retained: Dictionary[int, bool],
	water_heights: Dictionary[int, float]
) -> void:
	var cells: Array[int] = [entry]
	var cell := entry
	var exited := false
	while downstream[cell] >= 0 and accumulation[cell] >= _parameters.channel_threshold:
		var next := downstream[cell]
		cells.append(next)
		if _is_inside(cell) and not _is_inside(next):
			exited = true
			break
		cell = next
	if not exited:
		return

	var surfaces := PackedFloat32Array()
	surfaces.resize(cells.size())
	var surface := base_heights[cells[0]] - WATER_SURFACE_OFFSET
	var maximum_cut := 0.0
	for index in cells.size():
		if index > 0:
			var distance := _cell_position(cells[index - 1]).distance_to(_cell_position(cells[index]))
			surface = minf(
				base_heights[cells[index]] - WATER_SURFACE_OFFSET,
				surface - CHANNEL_MINIMUM_DROP * distance
			)
		var grade_cut := base_heights[cells[index]] - WATER_SURFACE_OFFSET - surface
		maximum_cut = maxf(maximum_cut, grade_cut)
		surfaces[index] = surface
	if maximum_cut > _parameters.maximum_centerline_cut:
		return

	for index in range(cells.size() - 1):
		retained[cells[index]] = true
	for index in cells.size():
		water_heights[cells[index]] = minf(water_heights.get(cells[index], INF), surfaces[index])


func _build_branches(
	retained: Dictionary[int, bool],
	water_heights: Dictionary[int, float],
	downstream: PackedInt32Array,
	accumulation: PackedFloat32Array
) -> Array[ChannelBranch]:
	var incoming_count: Dictionary[int, int] = {}
	for cell in retained:
		var next := downstream[cell]
		incoming_count[next] = incoming_count.get(next, 0) + 1

	var branches: Array[ChannelBranch] = []
	for cell in retained:
		if incoming_count.get(cell, 0) == 1:
			continue
		var points: Array[ChannelPoint] = []
		var current: int = cell
		while true:
			points.append(_make_point(current, water_heights, accumulation))
			if not retained.has(current):
				break
			var next := downstream[current]
			if incoming_count.get(next, 0) != 1:
				points.append(_make_point(next, water_heights, accumulation))
				break
			current = next
		_smooth_branch(points)
		branches.append(ChannelBranch.new(points))
	return branches


func _make_point(
	cell: int,
	water_heights: Dictionary[int, float],
	accumulation: PackedFloat32Array
) -> ChannelPoint:
	var horizontal := _cell_position(cell)
	return ChannelPoint.new(
		Vector3(horizontal.x, water_heights[cell], horizontal.y),
		accumulation[cell],
		dimensions_for_area(accumulation[cell])
	)


func _smooth_branch(points: Array[ChannelPoint]) -> void:
	var positions: Array[Vector3] = []
	for point in points:
		positions.append(point.position)
	for index in range(1, points.size() - 1):
		var smoothed := (positions[index - 1] + positions[index] * 2.0 + positions[index + 1]) * 0.25
		points[index].position.x = smoothed.x
		points[index].position.z = smoothed.z


func _fill_depressions(
	base_heights: PackedFloat32Array,
	ascending_cells: Array[int]
) -> PackedFloat32Array:
	var filled := base_heights.duplicate()
	var visited := PackedByteArray()
	visited.resize(filled.size())
	var heap: Array[int] = []
	for z in _grid_size:
		for x in _grid_size:
			if x != 0 and z != 0 and x != _grid_size - 1 and z != _grid_size - 1:
				continue
			var cell := z * _grid_size + x
			visited[cell] = 1
			_heap_push(heap, cell, filled)

	while not heap.is_empty():
		var cell := _heap_pop(heap, filled)
		ascending_cells.append(cell)
		var cell_x := cell % _grid_size
		var cell_z: int = cell / _grid_size
		for neighbor_z in range(maxi(0, cell_z - 1), mini(_grid_size - 1, cell_z + 1) + 1):
			for neighbor_x in range(maxi(0, cell_x - 1), mini(_grid_size - 1, cell_x + 1) + 1):
				var neighbor := neighbor_z * _grid_size + neighbor_x
				if visited[neighbor] == 1:
					continue
				visited[neighbor] = 1
				filled[neighbor] = maxf(filled[neighbor], filled[cell] + DEPRESSION_SLOPE)
				_heap_push(heap, neighbor, filled)
	return filled


func _flow_directions(heights: PackedFloat32Array) -> PackedInt32Array:
	var downstream := PackedInt32Array()
	downstream.resize(heights.size())
	downstream.fill(-1)
	for z in range(1, _grid_size - 1):
		for x in range(1, _grid_size - 1):
			var cell := z * _grid_size + x
			var steepest_slope := 0.0
			for neighbor_z in range(z - 1, z + 2):
				for neighbor_x in range(x - 1, x + 2):
					if neighbor_x == x and neighbor_z == z:
						continue
					var neighbor := neighbor_z * _grid_size + neighbor_x
					var distance := Vector2(x, z).distance_to(Vector2(neighbor_x, neighbor_z))
					var slope := (heights[cell] - heights[neighbor]) / distance
					if slope > steepest_slope:
						steepest_slope = slope
						downstream[cell] = neighbor
	return downstream


func _flow_accumulation(
	downstream: PackedInt32Array,
	descending_cells: Array[int]
) -> PackedFloat32Array:
	var accumulation := PackedFloat32Array()
	accumulation.resize(downstream.size())
	accumulation.fill(1.0)
	for cell in descending_cells:
		if downstream[cell] >= 0:
			accumulation[downstream[cell]] += accumulation[cell]
	return accumulation


func _cell_position(cell: int) -> Vector2:
	var world_min := _region_size * -0.5
	return Vector2(
		cell % _grid_size - _padding + world_min,
		cell / _grid_size - _padding + world_min
	)


func _is_inside(cell: int) -> bool:
	var position := _cell_position(cell)
	var world_min := _region_size * -0.5
	var world_max := world_min + _region_size
	return (
		position.x >= world_min
		and position.y >= world_min
		and position.x < world_max
		and position.y < world_max
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
