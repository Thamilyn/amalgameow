extends CharacterBody2D

# ---------------------------------------------------------------------------
# Boss – HP mechanic + Hammer Fist attack
# ---------------------------------------------------------------------------

# ── Exports ─────────────────────────────────────────────────────────────────
@export var player : CharacterBody2D
@export var main : Node2D
@export var player_sigth_distance := 600.0
@export_group("Health")
@export var max_hp          : int   = 50

@export_group("Movement")
@export var detection_range : float = 500.0
@export var attack_range    : float = 150.0

@export_group("Hammer Fist")
@export var hammer_damage   : float = 15.0
@export var hammer_cooldown : float = 2.0   ## Seconds between attacks


@onready var animated_sprite2d := $AnimatedSprite2D

# ── Constants ────────────────────────────────────────────────────────────────

const MOVE_SPEED          : float = 90.0

# Fist X positions – fist moves horizontally only (Y is always 0)
const FIST_IDLE_X         : float = 16.0    # resting
const FIST_RAISED_X       : float = 8.0     # pulled back during windup
const FIST_SLAMMED_X      : float = 160.0   # fully extended during slam

# ── State machine ────────────────────────────────────────────────────────────

enum State {
	IDLE,
	INTRO,
	CHASE,
	HAMMER_WINDUP,
	HAMMER_SLAM,
	HAMMER_RECOVER,
	DIE,
}

# ── Node references ──────────────────────────────────────────────────────────

@onready var hammer_fist    : Node2D           = $HammerFist
@onready var fist_collision : CollisionShape2D = $HammerFist/FistHitbox/CollisionShape2D
@onready var hp_bar         : ProgressBar      = $HPBar
@onready var laugh          : AudioStreamPlayer = $Laugh

# ── Runtime state ────────────────────────────────────────────────────────────

var current_hp    : int   = 0  # initialised in _ready from max_hp
var current_state : State = State.IDLE

var _facing       : float  = 1.0    # +1 = right, -1 = left
var _attack_timer : float  = 0.0    # cooldown remaining
var _intro_played : bool   = false  # true after the first-encounter cutscene

var starting_position := Vector2.ZERO

signal boss_died

# ── Ready ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	current_hp       = max_hp
	hp_bar.max_value = max_hp
	hp_bar.value     = current_hp
	fist_collision.disabled = true
	hammer_fist.position    = Vector2(FIST_IDLE_X, 0.0)
	starting_position = position
	main.connect("stage_restarted", reset_boss)

# ── Physics loop ─────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if current_state == State.DIE:
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)

	match current_state:
		State.IDLE:
			_state_idle()
		State.CHASE:
			_state_chase()
		# Hammer states are tween-driven; just brake horizontal movement
		State.HAMMER_WINDUP, State.HAMMER_SLAM, State.HAMMER_RECOVER, State.INTRO:
			velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
			move_and_slide()

	_sync_fist_side()

# ── State logic ───────────────────────────────────────────────────────────────

func _state_idle() -> void:
	velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
	move_and_slide()
	if is_instance_valid(player):
		if global_position.distance_to(player.global_position) <= detection_range:
			_enter_state(State.INTRO if not _intro_played else State.CHASE)


func _state_chase() -> void:
	if not is_instance_valid(player):
		_enter_state(State.IDLE)
		return

	var dist : float  = global_position.distance_to(player.global_position)
	var dir  : Vector2 = (player.global_position - global_position).normalized()

	if dist > detection_range * 1.2:
		_enter_state(State.IDLE)
		return
	if dist <= attack_range and _attack_timer <= 0.0:
		_enter_state(State.HAMMER_WINDUP)
		return

	if dir.x != 0.0:
		_facing = sign(dir.x)
		animated_sprite2d.flip_h = _facing < 0.0
	velocity.x = dir.x * MOVE_SPEED
	move_and_slide()

# ── State transitions ─────────────────────────────────────────────────────────

func _enter_state(new_state: State) -> void:
	if new_state == current_state:
		return
	current_state = new_state

	match new_state:

		State.IDLE:
			laugh.play()
			animated_sprite2d.play("idle")

		State.INTRO:
			_intro_played = true
			animated_sprite2d.play("boss_intro")
			var timer := get_tree().create_timer(1.5)
			timer.timeout.connect(func() -> void: _enter_state(State.CHASE))

		State.CHASE:
			animated_sprite2d.play("idle")

		# Phase 1: pull the fist back (wind-up telegraph)
		State.HAMMER_WINDUP:
			animated_sprite2d.play("attack")
			var tween := create_tween()
			tween.tween_property(
				hammer_fist, "position",
				Vector2(FIST_RAISED_X * _facing, 0.0),
				0.45
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_callback(_begin_slam)

		# Phase 2: shoot the fist forward, hitbox active
		State.HAMMER_SLAM:
			fist_collision.disabled = false
			var tween := create_tween()
			tween.tween_property(
				hammer_fist, "position",
				Vector2(FIST_SLAMMED_X * _facing, 0.0),
				0.3
			).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			tween.tween_callback(_begin_recover)

		# Phase 3: deactivate hitbox and return fist to idle
		State.HAMMER_RECOVER:
			fist_collision.disabled = true
			_attack_timer = hammer_cooldown
			var tween := create_tween()
			tween.tween_property(
				hammer_fist, "position",
				Vector2(FIST_IDLE_X * _facing, 0.0),
				0.6
			).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_callback(_end_recover)

		State.DIE:
			set_physics_process(false)
			fist_collision.call_deferred("set_disabled", true)
			#fist_collision.disabled = true
			emit_signal("boss_died")
			var tween := create_tween()
			tween.tween_property(self, "modulate:a", 0.0, 1.2) \
				.set_trans(Tween.TRANS_SINE)
			tween.tween_callback(queue_free)


# ── Attack phase callbacks ────────────────────────────────────────────────────

func _begin_slam() -> void:
	_enter_state(State.HAMMER_SLAM)


func _begin_recover() -> void:
	_enter_state(State.HAMMER_RECOVER)


func _end_recover() -> void:
	if is_instance_valid(player):
		_enter_state(State.CHASE)
	else:
		_enter_state(State.IDLE)

# ── Helpers ───────────────────────────────────────────────────────────────────

# Keep the fist on the correct side of the boss when not in an attack sequence.
func _sync_fist_side() -> void:
	if current_state == State.IDLE or current_state == State.CHASE:
		hammer_fist.position.x = absf(hammer_fist.position.x) * _facing

# ── Public API ────────────────────────────────────────────────────────────────

## Reduce boss HP by `amount`. Call from player hitbox callbacks.
func take_damage(amount: float = 1.0) -> void:
	if current_state == State.DIE:
		return
	current_hp  = max(current_hp - int(amount), 0)
	hp_bar.value = current_hp
	if current_hp <= 0:
		_enter_state(State.DIE)


func _on_fist_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(hammer_damage)

func reset_boss():
	current_hp = max_hp
	position = starting_position
