extends Node

@onready var intro_scene = $IntroScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	intro_scene.get_node("AnimationPlayer").connect("animation_finished", on_anim_finished)
	pass # Replace with function body.

func on_anim_finished(anim_name):
	print(anim_name)
	if anim_name == "intro":
		intro_scene.hide()
		$Menu.show()
	pass


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
