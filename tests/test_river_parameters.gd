extends GutTest

const PARAMETERS_PATH := "res://world/river_parameters.gd"


func test_default_river_parameters_match_the_design_ranges() -> void:
	assert_true(ResourceLoader.exists(PARAMETERS_PATH))
	if not ResourceLoader.exists(PARAMETERS_PATH):
		return
	var parameters: Resource = (load(PARAMETERS_PATH) as GDScript).new()

	assert_eq(parameters.get("stream_threshold"), 4096.0)
	assert_eq(parameters.get("channel_threshold"), 65536.0)
	assert_eq(parameters.get("minimum_width"), 3.0)
	assert_eq(parameters.get("maximum_width"), 8.0)
	assert_eq(parameters.get("width_growth_exponent"), 0.45)
	assert_eq(parameters.get("minimum_depth"), 0.8)
	assert_eq(parameters.get("maximum_depth"), 1.8)
	assert_eq(parameters.get("depth_growth_exponent"), 0.35)
	assert_eq(parameters.get("minimum_bank_falloff"), 2.0)
	assert_eq(parameters.get("maximum_bank_falloff"), 4.8)
	assert_eq(parameters.get("maximum_centerline_cut"), 2.0)
