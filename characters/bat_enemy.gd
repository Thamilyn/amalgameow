extends CharacterBody2D

# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

enum States {
	Patrol,
	Chase,
	Attack,
	Die
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var patrol_distance_origin := 100
@export var patrol_speed           := 60.0
@export var chase_speed            := 120.0
@export var detection_range        := 200.0
@export var attack_range           := 40.0
## How far the player can be before the bat gives up chasing
@export var leash_range            := 320.0

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# ---------------------------------------------------------------------------
# State vars
# ---------------------------------------------------------------------------

var current_state: States = States.Patrol
var player: Node2D       = null

# Patrol waypoints
var _patrol_point_a:  Vector2
var _patrol_point_b:  Vector2
var _patrol_going_b:  bool = true   # true → heading toward B, false → heading toward A

# Guards so we don't re-enter the same state
var _attack_in_progress: bool = false

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	_patrol_point_a = global_position + Vector2(-patrol_distance_origin, 0.0)
	_patrol_point_b = global_position + Vector2( patrol_distance_origin, 0.0)
	_enter_state(States.Patrol)

# ---------------------------------------------------------------------------
# Physics loop
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	# Lazily grab the player node (must be in the "player" group)
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	match current_state:
		States.Patrol:
			_state_patrol()
		States.Chase:
			_state_chase()
		States.Attack:
			_state_attack()
		States.Die:
			pass   # animation plays, then queue_free

# ---------------------------------------------------------------------------
# State logic
# ---------------------------------------------------------------------------

func _state_patrol() -> void:
	var target: Vector2 = _patrol_point_b if _patrol_going_b else _patrol_point_a
	var to_target: Vector2 = target - global_position

	# Reached waypoint → flip direction
	if to_target.length() < 4.0:
		_patrol_going_b = not _patrol_going_b
		return

	velocity = to_target.normalized() * patrol_speed
	anim.flip_h = velocity.x < 0.0
	move_and_slide()

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

	# Close enough to attack
	if dist <= attack_range:
		_enter_state(States.Attack)
		return

	# Move toward player
	var direction: Vector2 = (player.global_position - global_position).normalized()
	velocity = direction * chase_speed
	anim.flip_h = velocity.x < 0.0
	move_and_slide()


func _state_attack() -> void:
	# Stop moving while attacking; the animation drives the action
	velocity = Vector2.ZERO
	move_and_slide()


# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------

func _enter_state(new_state: States) -> void:
	if new_state == current_state:
		return

	current_state = new_state

	match new_state:
		States.Patrol:
			_attack_in_progress = false
			anim.play("flight")

		States.Chase:
			_attack_in_progress = false
			anim.play("flight")

		States.Attack:
			_attack_in_progress = true
			anim.play("attack")
			# Return to Chase once the attack animation ends
			if not anim.animation_finished.is_connected(_on_attack_finished):
				anim.animation_finished.connect(_on_attack_finished, CONNECT_ONE_SHOT)

		States.Die:
			_attack_in_progress = false
			set_physics_process(false)
			anim.play("death")
			if not anim.animation_finished.is_connected(_on_death_finished):
				anim.animation_finished.connect(_on_death_finished, CONNECT_ONE_SHOT)

# ---------------------------------------------------------------------------
# Animation callbacks
# ---------------------------------------------------------------------------

func _on_attack_finished() -> void:
	if current_state != States.Attack:
		return

	# Decide where to go after the attack
	if is_instance_valid(player):
		var dist: float = global_position.distance_to(player.global_position)
		if dist <= attack_range:
			# Player still in range → attack again
			_attack_in_progress = false          # allow re-entry
			current_state       = States.Chase   # fake-reset so _enter_state fires
			_enter_state(States.Attack)
		elif dist <= leash_range:
			_enter_state(States.Chase)
		else:
			_enter_state(States.Patrol)
	else:
		_enter_state(States.Patrol)


func _on_death_finished() -> void:
	queue_free()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Call this from a hitbox / area callback to kill the bat.
func take_damage(_damage: int = 1) -> void:
	if current_state == States.Die:
		return
	_enter_state(States.Die)
