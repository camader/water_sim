class_name TerrainData
extends RefCounted

var width: int
var depth: int
var max_height: int
var terrace_size: float
var heightmap: PackedInt32Array


func _init(p_width: int = 64, p_depth: int = 64, p_max_height: int = 10, p_terrace_size: float = 2.0) -> void:
	width = p_width
	depth = p_depth
	max_height = p_max_height
	terrace_size = p_terrace_size
	heightmap = PackedInt32Array()
	heightmap.resize(width * depth)


func generate(seed_value: int) -> void:
	var base_noise := FastNoiseLite.new()
	base_noise.seed = seed_value
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base_noise.frequency = 0.03
	base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	base_noise.fractal_octaves = 3
	base_noise.fractal_lacunarity = 2.0
	base_noise.fractal_gain = 0.5

	# Generate base terrain with terracing
	for z in depth:
		for x in width:
			var noise_val: float = base_noise.get_noise_2d(x, z)
			# Remap from [-1, 1] to [0, max_height]
			var raw_h: float = (noise_val + 1.0) / 2.0 * max_height
			# Terrace: snap to discrete levels
			var terraced_h: int = int(floorf(raw_h / terrace_size) * terrace_size) + 1
			heightmap[z * width + x] = clampi(terraced_h, 1, max_height)

	# Carve rivers
	_carve_rivers(seed_value + 1000)


func get_height(x: int, z: int) -> int:
	return heightmap[z * width + x]


func _carve_rivers(river_seed: int) -> void:
	var river_noise := FastNoiseLite.new()
	river_noise.seed = river_seed
	river_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	river_noise.frequency = 0.02
	river_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	river_noise.fractal_octaves = 2

	var carve_threshold := 0.06
	var carve_depth := 3

	for z in depth:
		for x in width:
			var val: float = absf(river_noise.get_noise_2d(x, z))
			if val < carve_threshold:
				var idx: int = z * width + x
				heightmap[idx] = maxi(heightmap[idx] - carve_depth, 1)
