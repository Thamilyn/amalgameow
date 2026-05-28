extends CharacterBody2D

# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

enum States {
	Patrol,
	Chase,
	Explode
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var patrol_distance_origin := 80
@export var patrol_speed           := 50.0
@export var chase_speed            := 100.0
@export var detection_range        := 180.0
## Distance at which the tweet explodes on the player
@export var explosion_range        := 40.0
## Damage dealt to the player on explosion
@export var explosion_damage       := 25.0
## How far the player can be before the tweet gives up chasing
@export var leash_range            := 300.0

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var sprite: Sprite2D = $Sprite2D

# ---------------------------------------------------------------------------
# State vars
# ---------------------------------------------------------------------------

var current_state: States = States.Patrol
var player: Node2D        = null

# Patrol waypoints
var _patrol_point_a: Vector2
var _patrol_point_b: Vector2
var _patrol_going_b: bool = true

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	_patrol_point_a = global_position + Vector2(-patrol_distance_origin, 0.0)
	_patrol_point_b = global_position + Vector2( patrol_distance_origin, 0.0)

# ---------------------------------------------------------------------------
# Physics loop
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Lazily grab the player node (must be in the "player" group)
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	match current_state:
		States.Patrol:
			_state_patrol()
		States.Chase:
			_state_chase()
		States.Explode:
			pass

	move_and_slide()

# ---------------------------------------------------------------------------
# State logic
# ---------------------------------------------------------------------------

func _state_patrol() -> void:
	var target: Vector2    = _patrol_point_b if _patrol_going_b else _patrol_point_a
	var to_target: Vector2 = target - global_position

	# Reached waypoint (horizontal only) → flip direction
	if abs(to_target.x) < 4.0:
		_patrol_going_b = not _patrol_going_b
		velocity.x = 0.0
		return

	velocity.x = sign(to_target.x) * patrol_speed
	velocity.y = 0.0
	_set_facing(velocity.x < 0.0)

	# Transition: player enters detection range
	if is_instance_valid(player):
		if global_position.distance_to(player.global_position) <= detection_range:
			_enter_state(States.Chase)


func _state_chase() -> void:
	if not is_instance_valid(player):
		_enter_state(States.Patrol)
		return

	var dist: float = global_position.distance_to(player.global_position)

	# Lost the player
	if dist > leash_range:
		_enter_state(States.Patrol)
		return

	# Close enough to explode
	print(dist)
	if dist <= explosion_range:
		_enter_state(States.Explode)
		return

	# Move toward player in full 2D
	var direction: Vector2 = (player.global_position - global_position).normalized()
	velocity = direction * chase_speed
	_set_facing(direction.x < 0.0)

# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------

func _enter_state(new_state: States) -> void:
	if new_state == current_state:
		return

	current_state = new_state

	match new_state:
		States.Patrol:
			velocity.x = 0.0

		States.Chase:
			pass

		States.Explode:
			velocity = Vector2.ZERO
			set_physics_process(false)
			_deal_explosion_damage()
			queue_free()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _deal_explosion_damage() -> void:
	if is_instance_valid(player):
		var dist: float = global_position.distance_to(player.global_position)
		if dist <= explosion_range and player.has_method("take_damage"):
			player.take_damage(explosion_damage)


func _set_facing(facing_left: bool) -> void:
	sprite.flip_h = facing_left

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Taking damage also triggers the explosion (contact detonation).
func take_damage(_damage: int = 1) -> void:
	if current_state == States.Explode:
		return
	_enter_state(States.Explode)
