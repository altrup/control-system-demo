extends GutTest


func test_uses_jolt_physics() -> void:
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")
