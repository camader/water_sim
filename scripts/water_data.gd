class_name WaterData
extends RefCounted

var width: int
var depth: int
var water: PackedFloat32Array
var flow_right: PackedFloat32Array  # flow on +X edge of each cell
var flow_down: PackedFloat32Array   # flow on +Z edge of each cell
var _terrain: RefCounted  # TerrainData

var sources: Array = []
var source_rate: float = 2.0
var gravity: float = 9.8
var friction: float = 0.995
var min_water: float = 0.001


func _init(terrain: RefCounted) -> void:
	_terrain = terrain
	width = terrain.width
	depth = terrain.depth
	var size: int = width * depth
	water = PackedFloat32Array()
	water.resize(size)
	flow_right = PackedFloat32Array()
	flow_right.resize(size)
	flow_down = PackedFloat32Array()
	flow_down.resize(size)


func reset() -> void:
	water.fill(0.0)
	flow_right.fill(0.0)
	flow_down.fill(0.0)


func get_water(x: int, z: int) -> float:
	return water[z * width + x]


func clear_cell(x: int, z: int) -> void:
	var idx: int = z * width + x
	water[idx] = 0.0
	# Clear pipe flows touching this cell
	flow_right[idx] = 0.0
	flow_down[idx] = 0.0
	if x > 0:
		flow_right[idx - 1] = 0.0
	if z > 0:
		flow_down[idx - width] = 0.0


func get_total_height(x: int, z: int) -> float:
	var idx: int = z * width + x
	return float(_terrain.heightmap[idx]) + water[idx]


func simulate(delta: float) -> void:
	# Add water at sources
	for src in sources:
		var idx: int = src.y * width + src.x
		water[idx] += source_rate * delta

	# Step 1: Accelerate pipes based on pressure difference
	for z in depth:
		for x in width:
			var idx: int = z * width + x
			var total: float = float(_terrain.heightmap[idx]) + water[idx]

			# Right pipe (+X): accelerate by height diff between this cell and right neighbor
			if x < width - 1:
				var ridx: int = idx + 1
				var r_total: float = float(_terrain.heightmap[ridx]) + water[ridx]
				flow_right[idx] += (total - r_total) * gravity * delta

			# Down pipe (+Z): accelerate by height diff between this cell and down neighbor
			if z < depth - 1:
				var didx: int = idx + width
				var d_total: float = float(_terrain.heightmap[didx]) + water[didx]
				flow_down[idx] += (total - d_total) * gravity * delta

	# Step 2: Apply friction
	for i in flow_right.size():
		flow_right[i] *= friction
		flow_down[i] *= friction

	# Step 3: Scale outgoing flows so cells don't go negative
	for z in depth:
		for x in width:
			var idx: int = z * width + x
			var out_flow: float = 0.0

			# Right edge (positive = outgoing)
			if x < width - 1 and flow_right[idx] > 0.0:
				out_flow += flow_right[idx]
			# Left edge: this cell's left pipe is flow_right[idx - 1] negative
			if x > 0 and flow_right[idx - 1] < 0.0:
				out_flow += -flow_right[idx - 1]
			# Down edge (positive = outgoing)
			if z < depth - 1 and flow_down[idx] > 0.0:
				out_flow += flow_down[idx]
			# Up edge: this cell's up pipe is flow_down[idx - width] negative
			if z > 0 and flow_down[idx - width] < 0.0:
				out_flow += -flow_down[idx - width]

			# Edge sinks: outgoing flow at map boundaries
			if x == 0:
				# Left boundary: implicit leftward pipe
				# We don't store this, but water can drain. Handle in transfer step.
				pass
			if x == width - 1:
				if flow_right[idx] > 0.0:
					out_flow += flow_right[idx]
			if z == 0:
				pass
			if z == depth - 1:
				if flow_down[idx] > 0.0:
					out_flow += flow_down[idx]

			out_flow *= delta
			if out_flow > 0.0 and out_flow > water[idx]:
				var scale: float = water[idx] / out_flow if out_flow > 0.0 else 0.0
				# Scale all outgoing pipes for this cell
				if x < width - 1 and flow_right[idx] > 0.0:
					flow_right[idx] *= scale
				if x > 0 and flow_right[idx - 1] < 0.0:
					flow_right[idx - 1] *= scale
				if z < depth - 1 and flow_down[idx] > 0.0:
					flow_down[idx] *= scale
				if z > 0 and flow_down[idx - width] < 0.0:
					flow_down[idx - width] *= scale

	# Step 4: Transfer water along pipes
	for z in depth:
		for x in width:
			var idx: int = z * width + x

			# Right pipe
			if x < width - 1:
				var f: float = flow_right[idx] * delta
				water[idx] -= f
				water[idx + 1] += f
			elif flow_right[idx] > 0.0:
				# Right boundary sink: water leaves the map
				water[idx] -= flow_right[idx] * delta
				flow_right[idx] = 0.0

			# Down pipe
			if z < depth - 1:
				var f: float = flow_down[idx] * delta
				water[idx] -= f
				water[idx + width] += f
			elif flow_down[idx] > 0.0:
				# Bottom boundary sink: water leaves the map
				water[idx] -= flow_down[idx] * delta
				flow_down[idx] = 0.0

	# Step 5: Clamp negatives and tiny values
	for i in water.size():
		if water[i] < min_water:
			water[i] = 0.0
