extends Area2D

@export var next_scene: PackedScene

var _transitioning := false


func _on_body_entered(body: Node2D) -> void:
	if _transitioning or not body.is_in_group("player"):
		return
	_transitioning = true

	# Persist player health for the next scene.
	GameState.player_health = body.health

	# Reparent background music to the root so it survives the scene change.
	var music := get_tree().current_scene.find_child("BackgroundMusic", true, false)
	if music:
		music.reparent(get_tree().root)

	_fade_and_transition()


func _fade_and_transition() -> void:
	# Build a full-screen black overlay at root level so it persists through
	# the scene change (portal node itself will be freed with the old scene).
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	var rect := ColorRect.new()
	rect.color = Color(0.0, 0.0, 0.0, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(rect)
	get_tree().root.add_child(overlay)

	# Fade to black, then swap scene, then fade back in.
	var tw := overlay.create_tween()
	tw.tween_property(rect, "color:a", 1.0, 0.5)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_packed(next_scene)
		# Tween on the overlay itself so it survives the scene change.
		var tw2 := overlay.create_tween()
		tw2.tween_interval(0.1)   # brief pause while the new scene settles
		tw2.tween_property(rect, "color:a", 0.0, 0.5)
		tw2.tween_callback(func() -> void: overlay.queue_free())
	)
