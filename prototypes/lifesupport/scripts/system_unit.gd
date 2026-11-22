class_name SystemUnit
extends RefCounted
## The state every powered system shares: running, booting after power or a
## restart, faulted until restarted, or without power.

enum State { RUNNING, BOOTING, FAULT, NO_POWER }
enum RestartResult { REBOOTING, NO_POWER }

## Absorbs float residue from summing 0.1 s steps.
const BOOT_EPSILON_S := 1e-9

var id: String
var boot_s: float
var boot_left_s := 0.0
var state := State.RUNNING


func _init(unit_id: String, boot_time_s: float) -> void:
	id = unit_id
	boot_s = boot_time_s


## Advances `dt` seconds. True when the state changed.
func step(dt: float, powered: bool) -> bool:
	var before := state
	if not powered:
		state = State.NO_POWER
	elif state == State.NO_POWER:
		_start_boot()
	elif state == State.BOOTING:
		boot_left_s -= dt
		if boot_left_s <= BOOT_EPSILON_S:
			boot_left_s = 0.0
			state = State.RUNNING
	return state != before


## Starts a boot from any powered state, a fault included.
func restart(powered: bool) -> RestartResult:
	if not powered:
		return RestartResult.NO_POWER
	_start_boot()
	return RestartResult.REBOOTING


## Puts the system in FAULT. False when it has no power or is already faulted.
func fault() -> bool:
	if state == State.NO_POWER or state == State.FAULT:
		return false
	state = State.FAULT
	return true


func is_running() -> bool:
	return state == State.RUNNING


func _start_boot() -> void:
	state = State.BOOTING
	boot_left_s = boot_s
