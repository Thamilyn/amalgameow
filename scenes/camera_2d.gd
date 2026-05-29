extends Camera2D

@export var target : Node2D
@export var h_lookahead : float = 80.0
@export var smoothing   : float = 6.0

# Horizontal bounds – set these to match your stage width.
@export var bound_left  : float = 0.0
@export var bound_right : float = 2000.0

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var desired_x = target.global_position.x + target.get("_facing") * h_lookahead
	var desired_y := 360.0  # fixed vertical – typical SOR camera locks Y
	var desired   := Vector2(desired_x, desired_y)
	global_position = global_position.lerp(desired, smoothing * delta)
	# Clamp so we never scroll past stage edges.
	global_position.x = clamp(
		global_position.x,
		bound_left  + get_viewport_rect().size.x * 0.5 / zoom.x,
		bound_right - get_viewport_rect().size.x * 0.5 / zoom.x
	)
