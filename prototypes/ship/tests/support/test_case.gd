class_name TestCase
extends RefCounted
## Base class for headless tests. The runner sets `tree` before each test method.

var tree: SceneTree
var failures: Array[String] = []
var _owned: Array[Node] = []
var _expected_errors: Array[String] = []


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (got %.4f, expected %.4f ± %.4f)" % [message, actual, expected, tolerance])


## Declares that this test deliberately logs an error containing `substring`
## (for example through push_error). The test fails if none arrives.
func expect_error(substring: String) -> void:
	_expected_errors.append(substring)


## Fails the test for every logged error nobody expected, and for every
## expected error that never arrived. The runner calls this after the test.
func check_logged_errors(logged_messages: Array[String]) -> void:
	var still_expected := _expected_errors.duplicate()
	for message in logged_messages:
		var expected_index := still_expected.find_custom(func(substring: String) -> bool: return message.contains(substring))
		if expected_index == -1:
			failures.append("unexpected error logged: %s" % message)
		else:
			still_expected.remove_at(expected_index)
	for substring in still_expected:
		failures.append("expected an error containing '%s', but none was logged" % substring)


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
