extends CharacterBody2D

# ---------------------------------------------------------------------------
# Streets of Rage 4 – style player controller
# ---------------------------------------------------------------------------
# Architecture overview:
#   • Pseudo-3D / 2.5D movement: X = horizontal, Y = depth (the "lane").
#     A separate _z_velocity drives a real vertical arc for jumps, and the
#     node's visual Y position is offset by that arc height.
#   • Finite State Machine with explicit State enum.
#   • Input buffer so that attack presses during animations are honoured.
#   • Combo string: up to MAX_COMBO_HITS light attacks before a finisher.
#   • Dodge roll with i-frames.
#   • Hitstop (time-freeze effect on hit).
# ---------------------------------------------------------------------------

# ── Constants ───────────────────────────────────────────────────────────────

const WALK_SPEED        : float = 180.0   # px / s  (horizontal + depth)
const RUN_SPEED         : float = 320.0   # px / s  (after dash input)
const RUN_THRESHOLD     : float = 0.15    # seconds between two taps to trigger run
const JUMP_VELOCITY     : float = -520.0  # initial upward z-velocity
const GRAVITY           : float = 1200.0  # z-axis gravity (px / s²)
const DODGE_SPEED       : float = 400.0   # px / s during dodge roll
const DODGE_DURATION    : float = 0.5    # seconds
const DODGE_IFRAME_TIME : float = 0.3    # seconds of invincibility inside dodge
const KNOCKBACK_DECAY   : float = 8.0     # how fast knockback velocity bleeds off
const MAX_COMBO_HITS    : int   = 3       # light attacks before the finisher
const COMBO_WINDOW      : float = 0.55    # seconds to keep combo alive
const INPUT_BUFFER_TIME : float = 0.16    # seconds an input stays buffered
const HITSTOP_DURATION  : float = 0.07   # seconds of time-freeze on hit

# Depth (Y) is clamped so the player stays inside the "stage lane".
const LANE_TOP    : float = 280.0
const LANE_BOTTOM : float = 480.0

# ── State machine ───────────────────────────────────────────────────────────

enum State {
	IDLE,
	WALK,
	RUN,
	JUMP,
	ATTACK_LIGHT,
	ATTACK_FINISHER,
	ATTACK_AIR,
	DODGE,
	HURT,
	KNOCKED_DOWN,
	GET_UP,
}

# ── Node references (adjust to your actual scene tree) ──────────────────────

@onready var sprite       : Sprite2D        = $Sprite2D
@onready var anim         : AnimationPlayer = $AnimationPlayer   # optional – safe-guarded below
@onready var hitbox       : Area2D          = $Hitbox            # optional – safe-guarded below
@onready var hurtbox      : Area2D          = $Hurtbox           # optional – safe-guarded below
@onready var animated_sprite2d : AnimatedSprite2D = $AnimatedSprite2D

# ── Internal state ───────────────────────────────────────────────────────────

var state           : State = State.IDLE
var prev_state      : State = State.IDLE

# Movement
var _z_pos          : float = 0.0   # visual height above ground (for jump arc)
var _z_velocity     : float = 0.0   # vertical (jump) velocity
var _air_attack_used : bool  = false  # only one air attack allowed per jump
var _knockback      : Vector2 = Vector2.ZERO
var _facing         : float = 1.0   # +1 right / -1 left

# Running double-tap detection
var _last_h_tap_dir  : float = 0.0
var _last_h_tap_time : float = -1.0
var _is_running      : bool  = false

# Combo
var _combo_count    : int   = 0
var _combo_timer    : float = 0.0

# Dodge
var _dodge_timer    : float = 0.0
var _dodge_dir      : Vector2 = Vector2.ZERO
var _is_invincible  : bool  = false

# Hitstop
var _hitstop_timer  : float = 0.0

# Input buffer  { "action": String, "time": float }
var _input_buffer   : Array = []

# State timers / flags
var _state_timer    : float = 0.0   # generic "time spent in current state"
var _attack_hit     : bool  = false # did current attack swing already land?

# Health
var max_health      : int = 100
var health          : int = 100

# Signals
signal health_changed(new_health: int)
signal died()
signal attack_landed(damage: int, position: Vector2)

# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Gracefully handle missing optional nodes so the script doesn't crash in
	# a minimal scene (the placeholder player.tscn only has Sprite2D).
	if not has_node("AnimationPlayer"):
		anim = null
	if not has_node("Hitbox"):
		hitbox = null
	if not has_node("Hurtbox"):
		hurtbox = null
	if not has_node("AnimatedSprite2D"):
		animated_sprite2d = null

	if hurtbox:
		hurtbox.area_entered.connect(_on_hurtbox_area_entered)


	_enter_state(State.IDLE)

# ---------------------------------------------------------------------------
# _process  – input buffer + hitstop tick
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Tick hitstop independently of everything else.
	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		return   # freeze all gameplay logic during hitstop

	_tick_input_buffer(delta)
	_poll_inputs()

# ---------------------------------------------------------------------------
# _physics_process  – movement + state machine
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _hitstop_timer > 0.0:
		return

	_state_timer += delta
	match state:
		State.IDLE:
			_state_idle(delta)
		State.WALK:
			_state_walk(delta)
		State.RUN:
			_state_run(delta)
		State.JUMP:
			_state_jump(delta)
		State.ATTACK_LIGHT:
			_state_attack_light(delta)
		State.ATTACK_FINISHER:
			_state_attack_finisher(delta)
		State.ATTACK_AIR:
			_state_attack_air(delta)
		State.DODGE:
			_state_dodge(delta)
		State.HURT:
			_state_hurt(delta)
		State.KNOCKED_DOWN:
			_state_knocked_down(delta)
		State.GET_UP:
			_state_get_up(delta)

	# Apply knockback bleed-off on every state.
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta * 60.0)

	# Clamp depth lane.
	position.y = clamp(position.y, LANE_TOP, LANE_BOTTOM)

	# Apply visual height offset from jump arc.
	sprite.position.y = _z_pos
	if animated_sprite2d:
		animated_sprite2d.position.y = _z_pos

# ---------------------------------------------------------------------------
# Input polling (called every frame from _process)
# ---------------------------------------------------------------------------
func _poll_inputs() -> void:
	# Directional input this frame.
	var h : float = Input.get_axis("ui_left", "ui_right")
	var v : float = Input.get_axis("ui_up",   "ui_down")

	# ── Double-tap run detection ──────────────────────────────────────────
	if h != 0.0 and h != _last_h_tap_dir:
		_last_h_tap_dir  = h
		_last_h_tap_time = Time.get_ticks_msec() / 1000.0
	elif h != 0.0 and h == _last_h_tap_dir:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_h_tap_time < RUN_THRESHOLD and not _is_running:
			_is_running = true
		_last_h_tap_time = now   # reset so we don't keep triggering
	elif h == 0.0:
		_is_running = false

	# ── Attack ────────────────────────────────────────────────────────────
	if Input.is_action_just_pressed("attack_light"):
		_buffer_input("attack_light")
	if Input.is_action_just_pressed("attack_special"):
		_buffer_input("attack_special")

	# ── Jump ──────────────────────────────────────────────────────────────
	if Input.is_action_just_pressed("jump"):
		_buffer_input("jump")

	# ── Dodge ─────────────────────────────────────────────────────────────
	if Input.is_action_just_pressed("dodge"):
		_buffer_input("dodge")

# ---------------------------------------------------------------------------
# Input buffer helpers
# ---------------------------------------------------------------------------
func _buffer_input(action: String) -> void:
	# Remove any existing entry for the same action so it gets a fresh timer.
	_input_buffer = _input_buffer.filter(func(e): return e["action"] != action)
	_input_buffer.append({ "action": action, "time": INPUT_BUFFER_TIME })

func _consume_buffered(action: String) -> bool:
	for i in _input_buffer.size():
		if _input_buffer[i]["action"] == action:
			_input_buffer.remove_at(i)
			return true
	return false

func _tick_input_buffer(delta: float) -> void:
	for entry in _input_buffer:
		entry["time"] -= delta
	_input_buffer = _input_buffer.filter(func(e): return e["time"] > 0.0)

# ---------------------------------------------------------------------------
# State machine helpers
# ---------------------------------------------------------------------------
func _enter_state(new_state: State) -> void:
	prev_state  = state
	state       = new_state
	_state_timer = 0.0
	#print('Entering: ', str(new_state))
	match new_state:
		State.IDLE:
			_air_attack_used = false
			_play_anim("idle")
			velocity = Vector2.ZERO
		State.WALK:
			_play_anim("walk")
		State.RUN:
			_play_anim("run")
		State.JUMP:
			_z_velocity = JUMP_VELOCITY
			_play_anim("jump")
		State.ATTACK_LIGHT:
			_attack_hit = false
			_play_anim("attack_light_%d" % (_combo_count + 1))
		State.ATTACK_FINISHER:
			_attack_hit = false
			_play_anim("attack_finisher")
		State.ATTACK_AIR:
			_attack_hit = false
			_air_attack_used = true
			_play_anim("attack_air")
		State.DODGE:
			_dodge_timer   = DODGE_DURATION
			_is_invincible = true
			var h := Input.get_axis("ui_left", "ui_right")
			var v := Input.get_axis("ui_up",   "ui_down")
			_dodge_dir = Vector2(h, v).normalized()
			if _dodge_dir == Vector2.ZERO:
				_dodge_dir = Vector2(_facing, 0.0)
			_play_anim("dodge")
		State.HURT:
			_play_anim("hurt")
		State.KNOCKED_DOWN:
			_play_anim("knocked_down")
		State.GET_UP:
			_is_invincible = true
			_play_anim("get_up")

# Maps internal state animation names to the AnimatedSprite2D animation library.
const ANIM_MAP : Dictionary = {
	"idle":             "idle",
	"walk":             "walk",
	"run":              "run",
	"jump":             "jump",
	"attack_light_1":   "punch_jab",
	"attack_light_2":   "punch_jab",
	"attack_light_3":   "punch_cross",
	"attack_finisher":  "punch",
	"attack_air":       "air_spin",
	"dodge":            "roll",
	"hurt":             "idle",
	"knocked_down":     "death",
	"get_up":           "idle",
}

# Animations that must loop continuously while their state is active.
const LOOPING_ANIMS : Array[String] = ["idle", "walk", "run"]

# Updates _facing and immediately flips the AnimatedSprite2D.
func _set_facing(dir: float) -> void:
	if dir == 0.0:
		return
	_facing = sign(dir)
	if animated_sprite2d:
		animated_sprite2d.flip_h = _facing < 0.0
	if _facing < 0.0 and hitbox.position.x > 0:
		hitbox.position.x *= -1.0
	elif _facing > 0.0 and hitbox.position.x < 0:
		hitbox.position.x *= -1.0



func _play_anim(anim_name: String) -> void:
	if animated_sprite2d == null:
		return
	var mapped : String = ANIM_MAP.get(anim_name, "run")
	# Force the correct loop mode on the SpriteFrames resource before playing
	# so movement animations loop natively without needing external restarts.
	#if animated_sprite2d.sprite_frames and animated_sprite2d.sprite_frames.has_animation(mapped):
		#animated_sprite2d.sprite_frames.set_animation_loop(mapped, mapped in LOOPING_ANIMS)
	# Avoid restarting the same animation if it is already playing.
	if animated_sprite2d.animation == mapped and animated_sprite2d.is_playing():
		return
	animated_sprite2d.play(mapped)

# ---------------------------------------------------------------------------
# State handlers
# ---------------------------------------------------------------------------

# ── IDLE ─────────────────────────────────────────────────────────────────────
func _state_idle(_delta: float) -> void:
	velocity = _knockback

	var h := Input.get_axis("ui_left", "ui_right")
	var v := Input.get_axis("ui_up",   "ui_down")
	var moving := Vector2(h, v).length() > 0.1

	if _consume_buffered("jump"):
		_enter_state(State.JUMP)
		return
	if _consume_buffered("dodge"):
		_enter_state(State.DODGE)
		return
	if _consume_buffered("attack_light"):
		_combo_count = 0
		_combo_timer = COMBO_WINDOW
		_enter_state(State.ATTACK_LIGHT)
		return
	if moving:
		if _is_running:
			_enter_state(State.RUN)
		else:
			_enter_state(State.WALK)
		return

	move_and_slide()

# ── WALK ─────────────────────────────────────────────────────────────────────
func _state_walk(delta: float) -> void:
	var h := Input.get_axis("ui_left", "ui_right")
	var v := Input.get_axis("ui_up",   "ui_down")
	var dir := Vector2(h, v)

	if dir.length() > 0.1:
		dir = dir.normalized()
		velocity = dir * WALK_SPEED + _knockback
		if h != 0.0:
			_set_facing(h)
	else:
		velocity = _knockback
		_enter_state(State.IDLE)
		return

	if _consume_buffered("jump"):
		_enter_state(State.JUMP)
		return
	if _consume_buffered("dodge"):
		_enter_state(State.DODGE)
		return
	if _consume_buffered("attack_light"):
		_combo_count = 0
		_combo_timer = COMBO_WINDOW
		_enter_state(State.ATTACK_LIGHT)
		return
	if _is_running:
		_enter_state(State.RUN)
		return

	move_and_slide()

# ── RUN ──────────────────────────────────────────────────────────────────────
func _state_run(delta: float) -> void:
	var h := Input.get_axis("ui_left", "ui_right")
	var v := Input.get_axis("ui_up",   "ui_down")
	var dir := Vector2(h, v)

	if dir.length() > 0.1:
		dir = dir.normalized()
		velocity = dir * RUN_SPEED + _knockback
		if h != 0.0:
			_set_facing(h)
	else:
		_is_running = false
		_enter_state(State.IDLE)
		return

	if _consume_buffered("jump"):
		_enter_state(State.JUMP)
		return
	if _consume_buffered("dodge"):
		_enter_state(State.DODGE)
		return
	if _consume_buffered("attack_light"):
		# Running attack – treat as finisher for variety.
		_combo_count = MAX_COMBO_HITS
		_combo_timer = COMBO_WINDOW
		_enter_state(State.ATTACK_FINISHER)
		return
	if not _is_running:
		_enter_state(State.WALK)
		return

	move_and_slide()

# ── JUMP ─────────────────────────────────────────────────────────────────────
func _state_jump(delta: float) -> void:
	# Horizontal movement is preserved in the air (reduced control).
	var h := Input.get_axis("ui_left", "ui_right")
	var v := Input.get_axis("ui_up",   "ui_down")
	var air_control := 1.0
	velocity = Vector2(h, v).normalized() * WALK_SPEED * air_control + _knockback

	if h != 0.0:
		_set_facing(h)

	# Z arc.
	_z_velocity += GRAVITY * delta
	_z_pos      += _z_velocity * delta
	move_areas_on_jump(_z_pos)

	# Landed?
	if _z_pos >= 0.0:
		_z_pos      = 0.0
		_z_velocity = 0.0
		_enter_state(State.IDLE)
		return

	if _consume_buffered("attack_light") and not _air_attack_used:
		_enter_state(State.ATTACK_AIR)
		return
	if _consume_buffered("dodge"):
		# Air dodge – short horizontal burst.
		_enter_state(State.DODGE)
		return

	move_and_slide()

# ── ATTACK_LIGHT ─────────────────────────────────────────────────────────────
func _state_attack_light(delta: float) -> void:
	velocity = _knockback * 0.3   # slight drift during attack
	_combo_timer -= delta

	# Animation-driven: assume each attack anim lasts ~0.35 s.
	var attack_duration := 0.35

	# Mid-swing hitbox activation (at ~40% of duration).
	if not _attack_hit and _state_timer >= attack_duration * 0.4:
		_activate_hitbox(12)

	# Buffer the next attack input during this swing.
	if _state_timer >= attack_duration:
		if _combo_timer <= 0.0:
			# Combo timed out.
			_combo_count = 0
			_enter_state(State.IDLE)
			return

		if _consume_buffered("attack_light"):
			_combo_count += 1
			if _combo_count >= MAX_COMBO_HITS:
				_combo_count = 0
				_enter_state(State.ATTACK_FINISHER)
			else:
				_combo_timer = COMBO_WINDOW
				_enter_state(State.ATTACK_LIGHT)
			return

		# No follow-up pressed yet – wait a short grace period.
		if _state_timer >= attack_duration + 0.15:
			_combo_count = 0
			_enter_state(State.IDLE)

	if _consume_buffered("jump"):
		_combo_count = 0
		_enter_state(State.JUMP)
		return
	if _consume_buffered("dodge"):
		_combo_count = 0
		_enter_state(State.DODGE)
		return

	move_and_slide()

# ── ATTACK_FINISHER ───────────────────────────────────────────────────────────
func _state_attack_finisher(delta: float) -> void:
	velocity = _knockback * 0.2
	var attack_duration := 0.55

	if not _attack_hit and _state_timer >= attack_duration * 0.35:
		_activate_hitbox(30)

	if _state_timer >= attack_duration:
		_combo_count = 0
		_enter_state(State.IDLE)
		return

	if _consume_buffered("jump"):
		_enter_state(State.JUMP)
		return

	move_and_slide()

# ── ATTACK_AIR ────────────────────────────────────────────────────────────────
func _state_attack_air(delta: float) -> void:
	# Continue the jump arc.
	_z_velocity += GRAVITY * delta
	_z_pos      += _z_velocity * delta

	velocity = _knockback * 0.5
	var attack_duration := 0.3

	if not _attack_hit and _state_timer >= attack_duration * 0.4:
		_activate_hitbox(18)

	if _z_pos >= 0.0:
		_z_pos      = 0.0
		_z_velocity = 0.0
		_enter_state(State.IDLE)
		return

	if _state_timer >= attack_duration:
		_enter_state(State.JUMP)
		return

	move_and_slide()

# ── DODGE ─────────────────────────────────────────────────────────────────────
func _state_dodge(delta: float) -> void:
	_dodge_timer -= delta

	# Ease out the dodge speed.
	var t       = clamp(_dodge_timer / DODGE_DURATION, 0.0, 1.0)
	var speed   = DODGE_SPEED * t
	velocity    = _dodge_dir * speed

	# Invincibility ends a bit before the roll does.
	if _is_invincible and _dodge_timer <= (DODGE_DURATION - DODGE_IFRAME_TIME):
		_is_invincible = false

	if _dodge_timer <= 0.0:
		_is_invincible = false
		_enter_state(State.IDLE)
		return

	move_and_slide()

# ── HURT ─────────────────────────────────────────────────────────────────────
func _state_hurt(delta: float) -> void:
	velocity = _knockback

	if _state_timer >= 0.4 and _knockback.length() < 5.0:
		if health <= 0:
			_enter_state(State.KNOCKED_DOWN)
		else:
			_enter_state(State.IDLE)
		return

	move_and_slide()

# ── KNOCKED_DOWN ──────────────────────────────────────────────────────────────
func _state_knocked_down(_delta: float) -> void:
	velocity = _knockback * 0.5

	if _state_timer >= 1.2:
		if health > 0:
			_enter_state(State.GET_UP)
		else:
			# Dead – emit signal and let the game handle it.
			died.emit()

	move_and_slide()

# ── GET_UP ────────────────────────────────────────────────────────────────────
func _state_get_up(_delta: float) -> void:
	velocity = Vector2.ZERO

	if _state_timer >= 0.6:
		_is_invincible = false
		_enter_state(State.IDLE)

	move_and_slide()

# ---------------------------------------------------------------------------
# Combat helpers
# ---------------------------------------------------------------------------

func _activate_hitbox(damage: int) -> void:
	_attack_hit    = true
	_hitstop_timer = HITSTOP_DURATION   # brief freeze on successful hit

	if hitbox:
		# You can set damage on the hitbox Area2D itself via metadata.
		hitbox.set_meta("damage", damage)
		# Enable for one physics frame.
		hitbox.monitoring = true
		await get_tree().physics_frame
		hitbox.monitoring = false

	# Emit so the game can react even without an Area2D.
	attack_landed.emit(damage, global_position)

# ---------------------------------------------------------------------------
# Receiving damage  (called externally or via hurtbox signal)
# ---------------------------------------------------------------------------

func take_damage(damage: int, knockback_vector: Vector2 = Vector2.ZERO) -> void:
	if _is_invincible:
		return

	health = max(0, health - damage)
	_knockback = knockback_vector
	health_changed.emit(health)

	_hitstop_timer = HITSTOP_DURATION

	if health <= 0:
		_enter_state(State.KNOCKED_DOWN)
	else:
		_enter_state(State.HURT)


func move_areas_on_jump(z_pos : float) -> void:
	$CollisionShape2D.position.y = z_pos
	hitbox.position.y = z_pos
	hurtbox.position.y = z_pos

# ---------------------------------------------------------------------------
# Hurtbox Area2D callback
# ---------------------------------------------------------------------------

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.has_meta("damage"):
		var dmg : int = area.get_meta("damage")
		var kb  : Vector2 = (global_position - area.global_position).normalized() * 200.0
		take_damage(dmg, kb)


func _on_hitbox_body_entered(body: Node2D) -> void:
	body.take_damage(hitbox.get_meta('damage', 1))
