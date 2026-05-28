extends Control


@onready var hp_bar = $HPTextureBar
@onready var danger_texture = preload("res://assets/UI/ui_HP_RISK.png")
@onready var normal_texture = preload("res://assets/UI/UI_HP_normal.png")

@export var player : CharacterBody2D
@export var danger_hp := 30.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if player:
		hp_bar.value = player.health
		player.connect("health_changed", on_health_changed)

func on_health_changed(amount: int) -> void:
	print('new hp: ', amount)
	
	hp_bar.value = amount
	if (hp_bar.value <= danger_hp):
		hp_bar.texture_over = danger_texture
	else:
		hp_bar.texture_over = normal_texture
