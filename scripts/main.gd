extends Node3D

const TerrainDataScript = preload("res://scripts/terrain_data.gd")
const WaterDataScript = preload("res://scripts/water_data.gd")

enum EditMode { ADD_BLOCK, REMOVE_BLOCK }

@export var map_width: int = 72
@export var map_depth: int = 72
@export var max_height: int = 10
@export var terrace_size: float = 2.0

var _terrain_data: RefCounted
var _water_data: RefCounted
var _paused: bool = false
var _edit_mode: EditMode = EditMode.ADD_BLOCK

@onready var _renderer: MultiMeshInstance3D = $TerrainRenderer
@onready var _water_renderer: MultiMeshInstance3D = $WaterRenderer
@onready var _camera: Camera3D = $Camera

var _ui_label: Label


func _ready() -> void:
	_setup_lighting()
	_setup_ui()
	_terrain_data = TerrainDataScript.new(map_width, map_depth, max_height, terrace_size)
	_generate_map()


func _process(delta: float) -> void:
	if not _paused and _water_data:
		_water_data.simulate(delta)
		_water_renderer.render(_terrain_data, _water_data)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_R:
				_generate_map()
			KEY_SPACE:
				_paused = not _paused
				_update_ui()
			KEY_1:
				_edit_mode = EditMode.ADD_BLOCK
				_update_ui()
			KEY_2:
				_edit_mode = EditMode.REMOVE_BLOCK
				_update_ui()
			KEY_ESCAPE:
				get_tree().quit()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)


func _generate_map() -> void:
	_terrain_data.generate(42)

	_water_data = WaterDataScript.new(_terrain_data)
	_water_data.sources = _terrain_data.source_cells

	_renderer.render(_terrain_data, _water_data.sources, _terrain_data.channel_cells)
	_water_renderer.render(_terrain_data, _water_data)


func _handle_click(screen_pos: Vector2) -> void:
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var direction: Vector3 = _camera.project_ray_normal(screen_pos)

	var half_w: float = _terrain_data.width / 2.0
	var half_d: float = _terrain_data.depth / 2.0

	# March along the ray and check against the block grid
	var best_t: float = INF
	var best_cell := Vector2i(-1, -1)

	# For each cell, test ray against the top face of the column
	for z in _terrain_data.depth:
		for x in _terrain_data.width:
			var h: float = float(_terrain_data.get_height(x, z))
			var box_min := Vector3(x - half_w, 0.0, z - half_d)
			var box_max := Vector3(x - half_w + 1.0, h, z - half_d + 1.0)

			var t := _ray_box_intersect(origin, direction, box_min, box_max)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_cell = Vector2i(x, z)

	if best_cell.x < 0:
		return

	var cx: int = best_cell.x
	var cz: int = best_cell.y
	var current_h: int = _terrain_data.get_height(cx, cz)

	match _edit_mode:
		EditMode.ADD_BLOCK:
			_terrain_data.set_height(cx, cz, current_h + 1)
		EditMode.REMOVE_BLOCK:
			_terrain_data.set_height(cx, cz, current_h - 1)

	_water_data.clear_cell(cx, cz)
	_renderer.render(_terrain_data, _water_data.sources, _terrain_data.channel_cells)


func _ray_box_intersect(origin: Vector3, dir: Vector3, box_min: Vector3, box_max: Vector3) -> float:
	var tmin: float = -INF
	var tmax: float = INF

	for i in 3:
		if absf(dir[i]) < 1e-8:
			if origin[i] < box_min[i] or origin[i] > box_max[i]:
				return -1.0
		else:
			var t1: float = (box_min[i] - origin[i]) / dir[i]
			var t2: float = (box_max[i] - origin[i]) / dir[i]
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0

	return tmin if tmin >= 0.0 else tmax


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_ui_label = Label.new()
	_ui_label.position = Vector2(10, 10)
	_ui_label.add_theme_font_size_override("font_size", 18)
	_ui_label.add_theme_color_override("font_color", Color.WHITE)
	_ui_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_ui_label.add_theme_constant_override("shadow_offset_x", 1)
	_ui_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_ui_label)
	_update_ui()


func _update_ui() -> void:
	var mode_str: String
	match _edit_mode:
		EditMode.ADD_BLOCK:
			mode_str = "Add Block [1]"
		EditMode.REMOVE_BLOCK:
			mode_str = "Remove Block [2]"
	var pause_str: String = "  PAUSED" if _paused else ""
	_ui_label.text = "Mode: %s%s\nR: Reset  Space: Pause  LClick: Edit" % [mode_str, pause_str]


func _setup_lighting() -> void:
	# Directional sun light
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.5
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)

	# Environment with ambient light
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.6, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
