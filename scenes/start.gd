extends Node

@onready var think_video = preload("res://scenes/think_video.tscn")
@onready var intro_scene = $IntroScene
@onready var menu = $Menu

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	menu.hide()
	intro_scene.get_node("AnimationPlayer").connect("animation_finished", on_anim_finished)

func on_anim_finished(anim_name):
	if anim_name == "intro":
		show_menu()

func show_menu():
	intro_scene.hide()
	$Menu.show()

func go_to_main():
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_button_pressed() -> void:
	var video = think_video.instantiate()
	add_child(video)
	video.get_node("VideoStreamPlayer").connect("finished", go_to_main)
	
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		show_menu()
