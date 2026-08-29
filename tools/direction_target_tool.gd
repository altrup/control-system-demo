class_name DirectionTargetTool
extends Tool

enum State {
	SELECTING_TARGET,
	POSITIONING
}

var _state := State.SELECTING_TARGET
func get_state():
	return _state

# ===== AIM LOGIC =====

var _aim_direction := Vector3.ZERO

func set_aim_direction(direction: Vector3):
	assert(get_state() == State.SELECTING_TARGET, "Must be in SELECTING_TARGET state to aim")
	_aim_direction = direction
	_state = State.POSITIONING

func clear_aim_direction():
	_aim_direction = Vector3.ZERO
	_control_direction = Vector3.DOWN
	_angular_velocity = Vector3.ZERO
	_state = State.SELECTING_TARGET

# ===== POSITIONING LOGIC =====
# tool will be aligned so edge is facing towards aim location
# position is relative to user

var _control_direction := Vector3.DOWN

func set_control_direction(control_direction: Vector3):
	assert(get_state() == State.POSITIONING, "Must be in POSITIONING state to set_control_direction")
	_control_direction = control_direction

@export var swing_radius := 2.0

@export var angular_stiffness := 60.0
@export var angular_damping := 15.0
@export var max_angular_acceleration := 120.0
@export var max_angular_speed := 12.0

@export var roll_stiffness := 20.0
@export var roll_damping := 9.0
@export var max_roll_acceleration := 35.0
@export var max_roll_speed := 4.5

var _angular_velocity := Vector3.ZERO
var _roll_angular_velocity := 0.0

func _physics_process(delta: float) -> void:
	if get_state() != State.POSITIONING:
		return
	
	_update_rotation(delta)
	_update_edge_alignment(delta)

# ----- ROTATION -----

func _update_rotation(delta: float) -> void:
	if _control_direction.is_zero_approx():
		return
	
	var target_direction := _control_direction.normalized()
	
	# The axe model extends along the pivot's local +Y axis.
	var current_direction := (
		basis * Vector3.UP
	).normalized()
	
	var rotation_error := _get_rotation_error(
		current_direction,
		target_direction
	)
	
	# Spring acceleration toward the control direction,
	# with damping to reduce oscillation.
	var angular_acceleration := (
		rotation_error * angular_stiffness
		- _angular_velocity * angular_damping
	)
	
	angular_acceleration = angular_acceleration.limit_length(
		max_angular_acceleration
	)
	
	_angular_velocity += angular_acceleration * delta
	_angular_velocity = _angular_velocity.limit_length(
		max_angular_speed
	)
	
	var angular_speed := _angular_velocity.length()
	
	if angular_speed <= 0.0001:
		return
	
	var rotation_axis := _angular_velocity / angular_speed
	var rotation_angle := angular_speed * delta
	var rotation_step := Basis(
		rotation_axis,
		rotation_angle
	)
	
	basis = (
		rotation_step * basis
	).orthonormalized()

func _get_rotation_error(
	from: Vector3,
	to: Vector3
) -> Vector3:
	var from_normalized := from.normalized()
	var to_normalized := to.normalized()
	
	var cross := from_normalized.cross(to_normalized)
	var dot := clampf(
		from_normalized.dot(to_normalized),
		-1.0,
		1.0
	)
	
	if cross.length_squared() < 0.000001:
		if dot > 0.0:
			return Vector3.ZERO
		
		# The directions are opposite, so choose any axis
		# perpendicular to the current direction.
		var opposite_axis := from_normalized.cross(
			Vector3.UP
		)
		
		if opposite_axis.length_squared() < 0.000001:
			opposite_axis = from_normalized.cross(
				Vector3.RIGHT
			)
		
		return opposite_axis.normalized() * PI
	
	var angle := atan2(cross.length(), dot)
	return cross.normalized() * angle

# ----- EDGE ALIGNMENT -----

func _update_edge_alignment(delta: float) -> void:
	if _aim_direction.is_zero_approx():
		return
	
	# Both are expressed in the parent's local coordinate space.
	var current_y := (
		basis * Vector3.UP
	).normalized()
	
	var current_edge_direction := (
		basis * Vector3.LEFT
	).normalized()
	
	# This tangent points along the shortest spherical path
	# from current_y toward _aim_direction.
	var target_edge_direction := (
		_aim_direction.normalized()
		- current_y
		* _aim_direction.normalized().dot(current_y)
	)
	
	var roll_error := 0.0
	
	# When these directions are parallel or opposite, there is no
	# unique shortest path, so only apply damping.
	if not target_edge_direction.is_zero_approx():
		target_edge_direction = (
			target_edge_direction.normalized()
		)
	
		# Signed shortest angle around current_y.
		roll_error = atan2(
			current_y.dot(
				current_edge_direction.cross(
					target_edge_direction
				)
			),
			current_edge_direction.dot(
				target_edge_direction
			)
		)
	
	var roll_acceleration := (
		roll_error * roll_stiffness
		- _roll_angular_velocity * roll_damping
	)
	
	roll_acceleration = clampf(
		roll_acceleration,
		-max_roll_acceleration,
		max_roll_acceleration
	)
	
	_roll_angular_velocity += (
		roll_acceleration * delta
	)
	
	_roll_angular_velocity = clampf(
		_roll_angular_velocity,
		-max_roll_speed,
		max_roll_speed
	)
	
	var roll_angle := _roll_angular_velocity * delta
	
	# Multiplying on the right applies rotation around local Y.
	basis = (
		basis
		* Basis(Vector3.UP, roll_angle)
	).orthonormalized()

func get_total_angular_velocity() -> Vector3:
	var local_y_in_parent := (
		basis * Vector3.UP
	).normalized()
	
	return (
		_angular_velocity
		+ local_y_in_parent * _roll_angular_velocity
	)
