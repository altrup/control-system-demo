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
const CHANNEL_MAXIMUM_DROP := 0.04
const BANK_FREEBOARD := 0.15
const CURVE_SAMPLE_INTERVAL := 0.5
const CURVE_MAX_OFFSET := 0.75

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
	var branches := _build_branches(retained, water_heights, downstream, accumulation)
	_constrain_water_to_banks(branches, base_heights)
	return branches


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
		minimum_depth * pow(ratio, _parameters.depth_growth_exponent),
		minimum_depth,
		maximum_depth
	)
	return Vector3(
		clampf(
			minimum_width * pow(ratio, _parameters.width_growth_exponent),
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
		points = _curve_branch(points)
		_extend_boundary_endpoints(points)
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


func _curve_branch(points: Array[ChannelPoint]) -> Array[ChannelPoint]:
	if points.size() < 3:
		return points
	var source_distances := _point_distances(points)
	var controls: Array[Vector3] = []
	# ponytail: Sub-cell bends remove display bias; use D-infinity for continuous topology.
	var phase := points[0].position.x * 0.31 + points[0].position.z * 0.17
	for index in points.size():
		var position := Vector3(points[index].position.x, 0.0, points[index].position.z)
		if index > 0 and index < points.size() - 1:
			var previous := points[index - 1].position
			var following := points[index + 1].position
			var tangent := Vector2(
				following.x - previous.x,
				following.z - previous.z
			).normalized()
			var incoming := Vector2(
				position.x - previous.x,
				position.z - previous.z
			).normalized()
			var outgoing := Vector2(
				following.x - position.x,
				following.z - position.z
			).normalized()
			var progress := source_distances[index] / source_distances[-1]
			var bend := clampf(
				sin(source_distances[index] * 0.3 + phase) * 0.8
				+ sin(source_distances[index] * 0.53 - phase) * 0.3,
				-CURVE_MAX_OFFSET,
				CURVE_MAX_OFFSET
			) * sin(PI * progress) * smoothstep(0.7, 0.95, incoming.dot(outgoing))
			position.x -= tangent.y * bend
			position.z += tangent.x * bend
		controls.append(position)
	controls = _cut_corners(controls)
	controls = _cut_corners(controls)

	var curve := Curve3D.new()
	curve.bake_interval = CURVE_SAMPLE_INTERVAL
	for index in controls.size():
		var previous := controls[maxi(0, index - 1)]
		var following := controls[mini(controls.size() - 1, index + 1)]
		var handle := (following - previous) / 6.0
		curve.add_point(controls[index], -handle, handle)

	var baked := curve.get_baked_points()
	var baked_distances := PackedFloat32Array([0.0])
	for index in range(1, baked.size()):
		baked_distances.append(
			baked_distances[-1]
			+ Vector2(baked[index].x - baked[index - 1].x, baked[index].z - baked[index - 1].z).length()
		)
	var curved: Array[ChannelPoint] = []
	var source_index := 0
	for index in baked.size():
		var target_distance := (
			baked_distances[index] / baked_distances[-1] * source_distances[-1]
		)
		while (
			source_index < points.size() - 2
			and source_distances[source_index + 1] < target_distance
		):
			source_index += 1
		var span := source_distances[source_index + 1] - source_distances[source_index]
		var weight := (target_distance - source_distances[source_index]) / span
		var area := lerpf(
			points[source_index].accumulated_area,
			points[source_index + 1].accumulated_area,
			weight
		)
		var water_height := lerpf(
			points[source_index].position.y,
			points[source_index + 1].position.y,
			weight
		)
		curved.append(ChannelPoint.new(
			Vector3(baked[index].x, water_height, baked[index].z),
			area,
			dimensions_for_area(area)
		))
	return curved


func _point_distances(points: Array[ChannelPoint]) -> PackedFloat32Array:
	var distances := PackedFloat32Array([0.0])
	for index in range(1, points.size()):
		distances.append(
			distances[-1] + Vector2(
				points[index].position.x - points[index - 1].position.x,
				points[index].position.z - points[index - 1].position.z
			).length()
		)
	return distances


func _cut_corners(positions: Array[Vector3]) -> Array[Vector3]:
	var cut: Array[Vector3] = [positions[0]]
	for index in range(positions.size() - 1):
		cut.append(positions[index].lerp(positions[index + 1], 0.25))
		cut.append(positions[index].lerp(positions[index + 1], 0.75))
	cut.append(positions[-1])
	return cut


func _constrain_water_to_banks(
	branches: Array[ChannelBranch],
	base_heights: PackedFloat32Array
) -> void:
	var water_heights: Dictionary[Vector2, float] = {}
	var point_count := 0
	for branch in branches:
		point_count += branch.points.size()
		for index in branch.points.size():
			var point := branch.points[index]
			var previous := branch.points[maxi(0, index - 1)].position
			var next_index := mini(branch.points.size() - 1, index + 1)
			var following := branch.points[next_index].position
			var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
			var bank_offset := (
				Vector2(-tangent.y, tangent.x)
				* (point.half_width + point.bank_falloff)
			)
			var center := Vector2(point.position.x, point.position.z)
			var bank_height := minf(
				_sample_height(base_heights, center + bank_offset),
				_sample_height(base_heights, center - bank_offset)
			)
			water_heights[center] = minf(
				minf(water_heights.get(center, INF), point.position.y),
				bank_height - BANK_FREEBOARD
			)

	# ponytail: Full relaxation suits this small graph; use a topological pass if maps grow.
	for _iteration in point_count:
		var changed := false
		for branch in branches:
			for index in range(branch.points.size() - 1):
				var current := branch.points[index]
				var next := branch.points[index + 1]
				var current_key := Vector2(current.position.x, current.position.z)
				var next_key := Vector2(next.position.x, next.position.z)
				var distance := current_key.distance_to(next_key)
				var maximum_next_height := (
					water_heights[current_key] - CHANNEL_MINIMUM_DROP * distance
				)
				if water_heights[next_key] > maximum_next_height:
					water_heights[next_key] = maximum_next_height
					changed = true
				var maximum_current_height := (
					water_heights[next_key] + CHANNEL_MAXIMUM_DROP * distance
				)
				if water_heights[current_key] > maximum_current_height:
					water_heights[current_key] = maximum_current_height
					changed = true
		if not changed:
			break

	for branch in branches:
		for point in branch.points:
			point.position.y = water_heights[Vector2(point.position.x, point.position.z)]


func _sample_height(base_heights: PackedFloat32Array, position: Vector2) -> float:
	var world_min := _region_size * -0.5
	var grid_position := position - Vector2.ONE * world_min + Vector2.ONE * _padding
	var x0 := clampi(floori(grid_position.x), 0, _grid_size - 1)
	var z0 := clampi(floori(grid_position.y), 0, _grid_size - 1)
	var x1 := mini(x0 + 1, _grid_size - 1)
	var z1 := mini(z0 + 1, _grid_size - 1)
	var x_blend := clampf(grid_position.x - x0, 0.0, 1.0)
	var z_blend := clampf(grid_position.y - z0, 0.0, 1.0)
	var top := lerpf(
		base_heights[z0 * _grid_size + x0],
		base_heights[z0 * _grid_size + x1],
		x_blend
	)
	var bottom := lerpf(
		base_heights[z1 * _grid_size + x0],
		base_heights[z1 * _grid_size + x1],
		x_blend
	)
	return lerpf(top, bottom, z_blend)


func _extend_boundary_endpoints(points: Array[ChannelPoint]) -> void:
	if points.size() < 2:
		return
	var first_extension := _extended_boundary_point(points[0], points[1])
	if first_extension != null:
		points.push_front(first_extension)
	var last_index := points.size() - 1
	var last_extension := _extended_boundary_point(points[last_index], points[last_index - 1])
	if last_extension != null:
		points.append(last_extension)


func _extended_boundary_point(point: ChannelPoint, neighbor: ChannelPoint) -> ChannelPoint:
	if _is_inside_position(point.position):
		return null
	var outward := Vector2(
		point.position.x - neighbor.position.x,
		point.position.z - neighbor.position.z
	).normalized()
	var outward_component := _boundary_outward_component(point.position, outward)
	if is_zero_approx(outward_component):
		return null
	var profile_radius := point.half_width + point.bank_falloff
	var extension_distance := (
		maxf(profile_radius - _distance_outside_world(point.position), 0.0)
		/ outward_component
		+ 0.01
	)
	var extension := outward * extension_distance
	return ChannelPoint.new(
		point.position + Vector3(extension.x, 0.0, extension.y),
		point.accumulated_area,
		Vector3(point.half_width * 2.0, point.depth, point.bank_falloff)
	)


func _boundary_outward_component(position: Vector3, direction: Vector2) -> float:
	var world_min := _region_size * -0.5
	var world_max := world_min + _region_size
	var component := 0.0
	if position.x <= world_min:
		component = maxf(component, -direction.x)
	if position.x >= world_max:
		component = maxf(component, direction.x)
	if position.z <= world_min:
		component = maxf(component, -direction.y)
	if position.z >= world_max:
		component = maxf(component, direction.y)
	return component


func _distance_outside_world(position: Vector3) -> float:
	var world_min := _region_size * -0.5
	var world_max := world_min + _region_size
	return maxf(
		maxf(world_min - position.x, position.x - world_max),
		maxf(world_min - position.z, position.z - world_max)
	)


func _is_inside_position(position: Vector3) -> bool:
	var world_min := _region_size * -0.5
	var world_max := world_min + _region_size
	return (
		position.x >= world_min
		and position.z >= world_min
		and position.x < world_max
		and position.z < world_max
	)


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
