# Ship Ring Prototype

A capsule walks the inside of a spinning 12-sided ring (100 m across, 10 m wide, 5 m ceiling).
The camera holds a fixed isometric angle and the ship turns as you walk, so you always stay at
the bottom of the ring. Design: `docs/design.md`. Plan: `docs/plan.md`.

## Run

- Editor: `godot -e --path .` (from this folder), then press F5.
- Directly: `godot --path .`

## Controls

| Key | Action |
|---|---|
| Mouse | Face the cursor |
| W / S | Move forward / back along the facing |
| A / D | Strafe left / right |
| G | Toggle gravity: off, the capsule lies horizontal and floats mid-corridor. A W/A/S/D press then sets a drift that carries on after release, until it bumps into something or another key changes it |
| E | Grab a ladder at its doorway; let go at a landing. W/S climb. |
| Tab | Switch to the next ship (each remembers where you were) |
| Esc | Quit |

There are five ships: the ring, a three-room zero-g skiff (cockpit, cabin, hold), the Tug, two decks under thrust joined by a ladder pipe, the Freighter, four decks under thrust joined by one ladder pipe, and the Wheel, three rings side by side around a zero-g hub, joined by nine ladder spokes.

## Tuning knobs (Inspector, or the `@export` vars)

| Node | Property | Default | Effect |
|---|---|---|---|
| Player | `walk_speed` | 3.0 m/s | Walking pace (a real walk is about 1.4 m/s) |
| Player | `turn_speed` | 12 | How quickly the capsule turns to face the cursor |
| Player | `climb_speed` | 1.5 m/s | How fast W/S move along a ladder (a Wheel spoke is 38.6 m long) |
| CameraRig | `ortho_size` | 24 m | How much of the ship fits on screen |
| CameraRig | `follow_sharpness` | 10 | How tightly the camera tracks the player |
| OcclusionFader | `faded_alpha` | 0.15 | How see-through blocking walls and ceilings get |
| OcclusionFader | `fade_speed` | 8 | How fast panels fade out and back in |

Ring dimensions are constants in `scripts/ring_geometry.gd`.

## How it works

- The ship never moves. The player's "up" always points at the spin axis (world X), so
  gravity pulls outward like a real spinning station. Flat panels mean each panel's middle is
  slightly "uphill" of its seams (up to 15°).
- A `Ship` node answers which way is up, how far the camera rolls, which room meshes fade and
  where to spawn; `RingShip` is the ring and `SkiffShip` the skiff.
- `Fleet` holds the ships. Only the active one is shown, processed and collidable; Tab switches,
  boarding the player at the pose it last had there and pointing the camera rig and fader at the ship.
- A `DeckShip` stacks decks joined by a ladder pipe. Each pipe gets a `Ladder`; climbing places the
  player on the pipe's axis, and doorway blockers on the hatch layer keep walkers out of the shaft.
- Gravity applies where the ship has it and the player wants it: G sets what the player wants, and the ship answers per
  position. The Wheel's hub has none, so climbing a spoke into it leaves the player floating, and climbing out brings gravity back.
- A cutaway hides every deck above the player's; the ladder reveals each deck as you climb past its floor.
- `CameraRig` sits on the axis and rolls by the ship's camera roll at the player (the player's
  angle, for the ring); its isometric camera is a child, which makes the ship appear to turn
  under a fixed view.
- `OcclusionFader` always fades the ceiling and camera-side wall of the player's own section, and
  casts rays along the camera's view toward the player to fade any other wall or ceiling they hit.
- With gravity off, the player switches to Godot's floating motion mode, eases to `FLOAT_HEIGHT`
  above the floor, and its `Pivot` (the visible body, mirrored by the collision capsule) tips 90°
  so the head leads.

## Tests

```sh
godot --headless --path . --import   # once, or after adding a class_name script
godot --headless --path . -s res://tests/run_tests.gd            # all
godot --headless --path . -s res://tests/run_tests.gd -- player  # filter by file/test name
```

A test fails if it logs an engine or script error (a call on `null`, a type mismatch, `push_error`).
A test that deliberately triggers one declares it with `expect_error("part of the message")`, and
fails if that error never arrives.
Errors from work that outlives a test (a timer, a signal) are caught too: the runner keeps watching for a few
frames after the last test, and an error that lands in a later test names the earlier test it likely came from.

Screenshots of an automated walk (gravity turns off partway): `godot --path . -- --capture <dir>`.
