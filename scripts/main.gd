extends Node3D

const TerrainDataScript = preload("res://scripts/terrain_data.gd")

@export var map_width: int = 64
@export var map_depth: int = 64
@export var max_height: int = 10
@export var terrace_size: float = 2.0

var _terrain_data: RefCounted

@onready var _renderer: MultiMeshInstance3D = $TerrainRenderer
@onready var _camera: Camera3D = $Camera


func _ready() -> void:
	_setup_lighting()
	_terrain_data = TerrainDataScript.new(map_width, map_depth, max_height, terrace_size)
	_generate_map()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_R:
				_generate_map()
			KEY_ESCAPE:
				get_tree().quit()


func _generate_map() -> void:
	_terrain_data.generate(randi())
	_renderer.render(_terrain_data)


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
