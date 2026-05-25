extends Node2D


@export var player : CharacterBody2D

@onready var game_over_scene := preload("res://scenes/game_over_ui.tscn")
@onready var ui_layer = $UILayer

var player_start_position := Vector2.ZERO
var game_over_instance = null


func _ready() -> void:
	if player != null:
		player.connect("died", _on_player_death)
		player_start_position = player.position
	

func _on_player_death() -> void:
	if game_over_instance == null:
		game_over_instance = game_over_scene.instantiate()
		ui_layer.add_child(game_over_instance)
		game_over_instance.connect("try_again", _on_try_again)
	

func _on_try_again() -> void:
	player.position = player_start_position
	player.reset_state()
	game_over_instance.disconnect("try_again", _on_try_again)
	game_over_instance.queue_free()
