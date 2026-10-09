class_name SimClock
extends Node

signal tick_advanced

const TICK_SECONDS: float = 1.0

var simulation: Simulation
var _accumulator: float = 0.0

@export_enum("Paused:0", "1x:1", "2x:2", "3x:3") var speed: int = 1:
	set(value):
		if value not in [0, 1, 2, 3]:
			push_error("SimClock: speed must be 0, 1, 2 or 3")
			return
		speed = value

# This is a scheduling limit, not an economic balance parameter.
@export var max_ticks_per_frame: int = 8:
	set(value):
		if value <= 0:
			push_error("SimClock: max_ticks_per_frame must be positive")
			return
		max_ticks_per_frame = value


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		push_error("SimClock: delta must be finite and nonnegative")
		return
	if simulation == null or speed == 0:
		return
	_accumulator += delta * speed
	var ticks: int = 0
	while _accumulator >= TICK_SECONDS and ticks < max_ticks_per_frame:
		simulation.tick()
		tick_advanced.emit()
		_accumulator -= TICK_SECONDS
		ticks += 1
