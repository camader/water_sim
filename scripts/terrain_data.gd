class_name TerrainData
extends RefCounted

var width: int
var depth: int
var max_height: int
var terrace_size: float
var heightmap: PackedInt32Array
var source_cells: Array = []
var channel_cells: Array = []
var channel_edge_cells: Array = []
var channel_waterfall_cells: Array = []

# Channel generation params
var num_edge_channels: int = 2
var num_interior_channels: int = 1
var plateau_size_min: int = 20
var plateau_size_max: int = 40
var starting_height: int = 8


func _init(p_width: int = 72, p_depth: int = 72, p_max_height: int = 10, p_terrace_size: float = 2.0) -> void:
	width = p_width
	depth = p_depth
	max_height = p_max_height
	terrace_size = p_terrace_size
	heightmap = PackedInt32Array()
	heightmap.resize(width * depth)


func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	heightmap.fill(1)

	source_cells.clear()
	channel_cells.clear()
	channel_edge_cells.clear()
	channel_waterfall_cells.clear()

	_generate_channels(rng)
	_generate_terrain_around_channels(seed_value)
	_label_channel_cells()


func get_height(x: int, z: int) -> int:
	return heightmap[z * width + x]


func set_height(x: int, z: int, h: int) -> void:
	heightmap[z * width + x] = clampi(h, 1, max_height)


func _generate_channels(rng: RandomNumberGenerator) -> void:
	var channel_height_map := {}
	var min_source_dist: int = 25
	var used_starts: Array = []

	# === EDGE CHANNELS (start on left x=0 or top z=0, must reach opposite edge) ===
	var source_channel_idx: int = rng.randi_range(0, num_edge_channels - 1)

	for i in num_edge_channels:
		var is_primary: bool = (i == source_channel_idx)
		var half_w: int = rng.randi_range(1, 2) if is_primary else 1

		var start_x: int = 0
		var start_z: int = 0
		var on_x_edge: bool = true
		var found: bool = false
		for _attempt in 20:
			on_x_edge = rng.randf() < 0.5
			if on_x_edge:
				start_x = 0
				start_z = rng.randi_range(2, depth / 2)
			else:
				start_x = rng.randi_range(2, width / 2)
				start_z = 0

			var too_close: bool = false
			for prev in used_starts:
				var dist: float = sqrt(float((start_x - prev.x) ** 2 + (start_z - prev.y) ** 2))
				if dist < min_source_dist:
					too_close = true
					break
			if not too_close:
				found = true
				break

		if not found:
			continue

		used_starts.append(Vector2i(start_x, start_z))

		var meander_noise := FastNoiseLite.new()
		meander_noise.seed = rng.randi()
		meander_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		meander_noise.frequency = 0.02

		var amp: float = 6.0 if is_primary else 4.5

		# Straight entry: walk perpendicular from edge into interior
		# These cells bypass the exclusion zone — they connect source to interior
		var entry_len: int = 3
		var entry_h: int = starting_height
		if on_x_edge:
			for s in entry_len:
				for dz in range(-half_w, half_w + 1):
					var px: int = s
					var pz: int = start_z + dz
					if px >= 0 and px < width and pz >= 0 and pz < depth:
						var cell := Vector2i(px, pz)
						if not channel_height_map.has(cell) or channel_height_map[cell] > entry_h:
							channel_height_map[cell] = entry_h
		else:
			for s in entry_len:
				for dx in range(-half_w, half_w + 1):
					var px: int = start_x + dx
					var pz: int = s
					if px >= 0 and px < width and pz >= 0 and pz < depth:
						var cell := Vector2i(px, pz)
						if not channel_height_map.has(cell) or channel_height_map[cell] > entry_h:
							channel_height_map[cell] = entry_h

		# Mark source cells from the entry (only edge row/column of primary)
		if is_primary:
			for dz in range(-half_w, half_w + 1):
				for dx in range(-half_w, half_w + 1):
					var px: int = start_x + dx
					var pz: int = start_z + dz
					if px >= 0 and px < width and pz >= 0 and pz < depth:
						if px == 0 or pz == 0:
							source_cells.append(Vector2i(px, pz))

		# Meander path starts from interior end of entry
		var interior_start_x: float = float(entry_len - 1) if on_x_edge else float(start_x)
		var interior_start_z: float = float(start_z) if on_x_edge else float(entry_len - 1)
		var path := _walk_channel_path_to_edge(interior_start_x, interior_start_z, meander_noise, amp, rng)
		_assign_plateau_heights(path, half_w, starting_height, channel_height_map, rng)

		# Branches — curve away from main channel then re-enter it
		var num_branches: int = rng.randi_range(2, 4) if is_primary else rng.randi_range(1, 2)
		for _b in num_branches:
			if path.size() < 20:
				break
			var branch_idx: int = rng.randi_range(path.size() / 5, path.size() * 3 / 5)
			var branch_pt: Vector2i = path[branch_idx]

			# Target: a point further along the main channel for re-entry
			var reentry_idx: int = mini(branch_idx + rng.randi_range(20, 45), path.size() - 1)
			var reentry_pt: Vector2i = path[reentry_idx]

			var branch_start_h: int = starting_height
			if channel_height_map.has(branch_pt):
				branch_start_h = channel_height_map[branch_pt]

			var branch_noise := FastNoiseLite.new()
			branch_noise.seed = rng.randi()
			branch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			branch_noise.frequency = 0.03

			var branch_half_w: int = 1
			var branch_path := _walk_branch_path(
				float(branch_pt.x), float(branch_pt.y), reentry_pt,
				branch_noise, rng.randf_range(4.0, 6.0), rng
			)
			_assign_plateau_heights_capped(
				branch_path, branch_half_w, branch_start_h,
				channel_height_map, rng
			)

	# === INTERIOR CHANNELS ===
	for _i in num_interior_channels:
		var int_x: int = 0
		var int_z: int = 0
		var found: bool = false
		for _attempt in 30:
			int_x = rng.randi_range(width / 4, width * 3 / 4)
			int_z = rng.randi_range(2, depth / 2)

			if channel_height_map.has(Vector2i(int_x, int_z)):
				continue

			var too_close: bool = false
			for prev in used_starts:
				var dist: float = sqrt(float((int_x - prev.x) ** 2 + (int_z - prev.y) ** 2))
				if dist < min_source_dist:
					too_close = true
					break
			if not too_close:
				found = true
				break

		if not found:
			continue

		used_starts.append(Vector2i(int_x, int_z))

		var int_noise := FastNoiseLite.new()
		int_noise.seed = rng.randi()
		int_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		int_noise.frequency = 0.03

		var int_half_w: int = 1
		var int_path := _walk_channel_path_to_edge(
			float(int_x), float(int_z), int_noise, rng.randf_range(4.0, 6.0), rng
		)
		var int_start_h: int = rng.randi_range(starting_height - 2, starting_height)
		_assign_plateau_heights(int_path, int_half_w, int_start_h, channel_height_map, rng)

	# Write to heightmap
	for cell in channel_height_map:
		heightmap[cell.y * width + cell.x] = channel_height_map[cell]

	channel_cells = channel_height_map.keys()


func _generate_terrain_around_channels(seed_value: int) -> void:
	var channel_set := {}
	for cell in channel_cells:
		channel_set[cell] = true

	# Noise for adding variation to terrain growth
	var base_noise := FastNoiseLite.new()
	base_noise.seed = seed_value
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base_noise.frequency = 0.05
	base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	base_noise.fractal_octaves = 2

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	# Seed the BFS from channel bank cells: non-channel cells adjacent to channel
	var visited := {}
	var queue: Array = []  # [Vector2i, int] pairs — cell and its assigned height

	for cell in channel_cells:
		visited[cell] = true

	for cell in channel_cells:
		var ch_h: int = heightmap[cell.y * width + cell.x]
		var bank_h: int = ch_h + 1
		for dir in dirs:
			var nx: int = cell.x + dir.x
			var nz: int = cell.y + dir.y
			if nx < 0 or nx >= width or nz < 0 or nz >= depth:
				continue
			var neighbor := Vector2i(nx, nz)
			if channel_set.has(neighbor):
				continue
			if visited.has(neighbor):
				# If already queued, take the higher bank requirement
				continue
			visited[neighbor] = true
			heightmap[nz * width + nx] = clampi(bank_h, 1, max_height)
			queue.append(neighbor)

	# BFS outward: each ring can stay the same height or go up by 1,
	# influenced by noise. Terracing applied.
	while queue.size() > 0:
		var next_queue: Array = []
		for cell in queue:
			var my_h: int = heightmap[cell.y * width + cell.x]

			for dir in dirs:
				var nx: int = cell.x + dir.x
				var nz: int = cell.y + dir.y
				if nx < 0 or nx >= width or nz < 0 or nz >= depth:
					continue
				var neighbor := Vector2i(nx, nz)
				if visited.has(neighbor):
					continue
				visited[neighbor] = true

				# Noise determines whether we step up, stay, or (rarely) step down
				var noise_val: float = base_noise.get_noise_2d(float(nx), float(nz))
				var new_h: int = my_h
				if noise_val > 0.1:
					new_h = my_h + 1  # step up
				elif noise_val < -0.3:
					new_h = my_h  # stay (creates plateaus)
				# else stay same

				# Apply terrace snapping
				new_h = int(floorf(float(new_h) / terrace_size) * terrace_size) + 1
				new_h = clampi(new_h, my_h, max_height)  # never go below parent

				heightmap[nz * width + nx] = new_h
				next_queue.append(neighbor)

		queue = next_queue


## Walk a channel using a heading angle that gets perturbed by noise and sharp random turns.
## The heading is biased toward the diagonal (+x,+z) but can swing widely.
func _walk_channel_path_to_edge(
	start_x: float, start_z: float,
	meander_noise: FastNoiseLite, meander_amp: float,
	rng: RandomNumberGenerator
) -> Array:
	var path: Array = []
	var fx: float = start_x
	var fz: float = start_z
	var max_steps: int = (width + depth) * 2

	# Heading angle: PI/4 = diagonal toward (+x,+z)
	var base_heading: float = PI / 4.0
	var heading: float = base_heading
	var steps_since_turn: int = 0
	var turn_interval: int = rng.randi_range(8, 20)

	while path.size() < max_steps:
		var cx: int = clampi(int(fx), 0, width - 1)
		var cz: int = clampi(int(fz), 0, depth - 1)
		path.append(Vector2i(cx, cz))

		if cx >= width - 1 or cz >= depth - 1:
			break

		# Smooth noise-based heading adjustment
		var noise_turn: float = meander_noise.get_noise_2d(fx * 0.1, fz * 0.1) * meander_amp * 0.15

		# Occasional sharp direction changes
		steps_since_turn += 1
		if steps_since_turn >= turn_interval:
			noise_turn += rng.randf_range(-0.8, 0.8)
			steps_since_turn = 0
			turn_interval = rng.randi_range(8, 20)

		heading += noise_turn
		# Pull heading back toward the general diagonal so we still cross the map
		heading = lerpf(heading, base_heading, 0.03)
		# Clamp heading to prevent going backward
		heading = clampf(heading, -PI / 6.0, PI / 2.0 + PI / 6.0)

		fx += cos(heading)
		fz += sin(heading)

		# Keep channels at least 2 cells from left/top edges
		fx = maxf(fx, 2.0)
		fz = maxf(fz, 2.0)

	return path


## Walk a branch that curves away from then back toward a target point on the main channel.
func _walk_branch_path(
	start_x: float, start_z: float,
	target: Vector2i,
	meander_noise: FastNoiseLite, meander_amp: float,
	rng: RandomNumberGenerator
) -> Array:
	var path: Array = []
	var fx: float = start_x
	var fz: float = start_z
	var max_steps: int = width + depth

	# Initial heading: perpendicular away from the main diagonal, randomly left or right
	var base_heading: float = PI / 4.0
	var side: float = 1.0 if rng.randf() < 0.5 else -1.0
	var heading: float = base_heading + side * rng.randf_range(0.6, 1.2)

	var phase_steps: int = rng.randi_range(15, 35)  # how long before curving back
	var step: int = 0

	while path.size() < max_steps:
		var cx: int = clampi(int(fx), 0, width - 1)
		var cz: int = clampi(int(fz), 0, depth - 1)
		path.append(Vector2i(cx, cz))

		if cx >= width - 1 or cz >= depth - 1:
			break
		if cx <= 0 or cz <= 0:
			break

		step += 1

		# Noise wobble
		var noise_turn: float = meander_noise.get_noise_2d(fx * 0.12, fz * 0.12) * 0.3

		# After the initial outward phase, pull toward the target to re-enter main channel
		if step > phase_steps:
			var dx: float = float(target.x) - fx
			var dz: float = float(target.y) - fz
			var target_heading: float = atan2(dz, dx)
			heading = lerpf(heading, target_heading, 0.08)

			# Close enough to target — stop
			if dx * dx + dz * dz < 9.0:
				path.append(target)
				break

		heading += noise_turn
		fx += cos(heading)
		fz += sin(heading)

		fx = maxf(fx, 2.0)
		fz = maxf(fz, 2.0)

	return path


## Assign heights with plateau drops. Heights are written across the full width
## at the center-line's height, so transitions are perpendicular to flow.
func _assign_plateau_heights(
	path: Array, half_w: int, start_h: int,
	channel_height_map: Dictionary, rng: RandomNumberGenerator
) -> void:
	var current_h: int = start_h
	var plateau_remaining: int = rng.randi_range(plateau_size_min, plateau_size_max)

	for pt in path:
		if plateau_remaining <= 0 and current_h > 1:
			current_h = maxi(current_h - 1, 1)
			plateau_remaining = rng.randi_range(plateau_size_min, plateau_size_max)

		# All cells across the width get the center-line's height
		_stamp_width(pt, half_w, current_h, channel_height_map)
		plateau_remaining -= 1


## Same as above but height is capped — can only go down, never above start_h.
## When merging with existing lower channel, takes the lower value.
func _assign_plateau_heights_capped(
	path: Array, half_w: int, start_h: int,
	channel_height_map: Dictionary, rng: RandomNumberGenerator
) -> void:
	var current_h: int = start_h
	var plateau_remaining: int = rng.randi_range(plateau_size_min, plateau_size_max)

	for pt in path:
		if plateau_remaining <= 0 and current_h > 1:
			current_h = maxi(current_h - 1, 1)
			plateau_remaining = rng.randi_range(plateau_size_min, plateau_size_max)

		# If we encounter existing channel that's lower, drop to match
		if channel_height_map.has(pt) and channel_height_map[pt] < current_h:
			current_h = channel_height_map[pt]

		# Never go above start height
		current_h = mini(current_h, start_h)

		_stamp_width(pt, half_w, current_h, channel_height_map)
		plateau_remaining -= 1


func _stamp_width(pt: Vector2i, half_w: int, h: int, channel_height_map: Dictionary) -> void:
	for dz in range(-half_w, half_w + 1):
		for dx in range(-half_w, half_w + 1):
			var px: int = pt.x + dx
			var pz: int = pt.y + dz
			if px < 0 or px >= width or pz < 0 or pz >= depth:
				continue
			# Enforce 2-cell exclusion zone on left/top edges
			if px < 2 or pz < 2:
				continue
			var cell := Vector2i(px, pz)
			if not channel_height_map.has(cell) or channel_height_map[cell] > h:
				channel_height_map[cell] = h


func _label_channel_cells() -> void:
	var channel_set := {}
	for cell in channel_cells:
		channel_set[cell] = true

	var edge_set := {}
	var waterfall_set := {}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for cell in channel_cells:
		var my_h: int = heightmap[cell.y * width + cell.x]
		var is_edge: bool = false
		var is_waterfall: bool = false

		for dir in dirs:
			var nx: int = cell.x + dir.x
			var nz: int = cell.y + dir.y

			if nx < 0 or nx >= width or nz < 0 or nz >= depth:
				is_edge = true
				continue

			var neighbor := Vector2i(nx, nz)
			if channel_set.has(neighbor):
				var n_h: int = heightmap[nz * width + nx]
				if n_h != my_h:
					is_waterfall = true
			else:
				is_edge = true

		if is_edge:
			edge_set[cell] = true
		if is_waterfall:
			waterfall_set[cell] = true

	channel_edge_cells = edge_set.keys()
	channel_waterfall_cells = waterfall_set.keys()
