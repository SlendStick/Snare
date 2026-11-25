# Snare

A first-person 3D horror game built from scratch in **Godot 4.3+ (GDScript)**.

You wake up in a dark, claustrophobic maze that is **procedurally generated at runtime** as you move. Your only tool is an unreliable flashlight. A huge, wheezing monster stalks the corridors. Hide in lockers, control your breathing, and survive.

## Features

- **Runtime procedural maze generation**: random seed each run, chunks generated around the player on-the-fly using chunked Recursive Backtracker with guaranteed inter-chunk connectivity.
- **Dynamic navigation**: AStar2D pathfinding grid updated as new chunks are generated.
- **First-person controller**: WASD movement, Shift sprint (stamina + noise), Ctrl crouch (quiet), mouse look, head bob, hand sway.
- **Flashlight mechanics**:
  - Battery drains over time; below 20% it dims and flickers.
  - Random contact failures can turn it off even with charge.
  - **Shake-to-fix**: when it dies from bad contact, shake the mouse to restore it.
  - **Manual battery replacement (R)**: unscrew cap (mouse wheel/circular motion), swap battery (LMB/E), screw cap back. Esc cancels but leaves it disassembled.
  - Batteries spawn with random charge (15%–100%).
- **Lockers & breathing minigame**: hide in lockers; if the monster gets close, a panic breathing rhythm minigame starts (alternate Q/E in tempo). Fail too many times and the monster rips the door open.
- **Monster AI (FSM)**: PATROL, INVESTIGATE, CHASE, SEARCH, CHECK_LOCKER/KILL with 3D spatial audio (wheezing, heavy steps, roar), sight/hearing, and director bias toward player.
- **Atmosphere**: dark environment, fog, film grain + vignette + chromatic aberration postprocess, procedural SFX (no external assets required).

## Controls

| Key | Action |
|---|---|
| WASD | Move |
| Mouse | Look |
| Shift | Run (drains stamina, makes noise) |
| Ctrl | Crouch (quieter) |
| E | Interact (pickup / hide / exit locker) |
| F | Toggle flashlight |
| R | Flashlight service mode (battery replacement) |
| Mouse wheel / mouse motion | Unscrew/screw cap in service mode; shake to fix contact failure |
| LMB / E | Remove/insert battery during service mode |
| Q / E | Breathing rhythm minigame while hiding |
| Esc | Pause / cancel service mode |

## Run

1. Open the project folder in **Godot 4.3+**.
2. Run the main scene (`F5`). The main scene is `res://scenes/main.tscn`.

No external assets, addons, or imports are required — geometry, materials, textures, and sounds are generated procedurally at runtime.

## Project structure

```text
res://
├── scenes/
│   ├── main.tscn
│   ├── player/ (player.tscn, flashlight.tscn)
│   ├── world/ (maze_generator.tscn, maze_chunk.tscn, locker.tscn, battery_pickup.tscn)
│   ├── enemy/ (monster.tscn)
│   └── ui/ (hud.tscn, breathing_minigame.tscn, game_over.tscn)
├── scripts/
│   ├── core/ (game_manager.gd, audio_synthesizer.gd, main.gd)
│   ├── maze/ (runtime_maze_generator.gd, maze_grid_astar.gd)
│   ├── player/ (player_controller.gd, flashlight_controller.gd, battery_item.gd)
│   ├── interactables/ (locker.gd, battery_pickup.gd)
│   ├── enemy/ (monster_ai.gd)
│   └── ui/ (hud.gd, breathing_minigame.gd, game_over.gd)
└── shaders/ (horror_postprocess.gdshader)
```

## Notes

- Rendering is set to **GL Compatibility** for broad portability.
- Generated chunks are kept loaded to preserve floor collision and navigation consistency.
- Audio is synthesized at runtime via `AudioStreamWAV` (procedural noise/tones/envelopes).
