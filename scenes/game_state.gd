extends Node

## Persists player data across scene transitions.
var player_health: int = -1  # -1 = not yet set; player keeps its default

## Reference to the active BackgroundMusic node.
## Scenes that own a music node should assign it here in _ready().
var background_music: AudioStreamPlayer = null
