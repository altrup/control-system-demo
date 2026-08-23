extends RefCounted

const RiverNetwork := preload("res://world/river_network.gd")

var _region_size: int


func _init(region_size: int) -> void:
	_region_size = region_size


func carve(
	base_heights: PackedFloat32Array,
	branches: Array[RiverNetwork.ChannelBranch]
) -> PackedFloat32Array:
	if base_heights.size() != _region_size * _region_size:
		push_error("River carver height map dimensions do not match the visible terrain.")
		return PackedFloat32Array()
	var carved := base_heights.duplicate()
	for branch in branches:
		for index in range(branch.points.size() - 1):
			_carve_section(carved, branch.points[index], branch.points[index + 1])
	return carved


func _carve_section(
	heights: PackedFloat32Array,
	start_point: RiverNetwork.ChannelPoint,
	end_point: RiverNetwork.ChannelPoint
) -> void:
	var start := Vector2(start_point.position.x, start_point.position.z)
	var end := Vector2(end_point.position.x, end_point.position.z)
	var delta := end - start
	var length_squared := delta.length_squared()
	if is_zero_approx(length_squared):
		return
	var radius := maxf(
		start_point.half_width + start_point.bank_falloff,
		end_point.half_width + end_point.bank_falloff
	)
	var minimum := Vector2(
		maxf(0.0, minf(start.x, end.x) - radius),
		maxf(0.0, minf(start.y, end.y) - radius)
	)
	var maximum := Vector2(
		minf(_region_size - 1, maxf(start.x, end.x) + radius),
		minf(_region_size - 1, maxf(start.y, end.y) + radius)
	)
	for z in range(floori(minimum.y), ceili(maximum.y) + 1):
		for x in range(floori(minimum.x), ceili(maximum.x) + 1):
			var position := Vector2(x, z)
			var progress := clampf((position - start).dot(delta) / length_squared, 0.0, 1.0)
			var closest := start + delta * progress
			var half_width := lerpf(start_point.half_width, end_point.half_width, progress)
			var bank_falloff := lerpf(start_point.bank_falloff, end_point.bank_falloff, progress)
			var distance := position.distance_to(closest)
			if distance >= half_width + bank_falloff:
				continue
			var water_height := lerpf(start_point.position.y, end_point.position.y, progress)
			var depth := lerpf(start_point.depth, end_point.depth, progress)
			var bed_height := water_height - depth
			var blend := smoothstep(half_width, half_width + bank_falloff, distance)
			var cell := z * _region_size + x
			heights[cell] = minf(heights[cell], lerpf(bed_height, heights[cell], blend))
