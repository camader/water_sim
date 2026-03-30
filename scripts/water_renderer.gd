extends MultiMeshInstance3D

var _material: StandardMaterial3D
var _box: BoxMesh
var _water_color := Color(0.2, 0.4, 0.8, 0.6)
var _min_visible: float = 0.01


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = _water_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_box = BoxMesh.new()
	_box.size = Vector3(1.0, 1.0, 1.0)
	_box.material = _material


func render(terrain: RefCounted, water: RefCounted) -> void:
	# Count visible water cells
	var visible_count: int = 0
	for i in water.water.size():
		if water.water[i] > _min_visible:
			visible_count += 1

	if visible_count == 0:
		multimesh = null
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = visible_count
	mm.mesh = _box

	var half_w: float = terrain.width / 2.0
	var half_d: float = terrain.depth / 2.0
	var instance_idx: int = 0

	for z in water.depth:
		for x in water.width:
			var w: float = water.get_water(x, z)
			if w <= _min_visible:
				continue

			var terrain_h: float = float(terrain.get_height(x, z))
			var xform := Transform3D(
				Basis(Vector3(1, 0, 0), Vector3(0, w, 0), Vector3(0, 0, 1)),
				Vector3(x - half_w + 0.5, terrain_h + w / 2.0, z - half_d + 0.5)
			)
			mm.set_instance_transform(instance_idx, xform)
			instance_idx += 1

	multimesh = mm
