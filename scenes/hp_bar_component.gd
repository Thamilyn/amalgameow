extends Control


@onready var hp_bar = $HPBar
@export var player : CharacterBody2D



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if player:
		hp_bar.value = player.health
		player.connect("health_changed", on_health_changed)

func on_health_changed(amount: int) -> void:
	print('new hp: ', amount)
	hp_bar.value = amount
