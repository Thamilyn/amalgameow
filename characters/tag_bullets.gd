extends Area2D

@export var bullet_damage  := 25.0
@export var speed          := 500.0
@export var knockback_force := 200.0

## Set this before adding to the scene tree.
var direction := Vector2.RIGHT


func _ready() -> void:
	add_to_group("tag_bullet")


func _process(delta: float) -> void:
	position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(int(bullet_damage), direction * knockback_force)
	queue_free()


## Called by the player's hitbox to destroy the bullet on a successful punch.
func deflect() -> void:
	queue_free()


func _on_timer_timeout() -> void:
	queue_free()
