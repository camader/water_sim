extends MultiMeshInstance3D

const TerrainDataScript = preload("res://scripts/terrain_data.gd")

var _color_gradient: Gradient


func _ready() -> void:
	_color_gradient = Gradient.new()
	_color_gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	_color_gradient.colors = PackedColorArray([
		Color(0.15, 0.30, 0.20),  # Dark green - valley floor
		Color(0.20, 0.55, 0.15),  # Green - lowlands
		Color(0.60, 0.55, 0.30),  # Tan - mid plateau
		Color(0.65, 0.60, 0.55),  # Grey - high rock
	])


func render(terrain: RefCounted) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = terrain.width * terrain.depth

	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	box.material = mat

	mm.mesh = box

	var half_w: float = terrain.width / 2.0
	var half_d: float = terrain.depth / 2.0

	for z in terrain.depth:
		for x in terrain.width:
			var idx: int = z * terrain.width + x
			var h: float = float(terrain.get_height(x, z))

			var xform := Transform3D(
				Basis(Vector3(1, 0, 0), Vector3(0, h, 0), Vector3(0, 0, 1)),
				Vector3(x - half_w + 0.5, h / 2.0, z - half_d + 0.5)
			)
			mm.set_instance_transform(idx, xform)

			var t: float = (h - 1.0) / float(terrain.max_height - 1) if terrain.max_height > 1 else 0.0
			mm.set_instance_color(idx, _color_gradient.sample(t))

	multimesh = mm
