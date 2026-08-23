extends GutTest

const PLAYER_SCENE_PATH := "res://player/player.tscn"


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
