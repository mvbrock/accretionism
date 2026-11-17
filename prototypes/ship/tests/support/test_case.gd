class_name TestCase
extends RefCounted
## Base class for headless tests. The runner sets `tree` before each test method.

var tree: SceneTree
var failures: Array[String] = []
var _owned: Array[Node] = []


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (got %.4f, expected %.4f ± %.4f)" % [message, actual, expected, tolerance])


## Adds a node to the scene root and frees it after the test.
func own(node: Node) -> Node:
	tree.root.add_child(node)
	_owned.append(node)
	return node


func physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func teardown() -> void:
	for node in _owned:
		if is_instance_valid(node):
			node.free()
	_owned.clear()
