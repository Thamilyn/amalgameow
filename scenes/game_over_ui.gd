extends Panel


signal try_again


func _on_button_pressed() -> void:
	emit_signal("try_again")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
