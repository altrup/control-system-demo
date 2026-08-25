extends RefCounted

const CENTERLINE_COST := 0.03
const CONTINUITY_COST := 0.15
const SUBCELL_CURVATURE := 0.6
const SMOOTHING_PASSES := 2

var _sample_spacing: float
var _corridor_half_width: float


func _init(sample_spacing: float = 1.0, corridor_half_width: float = 6.0) -> void:
	_sample_spacing = maxf(sample_spacing, 0.1)
	_corridor_half_width = maxf(corridor_half_width, _sample_spacing)


func refine(path: PackedVector2Array, height_at: Callable) -> PackedVector2Array:
	if path.size() < 3 or not height_at.is_valid():
		return path
	var sampled := _sample_curve(path)
	var offsets := PackedFloat32Array()
	offsets.resize(sampled.size())
	var previous_offset := 0.0
	var offset_steps := floori(_corridor_half_width / _sample_spacing)
	for index in range(1, sampled.size() - 1):
		var tangent := (sampled[index + 1] - sampled[index - 1]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var best_offset := 0.0
		var best_cost := INF
		for step in range(-offset_steps, offset_steps + 1):
			var offset := step * _sample_spacing
			var candidate := sampled[index] + normal * offset
			var cost := (
				float(height_at.call(candidate))
				+ absf(offset) * CENTERLINE_COST
				+ absf(offset - previous_offset) * CONTINUITY_COST
			)
			if cost < best_cost:
				best_cost = cost
				best_offset = offset
		offsets[index] = best_offset
		previous_offset = best_offset

	for _pass in SMOOTHING_PASSES:
		var source := offsets.duplicate()
		for index in range(1, offsets.size() - 1):
			offsets[index] = (
				source[index - 1] + source[index] * 2.0 + source[index + 1]
			) * 0.25
	var distances := PackedFloat32Array([0.0])
	for index in range(1, sampled.size()):
		distances.append(distances[-1] + sampled[index].distance_to(sampled[index - 1]))
	var phase := path[0].x * 0.31 + path[0].y * 0.17
	for index in range(1, offsets.size() - 1):
		var progress := distances[index] / distances[-1]
		var curvature := clampf(
			sin(distances[index] * 0.3 + phase) * 0.8
			+ sin(distances[index] * 0.53 - phase) * 0.3,
			-1.0,
			1.0
		) * SUBCELL_CURVATURE * sin(PI * progress)
		offsets[index] = clampf(
			offsets[index] + curvature,
			-_corridor_half_width,
			_corridor_half_width
		)

	var refined := sampled.duplicate()
	for index in range(1, refined.size() - 1):
		var tangent := (sampled[index + 1] - sampled[index - 1]).normalized()
		refined[index] += Vector2(-tangent.y, tangent.x) * offsets[index]
	refined[0] = path[0]
	refined[-1] = path[-1]
	return refined


func _sample_curve(path: PackedVector2Array) -> PackedVector2Array:
	var curve := Curve2D.new()
	curve.bake_interval = _sample_spacing
	for index in path.size():
		var previous := path[maxi(0, index - 1)]
		var following := path[mini(path.size() - 1, index + 1)]
		var handle := (following - previous) / 6.0
		curve.add_point(path[index], -handle, handle)
	var sampled := PackedVector2Array()
	var length := curve.get_baked_length()
	var distance := 0.0
	while distance < length:
		sampled.append(curve.sample_baked(distance, true))
		distance += _sample_spacing
	sampled.append(path[-1])
	return sampled
