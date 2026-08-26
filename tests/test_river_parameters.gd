extends GutTest

const PARAMETERS_PATH := "res://world/river_parameters.gd"


func test_default_river_parameters_match_the_design_ranges() -> void:
	assert_true(ResourceLoader.exists(PARAMETERS_PATH))
	if not ResourceLoader.exists(PARAMETERS_PATH):
		return
	var parameters: Resource = (load(PARAMETERS_PATH) as GDScript).new()

	assert_eq(parameters.get("minimum_visible_flow"), 16384.0)
	assert_eq(parameters.get("reference_flow"), 65536.0)
	assert_eq(parameters.get("discharge_scale"), 2.0)
	assert_eq(parameters.get("reference_width"), 3.0)
	assert_eq(parameters.get("width_growth_exponent"), 0.45)
	assert_eq(parameters.get("reference_depth"), 0.8)
	assert_eq(parameters.get("depth_growth_exponent"), 0.35)
	assert_eq(parameters.get("bank_falloff_ratio"), 4.0)
	assert_eq(parameters.get("maximum_centerline_cut"), 2.0)
