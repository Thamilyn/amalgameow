extends Panel


signal try_again


func _on_button_pressed() -> void:
	emit_signal("try_again")
