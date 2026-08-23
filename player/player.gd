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
@onready var head: Node3D = $Head

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_motion := event as InputEventMouseMotion
		rotate_y(-mouse_motion.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - mouse_motion.relative.y * mouse_sensitivity,
			-deg_to_rad(89.0),
			deg_to_rad(89.0)
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
	return (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()


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
