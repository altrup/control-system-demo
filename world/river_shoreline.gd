extends RefCounted

const WorldGenerator := preload("res://world/world_generator.gd")

const SEARCH_STEP := 0.25
const MAXIMUM_SEARCH_DISTANCE := WorldGenerator.REGION_SIZE * 1.5
const BINARY_SEARCH_STEPS := 10
const BANK_OVERLAP := 0.15


class ShorePoint:
	extends RefCounted

	var center: Vector3
	var left_shore: Vector3
	var right_shore: Vector3
	var left_edge: Vector3
	var right_edge: Vector3
	var bed_half_width: float

	func _init(
		point_center: Vector3,
		point_left_shore: Vector3,
		point_right_shore: Vector3,
		point_left_edge: Vector3,
		point_right_edge: Vector3,
		point_bed_half_width: float
	) -> void:
		center = point_center
		left_shore = point_left_shore
		right_shore = point_right_shore
		left_edge = point_left_edge
		right_edge = point_right_edge
		bed_half_width = point_bed_half_width


class ShoreBranch:
	extends RefCounted

	var points: Array[ShorePoint]

	func _init(branch_points: Array[ShorePoint]) -> void:
		points = branch_points


func build(
	stream_branches: Array[WorldGenerator.StreamBranch],
	height_at: Callable
) -> Array[ShoreBranch]:
	var shore_branches: Array[ShoreBranch] = []
	for stream_branch in stream_branches:
		var shore_points: Array[ShorePoint] = []
		for point_index in stream_branch.points.size():
			var stream_point := stream_branch.points[point_index]
			var previous: Vector3 = stream_branch.points[maxi(0, point_index - 1)].position
			var following: Vector3 = stream_branch.points[
				mini(stream_branch.points.size() - 1, point_index + 1)
			].position
			var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
			var left_direction := Vector2(-tangent.y, tangent.x)
			var left_shore := _find_shore(
				stream_point.position,
				left_direction,
				stream_point.half_width,
				height_at
			)
			var right_shore := _find_shore(
				stream_point.position,
				-left_direction,
				stream_point.half_width,
				height_at
			)
			shore_points.append(ShorePoint.new(
				stream_point.position,
				left_shore,
				right_shore,
				left_shore + Vector3(left_direction.x, 0.0, left_direction.y) * BANK_OVERLAP,
				right_shore - Vector3(left_direction.x, 0.0, left_direction.y) * BANK_OVERLAP,
				stream_point.half_width
			))
		shore_branches.append(ShoreBranch.new(shore_points))
	return shore_branches


func _find_shore(
	center: Vector3,
	direction: Vector2,
	bed_half_width: float,
	height_at: Callable
) -> Vector3:
	var lower_distance := bed_half_width
	var upper_distance := lower_distance + SEARCH_STEP
	var maximum_distance := MAXIMUM_SEARCH_DISTANCE
	while upper_distance <= maximum_distance:
		if _terrain_height(center, direction, upper_distance, height_at) >= center.y:
			for step in BINARY_SEARCH_STEPS:
				var midpoint := (lower_distance + upper_distance) * 0.5
				if _terrain_height(center, direction, midpoint, height_at) < center.y:
					lower_distance = midpoint
				else:
					upper_distance = midpoint
			return _point_at_distance(center, direction, upper_distance)
		lower_distance = upper_distance
		upper_distance += SEARCH_STEP
	return _point_at_distance(center, direction, maximum_distance)


func _terrain_height(
	center: Vector3,
	direction: Vector2,
	distance: float,
	height_at: Callable
) -> float:
	var position := Vector2(center.x, center.z) + direction * distance
	return height_at.call(position) as float


func _point_at_distance(center: Vector3, direction: Vector2, distance: float) -> Vector3:
	return Vector3(
		center.x + direction.x * distance,
		center.y,
		center.z + direction.y * distance
	)
