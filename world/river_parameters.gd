extends Resource

@export_range(1.0, 65536.0, 1.0) var channel_threshold := 4096.0
@export_range(0.1, 12.0, 0.1) var minimum_width := 1.5
@export_range(0.1, 12.0, 0.1) var maximum_width := 6.0
@export_range(0.1, 4.0, 0.1) var minimum_depth := 0.6
@export_range(0.1, 4.0, 0.1) var maximum_depth := 1.8
@export_range(0.1, 10.0, 0.1) var minimum_bank_falloff := 2.0
@export_range(0.1, 10.0, 0.1) var maximum_bank_falloff := 4.8
@export_range(0.1, 10.0, 0.1) var maximum_centerline_cut := 2.0
