extends RefCounted

const RiverParameters := preload("res://world/river_parameters.gd")
const RiverPathRefiner := preload("res://world/river_path_refiner.gd")

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
const PATH_REFINEMENT_SPACING := 1.0
const PATH_REFINEMENT_HALF_WIDTH := 6.0
const VALLEY_MINIMUM_DEPTH := 0.6
const VALLEY_MAXIMUM_DEPTH := 4.0
const VALLEY_MINIMUM_RADIUS := 4.0
const VALLEY_MAXIMUM_RADIUS := 18.0
const VALLEY_ONSET_STREAM_RATIO := 0.25

var _region_size: float
var _padding: float
var _grid_size: int
var _parameters: RiverParameters
var _output_size: float
var _sample_spacing: float
var _path_height_sampler := Callable()
var _full_domain_output := false


func _init(
	region_size: float,
	padding: float,
	parameters: RiverParameters = null,
	sample_spacing: float = 1.0,
	path_height_sampler: Callable = Callable()
) -> void:
	_region_size = region_size
	_padding = padding
	_sample_spacing = sample_spacing
	_grid_size = roundi((region_size + padding * 2.0) / sample_spacing)
	_output_size = region_size
	_parameters = parameters if parameters != null else RiverParameters.new()
	_path_height_sampler = path_height_sampler


func build(base_heights: PackedFloat32Array) -> Array[ChannelBranch]:
	return _build(base_heights, false)


func build_full_domain(base_heights: PackedFloat32Array) -> Array[ChannelBranch]:
	return _build(base_heights, true)


func erode_valleys(base_heights: PackedFloat32Array) -> PackedFloat32Array:
	if base_heights.size() != _grid_size * _grid_size:
		push_error("River height map dimensions do not match the generation domain.")
		return PackedFloat32Array()
	var ascending_cells: Array[int] = []
	var routing_heights := _fill_depressions(base_heights, ascending_cells)
	var downstream := _flow_directions(routing_heights)
	ascending_cells.reverse()
	var accumulation := _flow_accumulation(downstream, ascending_cells)
	var eroded := base_heights.duplicate()
	for cell in accumulation.size():
		var dimensions := valley_dimensions_for_area(accumulation[cell])
		if dimensions == Vector2.ZERO:
			continue
		_erode_valley_section(eroded, base_heights, cell, dimensions.x, dimensions.y)
	return eroded


func valley_dimensions_for_area(area: float) -> Vector2:
	var flow := area * _parameters.discharge_scale
	var onset_flow := _parameters.minimum_visible_flow * VALLEY_ONSET_STREAM_RATIO
	if flow <= onset_flow:
		return Vector2.ZERO
	var ratio := flow / _parameters.reference_flow
	var fade := smoothstep(
		onset_flow,
		_parameters.reference_flow,
		minf(flow, _parameters.reference_flow)
	)
	var scale := pow(maxf(ratio, 1.0), 0.3)
	return Vector2(
		clampf(
			VALLEY_MINIMUM_RADIUS * scale,
			VALLEY_MINIMUM_RADIUS,
			VALLEY_MAXIMUM_RADIUS
		) * fade,
		clampf(
			VALLEY_MINIMUM_DEPTH * scale,
			VALLEY_MINIMUM_DEPTH,
			VALLEY_MAXIMUM_DEPTH
		) * fade
	)


func _erode_valley_section(
	eroded: PackedFloat32Array,
	base_heights: PackedFloat32Array,
	cell: int,
	radius: float,
	depth: float
) -> void:
	var center_x := cell % _grid_size
	var center_z: int = cell / _grid_size
	var extent := ceili(radius / _sample_spacing)
	for z in range(maxi(1, center_z - extent), mini(_grid_size - 1, center_z + extent + 1)):
		for x in range(maxi(1, center_x - extent), mini(_grid_size - 1, center_x + extent + 1)):
			var distance := Vector2(x - center_x, z - center_z).length() * _sample_spacing
			if distance >= radius:
				continue
			var blend := smoothstep(1.0, 0.0, distance / radius)
			var target := z * _grid_size + x
			eroded[target] = minf(eroded[target], base_heights[target] - depth * blend)


func _build(
	base_heights: PackedFloat32Array,
	full_domain: bool
) -> Array[ChannelBranch]:
	if base_heights.size() != _grid_size * _grid_size:
		push_error("River height map dimensions do not match the generation domain.")
		return []
	_output_size = _grid_size * _sample_spacing
	_full_domain_output = true

	var ascending_cells: Array[int] = []
	var routing_heights := _fill_depressions(base_heights, ascending_cells)
	var downstream := _flow_directions(routing_heights)
	ascending_cells.reverse()
	var accumulation := _flow_accumulation(downstream, ascending_cells)
	var retained: Dictionary[int, bool] = {}
	var water_heights: Dictionary[int, float] = {}
	_retain_full_domain(
		base_heights, downstream, accumulation, retained, water_heights
	)
	var branches := _build_branches(retained, water_heights, downstream, accumulation)
	_constrain_water_to_banks(branches, base_heights)
	if full_domain:
		return branches
	_output_size = _region_size
	_full_domain_output = false
	return _crop_crossing_branches(branches)


func dimensions_for_area(area: float) -> Vector3:
	var flow := area * _parameters.discharge_scale
	var ratio := maxf(flow / _parameters.reference_flow, 0.0001)
	var profile_fade := 1.0
	if _parameters.minimum_visible_flow < _parameters.reference_flow:
		profile_fade = smoothstep(
			_parameters.minimum_visible_flow / _parameters.reference_flow,
			1.0,
			minf(ratio, 1.0)
		)
	var river_depth := _parameters.reference_depth * pow(
		ratio, _parameters.depth_growth_exponent
	)
	var depth := river_depth * profile_fade
	var river_width := _parameters.reference_width * pow(
		ratio, _parameters.width_growth_exponent
	)
	return Vector3(
		river_width * profile_fade,
		depth,
		river_depth * _parameters.bank_falloff_ratio * profile_fade
	)


func _retain_full_domain(
	base_heights: PackedFloat32Array,
	downstream: PackedInt32Array,
	accumulation: PackedFloat32Array,
	retained: Dictionary[int, bool],
	water_heights: Dictionary[int, float]
) -> void:
	var incoming_count: Dictionary[int, int] = {}
	for cell in downstream.size():
		var next := downstream[cell]
		if (
			next >= 0
			and accumulation[cell] * _parameters.discharge_scale
			>= _parameters.minimum_visible_flow
		):
			incoming_count[next] = incoming_count.get(next, 0) + 1
	for cell in downstream.size():
		if (
			downstream[cell] >= 0
			and accumulation[cell] * _parameters.discharge_scale
			>= _parameters.minimum_visible_flow
			and incoming_count.get(cell, 0) == 0
		):
			_retain_domain_path(
				cell,
				base_heights,
				downstream,
				accumulation,
				retained,
				water_heights
			)


func _retain_domain_path(
	entry: int,
	base_heights: PackedFloat32Array,
	downstream: PackedInt32Array,
	accumulation: PackedFloat32Array,
	retained: Dictionary[int, bool],
	water_heights: Dictionary[int, float]
) -> void:
	var cells: Array[int] = [entry]
	var cell := entry
	while downstream[cell] >= 0:
		cell = downstream[cell]
		cells.append(cell)
	if not _is_domain_boundary(cell):
		return
	_retain_cells(cells, base_heights, accumulation, retained, water_heights)


func _retain_cells(
	cells: Array[int],
	base_heights: PackedFloat32Array,
	accumulation: PackedFloat32Array,
	retained: Dictionary[int, bool],
	water_heights: Dictionary[int, float]
) -> void:
	if cells.size() < 2:
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


func _crop_crossing_branches(
	branches: Array[ChannelBranch]
) -> Array[ChannelBranch]:
	var downstream_branches: Dictionary[Vector2, int] = {}
	for branch_index in branches.size():
		var start := branches[branch_index].points[0].position
		downstream_branches[Vector2(start.x, start.z)] = branch_index

	var retained_ranges: Dictionary[int, Vector2i] = {}
	for branch_index in branches.size():
		var points := branches[branch_index].points
		for point_index in range(points.size() - 1):
			if (
				not _is_playable_position(points[point_index].position)
				and _is_playable_position(points[point_index + 1].position)
			):
				_merge_ranges(
					retained_ranges,
					_trace_to_playable_exit(
						branches,
						downstream_branches,
						branch_index,
						point_index
					)
				)

	var cropped: Array[ChannelBranch] = []
	for branch_index in branches.size():
		if not retained_ranges.has(branch_index):
			continue
		var point_range := retained_ranges[branch_index]
		var points: Array[ChannelPoint] = []
		for point_index in range(point_range.x, point_range.y + 1):
			points.append(branches[branch_index].points[point_index])
		_extend_boundary_endpoints(points)
		cropped.append(ChannelBranch.new(points))
	return cropped


func _trace_to_playable_exit(
	branches: Array[ChannelBranch],
	downstream_branches: Dictionary[Vector2, int],
	entry_branch: int,
	entry_point: int
) -> Dictionary[int, Vector2i]:
	var route: Dictionary[int, Vector2i] = {}
	var branch_index := entry_branch
	var start_point := entry_point
	while not route.has(branch_index):
		var points := branches[branch_index].points
		for point_index in range(start_point, points.size() - 1):
			if (
				_is_playable_position(points[point_index].position)
				and not _is_playable_position(points[point_index + 1].position)
			):
				route[branch_index] = Vector2i(start_point, point_index + 1)
				return route
		route[branch_index] = Vector2i(start_point, points.size() - 1)
		var end := points[-1].position
		var end_key := Vector2(end.x, end.z)
		if not downstream_branches.has(end_key):
			return {}
		branch_index = downstream_branches[end_key]
		start_point = 0
	return {}


func _merge_ranges(
	target: Dictionary[int, Vector2i],
	source: Dictionary[int, Vector2i]
) -> void:
	for branch_index in source:
		var source_range := source[branch_index]
		if not target.has(branch_index):
			target[branch_index] = source_range
			continue
		var target_range := target[branch_index]
		target[branch_index] = Vector2i(
			mini(target_range.x, source_range.x),
			maxi(target_range.y, source_range.y)
		)


func _is_playable_position(position: Vector3) -> bool:
	var world_min := _region_size * -0.5
	var world_max := world_min + _region_size
	return (
		position.x >= world_min
		and position.z >= world_min
		and position.x < world_max
		and position.z < world_max
	)


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
				points.append(_make_point(
					next, water_heights, accumulation, accumulation[current]
				))
				break
			current = next
		points = _curve_branch(points)
		_extend_boundary_endpoints(points)
		branches.append(ChannelBranch.new(points))
	return branches


func _make_point(
	cell: int,
	water_heights: Dictionary[int, float],
	accumulation: PackedFloat32Array,
	area_override: float = -1.0
) -> ChannelPoint:
	var horizontal := _cell_position(cell)
	var area := accumulation[cell] if area_override < 0.0 else area_override
	return ChannelPoint.new(
		Vector3(horizontal.x, water_heights[cell], horizontal.y),
		area,
		dimensions_for_area(area)
	)


func _curve_branch(points: Array[ChannelPoint]) -> Array[ChannelPoint]:
	if points.size() < 3:
		return points
	var source_distances := _point_distances(points)
	var horizontal := PackedVector2Array()
	for point in points:
		horizontal.append(Vector2(point.position.x, point.position.z))
	if _path_height_sampler.is_valid():
		horizontal = RiverPathRefiner.new(
			PATH_REFINEMENT_SPACING, PATH_REFINEMENT_HALF_WIDTH
		).refine(horizontal, _path_height_sampler)
	var controls: Array[Vector3] = []
	for position in horizontal:
		controls.append(Vector3(position.x, 0.0, position.y))
	controls = _cut_corners(controls)
	controls = _cut_corners(controls)
	controls = _cut_corners(controls)
	controls = _cut_corners(controls)
	controls = _cut_corners(controls)

	var curve := Curve3D.new()
	curve.bake_interval = CURVE_SAMPLE_INTERVAL
	for index in controls.size():
		var previous := controls[maxi(0, index - 1)]
		var following := controls[mini(controls.size() - 1, index + 1)]
		var handle := (following - previous) / 6.0
		curve.add_point(controls[index], -handle, handle)

	var baked := PackedVector3Array()
	var baked_length := curve.get_baked_length()
	var bake_distance := 0.0
	while bake_distance < baked_length:
		baked.append(curve.sample_baked(bake_distance, true))
		bake_distance += CURVE_SAMPLE_INTERVAL
	baked.append(curve.sample_baked(baked_length, true))
	baked = _smooth_sampled_path(baked)
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
	curved[0].position.x = points[0].position.x
	curved[0].position.z = points[0].position.z
	curved[-1].position.x = points[-1].position.x
	curved[-1].position.z = points[-1].position.z
	return curved


func _smooth_sampled_path(points: PackedVector3Array) -> PackedVector3Array:
	var smoothed := points
	for _iteration in 4:
		var source := smoothed
		smoothed = source.duplicate()
		for index in range(1, source.size() - 1):
			smoothed[index] = (
				source[index - 1] * 0.25
				+ source[index] * 0.5
				+ source[index + 1] * 0.25
			)
	return smoothed


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
	for branch in branches:
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

	_constrain_water_grades(branches, water_heights)

	for branch in branches:
		for point in branch.points:
			point.position.y = water_heights[Vector2(point.position.x, point.position.z)]


func _constrain_water_grades(
	branches: Array[ChannelBranch],
	water_heights: Dictionary[Vector2, float]
) -> void:
	var outgoing: Dictionary[Vector2, Array] = {}
	var incoming: Dictionary[Vector2, Array] = {}
	var incoming_count: Dictionary[Vector2, int] = {}
	for point in water_heights:
		incoming_count[point] = 0
	for branch in branches:
		for index in range(branch.points.size() - 1):
			var current_position := branch.points[index].position
			var next_position := branch.points[index + 1].position
			var current := Vector2(current_position.x, current_position.z)
			var next := Vector2(next_position.x, next_position.z)
			var distance := current.distance_to(next)
			if not outgoing.has(current):
				outgoing[current] = []
			if not incoming.has(next):
				incoming[next] = []
			outgoing[current].append(Vector3(next.x, next.y, distance))
			incoming[next].append(Vector3(current.x, current.y, distance))
			incoming_count[next] = incoming_count.get(next, 0) + 1

	var queue: Array[Vector2] = []
	for point in incoming_count:
		if incoming_count[point] == 0:
			queue.append(point)
	var order: Array[Vector2] = []
	var queue_index := 0
	while queue_index < queue.size():
		var current := queue[queue_index]
		queue_index += 1
		order.append(current)
		for edge: Vector3 in outgoing.get(current, []):
			var next := Vector2(edge.x, edge.y)
			water_heights[next] = minf(
				water_heights[next],
				water_heights[current] - CHANNEL_MINIMUM_DROP * edge.z
			)
			incoming_count[next] -= 1
			if incoming_count[next] == 0:
				queue.append(next)

	for index in range(order.size() - 1, -1, -1):
		var current := order[index]
		for edge: Vector3 in incoming.get(current, []):
			var previous := Vector2(edge.x, edge.y)
			water_heights[previous] = minf(
				water_heights[previous],
				water_heights[current] + CHANNEL_MAXIMUM_DROP * edge.z
			)


func _sample_height(base_heights: PackedFloat32Array, position: Vector2) -> float:
	var world_min := _region_size * -0.5
	var grid_position := (
		position - Vector2.ONE * world_min + Vector2.ONE * _padding
	) / _sample_spacing
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
	elif _full_domain_output and _is_output_edge_sample(points[last_index].position):
		var domain_extension := _extended_domain_exit_point(
			points[last_index], points[last_index - 1]
		)
		if domain_extension != null:
			points.append(domain_extension)


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


func _extended_domain_exit_point(point: ChannelPoint, neighbor: ChannelPoint) -> ChannelPoint:
	var direction := Vector2(
		point.position.x - neighbor.position.x,
		point.position.z - neighbor.position.z
	).normalized()
	var world_min := _output_size * -0.5
	var world_max := world_min + _output_size
	var boundary_distance := INF
	if direction.x < 0.0:
		boundary_distance = minf(
			boundary_distance,
			(world_min - point.position.x) / direction.x
		)
	elif direction.x > 0.0:
		boundary_distance = minf(
			boundary_distance,
			(world_max - point.position.x) / direction.x
		)
	if direction.y < 0.0:
		boundary_distance = minf(
			boundary_distance,
			(world_min - point.position.z) / direction.y
		)
	elif direction.y > 0.0:
		boundary_distance = minf(
			boundary_distance,
			(world_max - point.position.z) / direction.y
		)
	var boundary_position := point.position + Vector3(
		direction.x * (boundary_distance + 0.001),
		0.0,
		direction.y * (boundary_distance + 0.001)
	)
	var boundary_point := ChannelPoint.new(
		boundary_position,
		point.accumulated_area,
		Vector3(point.half_width * 2.0, point.depth, point.bank_falloff)
	)
	return _extended_boundary_point(boundary_point, point)


func _boundary_outward_component(position: Vector3, direction: Vector2) -> float:
	var world_min := _output_size * -0.5
	var world_max := world_min + _output_size
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
	var world_min := _output_size * -0.5
	var world_max := world_min + _output_size
	return maxf(
		maxf(world_min - position.x, position.x - world_max),
		maxf(world_min - position.z, position.z - world_max)
	)


func _is_inside_position(position: Vector3) -> bool:
	var world_min := _output_size * -0.5
	var world_max := world_min + _output_size
	return (
		position.x >= world_min
		and position.z >= world_min
		and position.x < world_max
		and position.z < world_max
	)


func _is_output_edge_sample(position: Vector3) -> bool:
	var world_min := _output_size * -0.5
	var world_max_sample := world_min + _output_size - _sample_spacing
	return (
		position.x <= world_min
		or position.z <= world_min
		or position.x >= world_max_sample
		or position.z >= world_max_sample
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
				var distance := Vector2(
					neighbor_x - cell_x, neighbor_z - cell_z
				).length() * _sample_spacing
				filled[neighbor] = maxf(
					filled[neighbor], filled[cell] + DEPRESSION_SLOPE * distance
				)
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
					var distance := (
						Vector2(x, z).distance_to(Vector2(neighbor_x, neighbor_z))
						* _sample_spacing
					)
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
	accumulation.fill(_sample_spacing * _sample_spacing)
	for cell in descending_cells:
		if downstream[cell] >= 0:
			accumulation[downstream[cell]] += accumulation[cell]
	return accumulation


func _cell_position(cell: int) -> Vector2:
	var world_min := _region_size * -0.5
	return Vector2(
		(cell % _grid_size) * _sample_spacing - _padding + world_min,
		(cell / _grid_size) * _sample_spacing - _padding + world_min
	)


func _is_domain_boundary(cell: int) -> bool:
	var x := cell % _grid_size
	var z: int = cell / _grid_size
	return x == 0 or z == 0 or x == _grid_size - 1 or z == _grid_size - 1


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
