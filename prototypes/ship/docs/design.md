# Ship Ring Prototype — Design

## Intent

Prove two things: how it **feels to move** around a spinning-station ring, and whether
the **ship's size feels natural and good for gameplay**. Everything else is placeholder.

## Goals

- A capsule character walks (no jump, no sprint) anywhere on the inside of a 12-sided ring.
- The camera stays at a fixed isometric angle; the ship appears to rotate as the player moves,
  so the player always stays at the bottom of the screen.
- The player can walk all the way around the ring and back to the start.
- Walls and ceiling fade out only when they block the view of the player.
- A few crates give a sense of human scale.

## Non-goals

No jumping, readouts, scale bar, art, animation, audio, menus, or Coriolis/true spin physics.

## Decided by Matt

| Topic | Decision |
|---|---|
| Ship | Spinning station; walk on the inner hull; "down" is away from the hub |
| Ring | Dodecagon, 100 m diameter, each of the 12 sections a different color |
| Corridor | 10 m wide (along the spin axis), 5 m ceiling, walls and ceiling |
| Camera | Fixed isometric angle; the ship appears to rotate continuously with the player's position |
| Occlusion | Walls and ceiling become see-through only when they block the view of the player |
| Player | Capsule; WASD, ship-relative: W/S = around the ring, A/D = across its width |
| Tech | Godot 4, GDScript, in `prototypes/ship` |
| Scale cues | A few crates; no readout or scale bar |

## Approaches considered

- **A. Moving camera, static ship (chosen).** Ship collision never moves. The player uses
  radial gravity (`up_direction` points toward the hub). A camera rig on the spin axis rotates
  to match the player's angle, which looks identical to the ship rotating under a fixed camera.
  Physics stays stable, and seam-based rotation can be added later by changing only the rig.
- B. Actually rotate the ship: literal, but characters standing on moving colliders jitter and clip.
- C. Analytic movement without physics: smooth, but every crate and wall needs custom collision.

## Design

- **Geometry.** Spin axis = world X. The 100 m diameter is the floor's corner-to-corner size, so
  floor corners sit at radius 50 m, the floor's flat centers at 48.30 m (apothem), and each floor
  panel is 25.88 m long. The ceiling is 5 m inward (apothem 43.30 m). Walls are at x = ±5 m.
  Each section is built from code as convex slabs (floor, ceiling, two walls) with matching
  collision. Section *k* is centered at angle 30°·*k*, and section 0 is at the bottom.
- **Colors.** 12 evenly spaced hues. Floors use the full color; walls and ceiling use a muted tint
  of the same hue.
- **Gravity.** True spin gravity points radially outward, 9.8 m/s². Because the panels are flat,
  each panel's center is its "high" point and the seams are shallow valleys (up to a 15° slope).
  This matches the continuous camera: the floor under the player tilts by the same amount on screen.
  The player stays upright relative to the hub, doesn't slide when standing still, and walks at
  constant speed on the slopes.
- **Player.** CharacterBody3D capsule (0.4 m radius, 1.8 m tall) with a small "nose" to show facing.
  Walk speed is an exported variable (default 3 m/s, a brisk game walk; a real walk is ~1.4 m/s).
- **Camera rig.** A node on the spin axis, rotated about X so the player sits at the rig's local
  bottom. An orthographic Camera3D (isometric pitch −35.26°, yaw 45°) follows the player's local
  position. Orthographic size and distance are exported for tuning.
- **Occlusion fade.** Each frame, rays run parallel to the camera's view direction toward several
  points on the player and hit only wall and ceiling bodies (their own collision layer). Hit panels
  fade to low alpha, and everything else fades back to opaque.
- **Lighting.** One shadowed light near the ceiling of each section, plus dim ambient light. A single
  directional light would be blocked by the far side of the ring.
- **Crates.** About 2 per section, 1–1.5 m cubes, placed deterministically, static, and kept clear
  of the spawn point.

## Verification

Headless GDScript tests (no plugins): ring geometry values, the rig keeps the player at the local
bottom, the player stays grounded while walking a full lap, walls stop the player at the corridor
edges, and crates sit on the floor.

## Left to the builder

Scene layout, exact camera and fade tuning values, crate layout, and the hue palette.
