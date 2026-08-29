extends CharacterBody3D

@export var walking_speed := 5.0
@export var crouching_speed := 3.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var standing_height := 1.8
@export var crouching_height := 1.1
@export var standing_head_height := 1.65
@export var crouching_head_height := 1.0
@export var crouch_transition_speed := 8.0

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var body: MeshInstance3D = $Body
@onready var axe: DirectionTargetTool = $Axe
@onready var head: Node3D = $Head

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _is_controlling_tool := false
var _aim_direction := Vector3.ZERO
var _control_direction := Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("tool_primary"):
		_start_tool_control()
	elif event.is_action_released("tool_primary") and _is_controlling_tool:
		_stop_tool_control()
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if _is_controlling_tool:
			_update_tool_control(mouse_motion.relative)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-mouse_motion.relative.x * mouse_sensitivity)
			head.rotation.x = clampf(
				head.rotation.x - mouse_motion.relative.y * mouse_sensitivity,
				-deg_to_rad(89.0),
				deg_to_rad(89.0)
			)


func _start_tool_control() -> void:
	_aim_direction = (head.basis * Vector3.FORWARD).normalized()
	_control_direction = _aim_direction
	axe.set_aim_direction(_aim_direction)
	axe.set_control_direction(_control_direction)
	_is_controlling_tool = true


func _stop_tool_control() -> void:
	var view_direction := (head.basis * Vector3.FORWARD).normalized()
	rotate_y(atan2(-view_direction.x, -view_direction.z))
	head.rotation = Vector3(asin(view_direction.y), 0.0, 0.0)
	axe.clear_aim_direction()
	_is_controlling_tool = false
	_aim_direction = Vector3.ZERO
	_control_direction = Vector3.ZERO


func _update_tool_control(mouse_motion: Vector2) -> void:
	var yawed_direction := Basis(
		Vector3.UP,
		-mouse_motion.x * mouse_sensitivity
	) * _control_direction
	var horizontal_direction := Vector3(
		yawed_direction.x,
		0.0,
		yawed_direction.z
	).normalized()
	var pitch := clampf(
		asin(yawed_direction.y) - mouse_motion.y * mouse_sensitivity,
		-deg_to_rad(89.0),
		deg_to_rad(89.0)
	)
	_control_direction = (
		horizontal_direction * cos(pitch) + Vector3.UP * sin(pitch)
	).normalized()
	axe.set_control_direction(_control_direction)
	head.basis = Basis.looking_at(
		_aim_direction.slerp(_control_direction, 0.5).normalized(),
		Vector3.UP
	)


func _physics_process(delta: float) -> void:
	var is_crouching := Input.is_action_pressed("crouch")
	set_crouching(is_crouching, delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump"):
		apply_jump(is_on_floor())

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := movement_direction(input)
	var speed := crouching_speed if is_crouching else walking_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()


func movement_direction(input: Vector2) -> Vector3:
	var forward := head.global_basis * Vector3.FORWARD
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	return (right * input.x - forward * input.y).normalized()


func apply_jump(is_grounded: bool) -> void:
	if is_grounded:
		velocity.y = jump_velocity


func set_crouching(is_crouching: bool, delta: float) -> void:
	var capsule := collision.shape as CapsuleShape3D
	var target_height := crouching_height if is_crouching else standing_height
	var height := move_toward(capsule.height, target_height, crouch_transition_speed * delta)
	capsule.height = height
	collision.position.y = height / 2.0

	var body_scale := height / standing_height
	body.scale.y = body_scale
	body.position.y = 0.7 * body_scale

	var target_head_height := crouching_head_height if is_crouching else standing_head_height
	head.position.y = move_toward(head.position.y, target_head_height, crouch_transition_speed * delta)
