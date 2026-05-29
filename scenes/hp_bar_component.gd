extends Control


@onready var hp_bar = $HPTextureBar
@onready var danger_texture = preload("res://assets/UI/ui_HP_RISK.png")
@onready var normal_texture = preload("res://assets/UI/UI_HP_normal.png")

@export var player: CharacterBody2D
@export var danger_hp := 30.0


func _ready() -> void:
	# Defer setup so all sibling nodes (including Player) are in the tree.
	call_deferred("_setup")


func _setup() -> void:
	# If no player was explicitly assigned (e.g. alley.tscn), find one by group.
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if player:
		hp_bar.value = player.health
		if not player.health_changed.is_connected(on_health_changed):
			player.health_changed.connect(on_health_changed)


func on_health_changed(amount: int) -> void:
	hp_bar.value = amount
	if hp_bar.value <= danger_hp:
		hp_bar.texture_over = danger_texture
	else:
		hp_bar.texture_over = normal_texture
