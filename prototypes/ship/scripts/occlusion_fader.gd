class_name OcclusionFader
extends Node
## Fades walls and ceilings that block the camera's view of the target, and restores them after.
## The ceiling and camera-side wall of the target's own section always fade, wherever it stands.
## Occluder bodies sit on collision layer 2 and carry a "fade_mesh" meta pointing at their mesh.

const OCCLUDER_MASK := 2
const MAX_HITS_PER_RAY := 6
const RAY_LENGTH := 80.0

@export var camera: Camera3D
@export var target: Node3D
@export var ship: Ship
@export var faded_alpha := 0.15
@export var fade_speed := 8.0

## Meshes currently faded or fading back in.
var _tracked: Array[MeshInstance3D] = []


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	var occluders := find_occluders()
	for mesh in occluders:
		if mesh not in _tracked:
			_tracked.append(mesh)
	var weight := 1.0 - exp(-fade_speed * delta)
	for mesh in _tracked.duplicate():
		var material: StandardMaterial3D = mesh.material_override
		var goal := faded_alpha if mesh in occluders else 1.0
		var color := material.albedo_color
		color.a = lerpf(color.a, goal, weight)
		if goal == 1.0 and color.a > 0.99:
			color.a = 1.0
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			_tracked.erase(mesh)
		else:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color


## Points on the target's body (feet, middle, head, and either side) that the camera should see.
## They follow the target's "Pivot" child when it has one, so they stay on a body tipped horizontal.
func sight_points() -> Array[Vector3]:
	var body: Node3D = target.get_node_or_null("Pivot")
	var center := body.global_position if body != null else target.global_position + target.global_basis.y * 0.9
	var axis := (body if body != null else target).global_basis.y
	var right := camera.global_basis.x
	return [
		center - axis * 0.7,
		center,
		center + axis * 0.8,
		center + right * 0.4,
		center - right * 0.4,
	]


## Meshes of the target's room plus occluder panels between the camera and points on the target.
## The camera is orthographic, so sight lines run parallel to its view direction.
func find_occluders() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if camera == null or target == null:
		return found
	var forward := -camera.global_basis.z
	if ship != null:
		found.append_array(ship.room_fade_meshes(target.global_position, forward))
	var space := camera.get_world_3d().direct_space_state
	for point in sight_points():
		var exclude: Array[RID] = []
		for i in MAX_HITS_PER_RAY:
			var query := PhysicsRayQueryParameters3D.create(point - forward * RAY_LENGTH, point, OCCLUDER_MASK, exclude)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			exclude.append(hit.rid)
			var mesh: MeshInstance3D = hit.collider.get_meta("fade_mesh", null)
			if mesh != null and mesh not in found:
				found.append(mesh)
	return found
