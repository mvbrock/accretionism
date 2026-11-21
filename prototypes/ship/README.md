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
| W / S | Walk around the ring |
| A / D | Walk across the ring |
| Esc | Quit |

## Tuning knobs (Inspector, or the `@export` vars)

| Node | Property | Default | Effect |
|---|---|---|---|
| Player | `walk_speed` | 3.0 m/s | Walking pace (a real walk is about 1.4 m/s) |
| Player | `turn_speed` | 12 | How quickly the capsule turns to face its movement |
| CameraRig | `ortho_size` | 24 m | How much of the ship fits on screen |
| CameraRig | `follow_sharpness` | 10 | How tightly the camera tracks the player |
| OcclusionFader | `faded_alpha` | 0.15 | How see-through blocking walls and ceilings get |
| OcclusionFader | `fade_speed` | 8 | How fast panels fade out and back in |

Ring dimensions are constants in `scripts/ring_geometry.gd`.

## How it works

- The ship never moves. The player's "up" always points at the spin axis (world X), so
  gravity pulls outward like a real spinning station. Flat panels mean each panel's middle is
  slightly "uphill" of its seams (up to 15°).
- `CameraRig` sits on the axis and rotates to the player's angle; its isometric camera is a
  child, which makes the ship appear to turn under a fixed view.
- `OcclusionFader` casts rays along the camera's view toward the player and fades any wall or
  ceiling they hit.

## Tests

```sh
godot --headless --path . --import   # once, or after adding a class_name script
godot --headless --path . -s res://tests/run_tests.gd            # all
godot --headless --path . -s res://tests/run_tests.gd -- player  # filter by file/test name
```

A test fails if it logs an engine or script error (a call on `null`, a type mismatch, `push_error`).
A test that deliberately triggers one declares it with `expect_error("part of the message")`, and
fails if that error never arrives.

Screenshots of an automated walk: `godot --path . -- --capture <dir>`.
