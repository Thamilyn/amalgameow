extends CharacterBody2D

# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

enum States {
	Patrol,
	Shoot,
	Die,
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var max_hp              := 30
@export var patrol_speed        := 60.0
@export var patrol_distance     := 120.0
@export var detection_range     := 300.0
## How far the player can be before the enemy stops shooting and resumes patrol
@export var leash_range         := 400.0
@export var shoot_cooldown      := 1.5

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var sprite: Sprite2D = $Sprite2D

# ---------------------------------------------------------------------------
# State vars
# ---------------------------------------------------------------------------

const BULLETS = preload("res://characters/tag_bullets.tscn")

var current_state := States.Patrol
var player: Node2D = null
var hp: int

var _patrol_point_a: Vector2
var _patrol_point_b: Vector2
var _patrol_going_b := true

var _shoot_timer := 0.0

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	hp = max_hp
	_patrol_point_a = global_position + Vector2(-patrol_distance, 0.0)
	_patrol_point_b = global_position + Vector2( patrol_distance, 0.0)

# ---------------------------------------------------------------------------
# Physics loop
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Lazily find the player
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	match current_state:
		States.Patrol:
			_state_patrol()
		States.Shoot:
			_state_shoot(delta)
		States.Die:
			pass

# ---------------------------------------------------------------------------
# State logic
# ---------------------------------------------------------------------------

func _state_patrol() -> void:
	var target := _patrol_point_b if _patrol_going_b else _patrol_point_a
	var to_target := target - global_position

	if to_target.length() < 4.0:
		_patrol_going_b = not _patrol_going_b
		velocity.x = 0.0
	else:
		velocity.x = to_target.normalized().x * patrol_speed
		_set_facing(velocity.x < 0.0)

	move_and_slide()

	if is_instance_valid(player):
		if global_position.distance_to(player.global_position) <= detection_range:
			_enter_state(States.Shoot)


func _state_shoot(delta: float) -> void:
	# Slow to a stop while shooting
	velocity.x = move_toward(velocity.x, 0.0, patrol_speed * 4.0)
	move_and_slide()

	if not is_instance_valid(player):
		_enter_state(States.Patrol)
		return

	var dist := global_position.distance_to(player.global_position)
	if dist > leash_range:
		_enter_state(States.Patrol)
		return

	# Face the player
	_set_facing(player.global_position.x < global_position.x)

	# Countdown and fire
	_shoot_timer -= delta
	if _shoot_timer <= 0.0:
		_fire_bullet()
		_shoot_timer = shoot_cooldown

# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------

func _enter_state(new_state: States) -> void:
	if new_state == current_state:
		return
	current_state = new_state

	match new_state:
		States.Patrol:
			_shoot_timer = 0.0

		States.Shoot:
			# Fire immediately when the player is first spotted
			_shoot_timer = 0.0

		States.Die:
			set_physics_process(false)
			queue_free()

# ---------------------------------------------------------------------------
# Firing
# ---------------------------------------------------------------------------

func _fire_bullet() -> void:
	if not is_instance_valid(player):
		return
	var bullet: Area2D = BULLETS.instantiate()
	bullet.direction = (player.global_position - global_position).normalized()
	# Spawn at the enemy's centre so the bullet doesn't collide with it
	bullet.global_position = global_position
	get_parent().add_child(bullet)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _set_facing(facing_left: bool) -> void:
	sprite.flip_h = facing_left

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func take_damage(damage: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if current_state == States.Die:
		return
	hp -= damage
	if hp <= 0:
		_enter_state(States.Die)
