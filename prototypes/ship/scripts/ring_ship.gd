class_name RingShip
extends Ship
## The 12-section ring: floor, ceiling and walls per section, with lights and crates, built from code.

const CRATES_PER_SECTION := 2

var _hull := RingHull.new()


func _ready() -> void:
	_hull.crates_per_section = CRATES_PER_SECTION
	_hull.build(self, self)


func up_at(p: Vector3) -> Vector3:
	return RingGeometry.up_at(p)


func camera_roll_at(p: Vector3) -> float:
	return RingGeometry.angle_of(p)


func room_at(p: Vector3) -> String:
	return _hull.room_at(p)


func spawn_point() -> Vector3:
	return RingGeometry.section_down(0) * (RingGeometry.floor_apothem() - 0.05)
