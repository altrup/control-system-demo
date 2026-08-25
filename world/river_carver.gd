extends RefCounted

const RiverNetwork := preload("res://world/river_network.gd")
const FLAT_BED_RATIO := 0.6
const SUB_GRID_HALF_WIDTH := 0.5

var _region_size: float
var _sample_spacing: float
var _grid_size: int


func _init(region_size: float, sample_spacing: float = 1.0) -> void:
	_region_size = region_size
	_sample_spacing = sample_spacing
	_grid_size = roundi(region_size / sample_spacing)


func carve(
	base_heights: PackedFloat32Array,
	branches: Array[RiverNetwork.ChannelBranch]
) -> PackedFloat32Array:
	if base_heights.size() != _grid_size * _grid_size:
		push_error("River carver height map dimensions do not match the visible terrain.")
		return PackedFloat32Array()
	var carved := base_heights.duplicate()
	for branch in branches:
		for index in range(branch.points.size() - 1):
			_carve_section(
				carved,
				base_heights,
				branch.points[index],
				branch.points[index + 1]
			)
	return carved


func _carve_section(
	heights: PackedFloat32Array,
	base_heights: PackedFloat32Array,
	start_point: RiverNetwork.ChannelPoint,
	end_point: RiverNetwork.ChannelPoint
) -> void:
	var grid_offset := Vector2.ONE * (_grid_size * 0.5)
	var start := (
		Vector2(start_point.position.x, start_point.position.z) / _sample_spacing
		+ grid_offset
	)
	var end := (
		Vector2(end_point.position.x, end_point.position.z) / _sample_spacing
		+ grid_offset
	)
	var delta := end - start
	var length_squared := delta.length_squared()
	if is_zero_approx(length_squared):
		return
	var minimum_half_width := minf(
		start_point.half_width,
		end_point.half_width
	) / _sample_spacing
	var radius := maxf(
		start_point.half_width + start_point.bank_falloff,
		end_point.half_width + end_point.bank_falloff
	) / _sample_spacing
	if minimum_half_width < SUB_GRID_HALF_WIDTH:
		radius += 1.0
	var minimum := Vector2(
		maxf(0.0, minf(start.x, end.x) - radius),
		maxf(0.0, minf(start.y, end.y) - radius)
	)
	var maximum := Vector2(
		minf(_grid_size - 1, maxf(start.x, end.x) + radius),
		minf(_grid_size - 1, maxf(start.y, end.y) + radius)
	)
	for z in range(floori(minimum.y), ceili(maximum.y) + 1):
		for x in range(floori(minimum.x), ceili(maximum.x) + 1):
			var position := Vector2(x, z)
			var progress := clampf((position - start).dot(delta) / length_squared, 0.0, 1.0)
			var closest := start + delta * progress
			var half_width := (
				lerpf(start_point.half_width, end_point.half_width, progress)
				/ _sample_spacing
			)
			var bank_falloff := (
				lerpf(start_point.bank_falloff, end_point.bank_falloff, progress)
				/ _sample_spacing
			)
			var distance := position.distance_to(closest)
			var bed_half_width := half_width * FLAT_BED_RATIO
			if half_width < SUB_GRID_HALF_WIDTH:
				distance = maxf(distance - (1.0 - bed_half_width), 0.0)
			if distance >= half_width + bank_falloff:
				continue
			var water_height := lerpf(start_point.position.y, end_point.position.y, progress)
			var depth := lerpf(start_point.depth, end_point.depth, progress)
			var bed_height := water_height - depth
			var cell := z * _grid_size + x
			var profile_height: float
			if distance <= bed_half_width:
				profile_height = bed_height
			elif distance <= half_width:
				profile_height = lerpf(
					bed_height,
					water_height,
					smoothstep(bed_half_width, half_width, distance)
				)
			else:
				profile_height = lerpf(
					water_height,
					base_heights[cell],
					smoothstep(half_width, half_width + bank_falloff, distance)
				)
			heights[cell] = minf(heights[cell], profile_height)
