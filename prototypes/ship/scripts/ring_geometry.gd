class_name RingGeometry
extends RefCounted
## Pure math for the 12-sided ring. The spin axis is world X.
## Section k's floor panel is centered at angle 30°·k; section 0 is straight down (−Y).

const SECTIONS := 12
## Distance from the axis to the floor's corners (the 100 m diameter).
const FLOOR_CORNER_RADIUS := 50.0
## Corridor runs from x = −HALF_WIDTH to +HALF_WIDTH.
const HALF_WIDTH := 5.0
const CEILING_HEIGHT := 5.0
const SLAB_THICKNESS := 0.4
const HALF_ANGLE := PI / SECTIONS


## Distance from the axis to the middle of a floor panel.
static func floor_apothem() -> float:
	return FLOOR_CORNER_RADIUS * cos(HALF_ANGLE)


static func ceiling_apothem() -> float:
	return floor_apothem() - CEILING_HEIGHT


static func floor_side_length() -> float:
	return 2.0 * FLOOR_CORNER_RADIUS * sin(HALF_ANGLE)


static func ceiling_side_length() -> float:
	return 2.0 * half_length_at(ceiling_apothem())


## Half the length of a panel at distance `radius` from the axis, so neighboring panels meet at the seams.
static func half_length_at(radius: float) -> float:
	return radius * tan(HALF_ANGLE)


static func section_angle(k: int) -> float:
	return k * TAU / SECTIONS


## Outward unit normal of section k's floor (the direction of "down" at its center).
static func section_down(k: int) -> Vector3:
	var theta := section_angle(k)
	return Vector3(0, -cos(theta), -sin(theta))


## Unit direction along section k's panel, toward increasing angle (the way W walks).
static func section_tangent(k: int) -> Vector3:
	var theta := section_angle(k)
	return Vector3(0, sin(theta), -cos(theta))


## Angle of a point around the axis, in (−π, π]; 0 is straight down.
static func angle_of(p: Vector3) -> float:
	return atan2(-p.z, -p.y)


## Unit vector from p toward the axis (the player's "up").
static func up_at(p: Vector3) -> Vector3:
	return Vector3(0, -p.y, -p.z).normalized()


static func section_of(p: Vector3) -> int:
	return posmod(roundi(angle_of(p) / (TAU / SECTIONS)), SECTIONS)
