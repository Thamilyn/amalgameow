extends Node2D


@export var player : CharacterBody2D
@export var boss : CharacterBody2D

@onready var game_over_scene := preload("res://scenes/game_over_ui.tscn")
@onready var end_scene := preload("res://scenes/end_scene.tscn")
@onready var ui_layer = $UILayer
#@onready var background_music: AudioStreamPlayer = $BackgroundMusic

var player_start_position := Vector2.ZERO
var game_over_instance = null

## Stores data for every enemy present at scene load so they can be respawned.
## Each entry is a Dictionary:
##   "packed_scene" : PackedScene  – the scene to instantiate
##   "position"     : Vector2      – original world position
##   "node"         : Node         – current live instance (may become invalid)
##   "overrides"    : Dictionary   – exported properties that differ from defaults
var _enemy_records: Array = []

signal stage_restarted

func _ready() -> void:
	if player != null:
		player.connect("died", _on_player_death)
		player_start_position = player.position

	if boss != null:
		boss.connect("boss_died", on_boss_death)
	if has_node("BackgroundMusic"):
		GameState.background_music = get_node("BackgroundMusic")
		GameState.background_music.reparent.call_deferred(get_tree().root)
	_collect_enemies()


# ---------------------------------------------------------------------------
# Enemy catalogue
# ---------------------------------------------------------------------------

func _collect_enemies() -> void:
	for child in get_children():
		# Only CharacterBody2D instances that are not the player
		if not child is CharacterBody2D or child == player:
			continue
		# Must be a proper scene instance (has a source file)
		if child.scene_file_path.is_empty():
			continue
		_enemy_records.append({
			"packed_scene": load(child.scene_file_path),
			"position":     child.position,
			"node":         child,
			"overrides":    _capture_overrides(child),
		})


## Compares each script-defined exported property of *node* against the
## scene defaults and returns only the ones that were overridden in the editor.
func _capture_overrides(node: Node) -> Dictionary:
	var overrides := {}
	var script: Script = node.get_script()
	if script == null:
		return overrides
	var fresh: Node = load(node.scene_file_path).instantiate()
	for prop in script.get_script_property_list():
		var pname: String = prop["name"]
		var cur = node.get(pname)
		var def = fresh.get(pname)
		if cur != def:
			overrides[pname] = cur
	fresh.free()
	return overrides


# ---------------------------------------------------------------------------
# Player death / retry flow
# ---------------------------------------------------------------------------

func _on_player_death() -> void:
	if game_over_instance == null:
		game_over_instance = game_over_scene.instantiate()
		ui_layer.add_child(game_over_instance)
		game_over_instance.connect("try_again", _on_try_again)


func _on_try_again() -> void:
	player.position = player_start_position
	player.reset_state()
	_respawn_enemies()
	emit_signal("stage_restarted")
	game_over_instance.disconnect("try_again", _on_try_again)
	game_over_instance.queue_free()
	game_over_instance = null


func on_boss_death():
	if GameState.background_music:
		GameState.background_music.stop()
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 2.0
	timer.connect("timeout", go_to_endscene)
	add_child(timer)
	timer.start()

func go_to_endscene():
	get_tree().change_scene_to_packed(end_scene)
# ---------------------------------------------------------------------------
# Enemy respawn
# ---------------------------------------------------------------------------

func _respawn_enemies() -> void:
	for record in _enemy_records:
		if is_instance_valid(record["node"]):
			continue  # enemy is still alive – leave it alone
		var instance: Node = record["packed_scene"].instantiate()
		instance.position = record["position"]
		for pname in record["overrides"]:
			instance.set(pname, record["overrides"][pname])
		add_child(instance)
		record["node"] = instance
