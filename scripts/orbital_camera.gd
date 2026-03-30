extends Camera3D

@export var target: Vector3 = Vector3.ZERO
@export var distance: float = 60.0
@export var min_distance: float = 5.0
@export var max_distance: float = 150.0
@export var rotate_speed: float = 0.005
@export var zoom_speed: float = 2.0
@export var pan_speed: float = 0.1

var yaw: float = PI / 4.0
var pitch: float = 0.7  # ~40 degrees

var _is_rotating: bool = false
var _is_panning: bool = false


func _ready() -> void:
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				if mb.shift_pressed:
					_is_panning = mb.pressed
					_is_rotating = false
				else:
					_is_rotating = mb.pressed
					_is_panning = false
			MOUSE_BUTTON_RIGHT:
				_is_rotating = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = maxf(min_distance, distance - zoom_speed)
					_update_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = minf(max_distance, distance + zoom_speed)
					_update_transform()

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _is_rotating:
			yaw -= motion.relative.x * rotate_speed
			pitch = clampf(pitch + motion.relative.y * rotate_speed, 0.1, PI / 2.0 - 0.01)
			_update_transform()
		elif _is_panning:
			var right := global_transform.basis.x
			var forward := Vector3(right.z, 0, -right.x).normalized()
			target += right * (-motion.relative.x * pan_speed)
			target += forward * (-motion.relative.y * pan_speed)
			_update_transform()


func _update_transform() -> void:
	var offset := Vector3(
		distance * cos(pitch) * sin(yaw),
		distance * sin(pitch),
		distance * cos(pitch) * cos(yaw)
	)
	global_position = target + offset
	look_at(target, Vector3.UP)
