extends Resource

@export_range(1.0, 1048576.0, 1.0) var stream_threshold := 4096.0
@export_range(1.0, 1048576.0, 1.0) var channel_threshold := 65536.0
@export_range(0.1, 12.0, 0.1) var minimum_width := 3.0
@export_range(0.1, 12.0, 0.1) var maximum_width := 8.0
@export_range(0.05, 1.0, 0.05) var width_growth_exponent := 0.45
@export_range(0.1, 4.0, 0.1) var minimum_depth := 0.8
@export_range(0.1, 4.0, 0.1) var maximum_depth := 1.8
@export_range(0.05, 1.0, 0.05) var depth_growth_exponent := 0.35
@export_range(0.1, 10.0, 0.1) var minimum_bank_falloff := 2.0
@export_range(0.1, 10.0, 0.1) var maximum_bank_falloff := 4.8
@export_range(0.1, 10.0, 0.1) var maximum_centerline_cut := 2.0
