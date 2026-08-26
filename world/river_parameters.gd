extends Resource

@export_range(1.0, 1048576.0, 1.0, "or_greater") var minimum_visible_flow := 16384.0
@export_range(1.0, 1048576.0, 1.0, "or_greater") var reference_flow := 65536.0
@export_range(0.1, 4.0, 0.1, "or_greater") var discharge_scale := 2.0
@export_range(0.1, 12.0, 0.1, "or_greater") var reference_width := 3.0
@export_range(0.05, 1.0, 0.05) var width_growth_exponent := 0.45
@export_range(0.1, 4.0, 0.1, "or_greater") var reference_depth := 0.8
@export_range(0.05, 1.0, 0.05) var depth_growth_exponent := 0.35
@export_range(0.1, 10.0, 0.1, "or_greater") var bank_falloff_ratio := 4.0
@export_range(0.1, 10.0, 0.1) var maximum_centerline_cut := 2.0
