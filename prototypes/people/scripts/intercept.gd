class_name Intercept
extends RefCounted
## Constant-speed intercept of a target whose path is known in advance.

const DEFAULT_HORIZON_DAYS := 730.0
const _BISECTION_STEPS := 60


## Trip duration in days from `from` at day `t0`, or -1.0 if the target can't be
## reached within `horizon_days`. `target_at` is `func(day: float) -> Vector2`.
static func solve(from: Vector2, t0: float, speed_km_per_day: float, target_at: Callable,
		horizon_days: float = DEFAULT_HORIZON_DAYS) -> float:
	# Every target is slower than the transport, so this reach margin only
	# grows with time and crosses zero once.
	var reach_margin := func(duration: float) -> float:
		return speed_km_per_day * duration - from.distance_to(target_at.call(t0 + duration))
	if reach_margin.call(horizon_days) < 0.0:
		return -1.0
	var too_early := 0.0
	var late_enough := horizon_days
	for step in _BISECTION_STEPS:
		var middle := (too_early + late_enough) / 2.0
		if reach_margin.call(middle) < 0.0:
			too_early = middle
		else:
			late_enough = middle
	return late_enough
