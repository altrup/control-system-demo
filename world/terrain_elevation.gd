extends RefCounted

const DEFAULT_SEA_LEVEL := -2.0
const DEFAULT_GLOBAL_RELIEF := 200.0
const COAST_THRESHOLD := -0.18
const COORDINATE_OFFSET := Vector2(4096.0, 4096.0)

var _continental_noise := FastNoiseLite.new()
var _macro_noise := FastNoiseLite.new()
var _mountain_noise := FastNoiseLite.new()
var _hill_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _sea_level: float
var _global_relief: float


func _init(
	world_seed: int,
	sea_level: float = DEFAULT_SEA_LEVEL,
	global_relief: float = DEFAULT_GLOBAL_RELIEF
) -> void:
	_sea_level = sea_level
	_global_relief = global_relief
	_configure_noise(_continental_noise, world_seed, 0.0004, 3)
	_configure_noise(_macro_noise, world_seed + 1, 0.000875, 4)
	_configure_noise(_mountain_noise, world_seed + 2, 0.00175, 5)
	_mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountain_noise.domain_warp_enabled = true
	_mountain_noise.domain_warp_amplitude = 112.0
	_mountain_noise.domain_warp_frequency = 0.001
	_configure_noise(_hill_noise, world_seed + 3, 0.003, 5)
	_configure_noise(_detail_noise, world_seed + 4, 0.045, 3)


func height_at(position: Vector2) -> float:
	var noise_position := position + COORDINATE_OFFSET
	var coast_distance := _continental_noise.get_noise_2dv(noise_position) - COAST_THRESHOLD
	var land_mask := smoothstep(0.0, 0.22, coast_distance)
	var macro := _macro_noise.get_noise_2dv(noise_position)
	var highland_mask := land_mask * smoothstep(0.05, 0.55, macro)
	var ridges := maxf(_mountain_noise.get_noise_2dv(noise_position), 0.0)
	return (
		coast_distance * 24.0
		+ macro * _global_relief * 0.25 * land_mask
		+ pow(ridges, 1.35) * _global_relief * highland_mask
		+ _hill_noise.get_noise_2dv(noise_position) * 5.0 * land_mask
		+ _detail_noise.get_noise_2dv(noise_position) * 1.2 * land_mask
	)


func is_ocean(position: Vector2) -> bool:
	return height_at(position) < _sea_level


func _configure_noise(
	noise: FastNoiseLite,
	seed: int,
	frequency: float,
	octaves: int
) -> void:
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
