```

Here's a breakdown of everything implemented:

---

## Architecture

### State Machine
The player has 11 explicit states managed by `_enter_state()`:

| State | Description |
|---|---|
| `IDLE` | Standing still, polls all input |
| `WALK` | 8-directional movement at walk speed |
| `RUN` | Double-tap a direction to trigger run |
| `JUMP` | Real physics Z-arc for a jump |
| `ATTACK_LIGHT` | Up to 3 chained light attacks |
| `ATTACK_FINISHER` | Auto-triggered after 3 hits, more damage |
| `ATTACK_AIR` | Jump attack mid-air |
| `DODGE` | Roll with i-frames + ease-out speed |
| `HURT` | Launched by knockback |
| `KNOCKED_DOWN` | Full knockdown at 0 HP |
| `GET_UP` | Invincible rising animation |

---

## Key Systems

- **Pseudo-3D**: `_z_pos` and `_z_velocity` drive a real parabolic jump arc; `sprite.position.y` is offset by it so the character lifts off visually while the collision stays on the ground.
- **Double-tap to run**: Detects two taps in the same direction within `RUN_THRESHOLD` seconds.
- **Combo string**: `_combo_count` tracks hits; reaching `MAX_COMBO_HITS` (3) auto-transitions into the heavier finisher.
- **Input buffer**: Inputs are stored for `0.16s`, so tapping attack slightly early during an animation is still respected.
- **Hitstop**: A `_hitstop_timer` freezes both `_process` and `_physics_process` for `0.07s` on hit, giving that satisfying SOR4 impact feel.
- **I-frames**: The dodge roll sets `_is_invincible = true`; `take_damage()` exits early if that flag is set.

---

## What to Wire Up in the Scene

To complete the setup, add these child nodes to `player.tscn`:
1. **`AnimationPlayer`** — add animations named `idle`, `walk`, `run`, `jump`, `attack_light_1/2/3`, `attack_finisher`, `attack_air`, `dodge`, `hurt`, `knocked_down`, `get_up`.
2. **`Hitbox`** (`Area2D`) — positioned in front of the character for melee range.
3. **`Hurtbox`** (`Area2D`) — covering the character's body to receive incoming hits.

And add these **Input Map** actions in Project Settings:
- `attack_light`, `attack_special`, `jump`, `dodge`
