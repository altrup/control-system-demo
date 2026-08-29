extends GutTest

const PLAYER_SCENE_PATH := "res://player/player.tscn"


func test_left_mouse_is_bound_to_tool_primary() -> void:
	assert_true(InputMap.has_action("tool_primary"))
	if not InputMap.has_action("tool_primary"):
		return

	var has_left_mouse := false
	for event: InputEvent in InputMap.action_get_events("tool_primary"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			has_left_mouse = true
	assert_true(has_left_mouse)


func test_space_is_bound_to_jump() -> void:
	assert_true(InputMap.has_action("jump"))
	if not InputMap.has_action("jump"):
		return

	var has_space := false
	for event: InputEvent in InputMap.action_get_events("jump"):
		if event is InputEventKey and event.physical_keycode == KEY_SPACE:
			has_space = true
	assert_true(has_space)


func test_player_owns_axe_at_centered_shoulder_pivot() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var axe := player.get_node_or_null("Axe") as DirectionTargetTool
	assert_not_null(axe)
	if axe == null:
		return

	assert_almost_eq(axe.position.x, 0.0, 0.0001)
	assert_gt(axe.position.y, player.standing_height / 2.0)
	assert_lt(axe.position.y, player.standing_head_height)


func test_tool_primary_press_starts_axe_aiming() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var axe := player.get_node("Axe") as DirectionTargetTool
	player._unhandled_input(_tool_primary_event(true))

	assert_eq(axe.get_state(), DirectionTargetTool.State.POSITIONING)
	assert_true((axe.get("_aim_direction") as Vector3).is_equal_approx(Vector3.FORWARD))


func test_tool_primary_release_clears_axe_aiming() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var axe := player.get_node("Axe") as DirectionTargetTool
	player._unhandled_input(_tool_primary_event(true))
	player._unhandled_input(_tool_primary_event(false))

	assert_eq(axe.get_state(), DirectionTargetTool.State.SELECTING_TARGET)
	assert_true((axe.get("_aim_direction") as Vector3).is_zero_approx())


func test_mouse_motion_controls_axe_and_moves_camera_halfway() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var axe := player.get_node("Axe") as DirectionTargetTool
	var head := player.get_node("Head") as Node3D
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, -50.0)
	player._unhandled_input(_tool_primary_event(true))
	player._unhandled_input(motion)

	var expected_control := Vector3(0.19767681, 0.09983342, -0.97517033)
	var expected_camera := Vector3(0.09945771, 0.05022948, -0.99377320)
	var control_direction := axe.get("_control_direction") as Vector3
	var camera_direction := head.basis * Vector3.FORWARD
	assert_true(
		control_direction.is_equal_approx(expected_control),
		"Expected %s, got %s" % [expected_control, control_direction]
	)
	assert_true(
		camera_direction.is_equal_approx(expected_camera),
		"Expected %s, got %s" % [expected_camera, camera_direction]
	)


func test_tool_control_pitch_stops_at_normal_camera_limit() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var axe := player.get_node("Axe") as DirectionTargetTool
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0.0, -1000.0)
	player._unhandled_input(_tool_primary_event(true))
	player._unhandled_input(motion)

	var control_direction := axe.get("_control_direction") as Vector3
	assert_almost_eq(control_direction.y, sin(deg_to_rad(89.0)), 0.0001)
	assert_lt(control_direction.z, 0.0)


func test_release_preserves_camera_as_normal_player_facing() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var camera := player.get_node("Head/Camera3D") as Camera3D
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, -50.0)
	player._unhandled_input(_tool_primary_event(true))
	player._unhandled_input(motion)
	var view_before_release := -camera.global_basis.z
	player._unhandled_input(_tool_primary_event(false))

	var movement_forward: Vector3 = player.movement_direction(Vector2(0.0, -1.0))
	var view_forward := Vector3(
		view_before_release.x,
		0.0,
		view_before_release.z
	).normalized()
	assert_true((-camera.global_basis.z).is_equal_approx(view_before_release))
	assert_true(movement_forward.is_equal_approx(view_forward))


func test_movement_follows_current_camera_during_tool_control() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var camera := player.get_node("Head/Camera3D") as Camera3D
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 0.0)
	player._unhandled_input(_tool_primary_event(true))
	player._unhandled_input(motion)

	var movement_forward: Vector3 = player.movement_direction(Vector2(0.0, -1.0))
	var view_forward := -camera.global_basis.z
	view_forward.y = 0.0
	assert_true(movement_forward.is_equal_approx(view_forward.normalized()))


func test_jump_only_applies_while_grounded() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	assert_true(player.has_method("apply_jump"))
	if not player.has_method("apply_jump"):
		return

	player.velocity.y = 0.0
	player.call("apply_jump", true)
	assert_gt(player.velocity.y, 0.0)

	player.velocity.y = 0.0
	player.call("apply_jump", false)
	assert_eq(player.velocity.y, 0.0)


func test_player_can_walk_on_sixty_degree_slopes() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	assert_almost_eq(player.floor_max_angle, deg_to_rad(60.0), 0.0001)


func test_movement_follows_player_facing() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var forward: Vector3 = player.call("movement_direction", Vector2(0.0, -1.0))
	assert_true(forward.is_equal_approx(Vector3.FORWARD))

	player.rotation.y = PI / 2.0
	var turned_forward: Vector3 = player.call("movement_direction", Vector2(0.0, -1.0))
	assert_true(turned_forward.is_equal_approx(Vector3.LEFT))


func test_diagonal_movement_has_unit_length() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var diagonal: Vector3 = player.call("movement_direction", Vector2(1.0, -1.0))
	assert_almost_eq(diagonal.length(), 1.0, 0.0001)


func test_crouching_lowers_player_without_moving_feet() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var collision := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var head := player.get_node_or_null("Head") as Node3D
	assert_not_null(collision)
	assert_not_null(head)
	if collision == null or head == null:
		return

	var capsule := collision.shape as CapsuleShape3D
	var standing_height := capsule.height
	var standing_bottom := collision.position.y - standing_height / 2.0
	var standing_head_height := head.position.y
	player.call("set_crouching", true, 1.0)

	assert_lt(capsule.height, standing_height)
	assert_almost_eq(collision.position.y - capsule.height / 2.0, standing_bottom, 0.0001)
	assert_lt(head.position.y, standing_head_height)


func test_releasing_crouch_restores_player_height() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	var collision := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D
	var head := player.get_node("Head") as Node3D
	var standing_height := capsule.height
	var standing_head_height := head.position.y
	player.call("set_crouching", true, 1.0)
	player.call("set_crouching", false, 1.0)

	assert_almost_eq(capsule.height, standing_height, 0.0001)
	assert_almost_eq(head.position.y, standing_head_height, 0.0001)


func test_forward_input_moves_player_forward() -> void:
	var player := _instantiate_player()
	if player == null:
		return

	Input.action_press("move_forward")
	await wait_physics_frames(1)
	Input.action_release("move_forward")
	assert_lt(player.velocity.z, 0.0)


func _instantiate_player() -> CharacterBody3D:
	assert_true(ResourceLoader.exists(PLAYER_SCENE_PATH), "Player scene exists")
	if not ResourceLoader.exists(PLAYER_SCENE_PATH):
		return null

	var player_scene := load(PLAYER_SCENE_PATH) as PackedScene
	return add_child_autofree(player_scene.instantiate()) as CharacterBody3D


func _tool_primary_event(is_pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"tool_primary"
	event.pressed = is_pressed
	return event
