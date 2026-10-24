class_name StepDetector
extends RefCounted
## Counts steps from the up-and-down bob of the head.
##
## Every step lifts and drops your head once, so one bob cycle = one step.
## Pipeline: remove slow drift (leaning, slouching) -> smooth out tracking
## jitter -> find each peak using a threshold that adapts to how big your
## bob currently is, with hysteresis so one bob can't count twice.

## Drift remover time constant (s). Longer than a step, shorter than a lean.
var baseline_tau := 0.8
## Jitter smoother time constant (s).
var smooth_tau := 0.03
## Smallest bob that counts as a step (m). A walking bob is roughly 2-5 cm.
var min_threshold := 0.006
## Detection threshold as a fraction of your recent bob size.
var threshold_ratio := 0.35
## Fastest and slowest step timing accepted (s): about 270 and 40 steps/min.
var min_step_interval := 0.22
var max_step_interval := 1.5
## Cadence drops to zero after this long without a step (s).
var idle_timeout := 2.0
## How many recent steps the cadence is averaged over.
var cadence_window := 8

var step_count := 0
## Steps per minute (median of recent step intervals), 0 when idle.
var cadence_spm := 0.0
## Filtered bob in metres, for the waveform display.
var signal_value := 0.0
## Current detection threshold in metres.
var threshold := 0.0
## Recent bob height (peak above the middle) in metres.
var amplitude := 0.0

enum State { ARMED, RISING, FALLING }

var _state := State.ARMED
var _baseline := NAN
var _smoothed := 0.0
var _peak := 0.0
var _time := 0.0
var _last_step_time := -INF
var _intervals: Array[float] = []
## A lone bob after a pause is held back until a second one follows at a
## walking rhythm, so swaying or nodding while standing doesn't count.
var _pending_first := false


## Feed one head height sample (metres) and the time since the last one.
## Returns true when this sample completed a step.
func add_sample(head_height: float, dt: float) -> bool:
	if dt <= 0.0:
		return false
	_time += dt
	if is_nan(_baseline):
		_baseline = head_height
	_baseline += (head_height - _baseline) * (1.0 - exp(-dt / baseline_tau))
	_smoothed += ((head_height - _baseline) - _smoothed) * (1.0 - exp(-dt / smooth_tau))
	signal_value = _smoothed
	threshold = maxf(min_threshold, threshold_ratio * amplitude)

	var stepped := false
	match _state:
		State.ARMED:
			if signal_value > threshold:
				_state = State.RISING
				_peak = signal_value
		State.RISING:
			_peak = maxf(_peak, signal_value)
			if signal_value < 0.0:
				stepped = _register_step()
				_state = State.FALLING
		State.FALLING:
			# Must dip clearly below the middle before the next peak can count.
			if signal_value < -threshold * 0.5:
				_state = State.ARMED

	if _time - _last_step_time > idle_timeout:
		cadence_spm = 0.0
		_intervals.clear()
		amplitude *= exp(-dt / 2.0)  # slowly regain sensitivity while idle
	return stepped


## True once enough steady steps have been seen to trust the cadence.
func is_stable() -> bool:
	return cadence_spm > 0.0 and _intervals.size() >= 6


func reset() -> void:
	step_count = 0
	cadence_spm = 0.0
	amplitude = 0.0
	_intervals.clear()
	_last_step_time = -INF
	_pending_first = false
	_state = State.ARMED


func _register_step() -> bool:
	var interval := _time - _last_step_time
	if interval < min_step_interval:
		return false
	_last_step_time = _time
	if interval > max_step_interval:
		# First bob after a pause: wait for a partner before counting it.
		_pending_first = true
		return false
	amplitude = _peak if amplitude <= 0.0 else lerpf(amplitude, _peak, 0.3)
	step_count += 2 if _pending_first else 1
	_pending_first = false
	_intervals.append(interval)
	if _intervals.size() > cadence_window:
		_intervals.pop_front()
	var sorted: Array[float] = _intervals.duplicate()
	sorted.sort()
	cadence_spm = 60.0 / sorted[int(sorted.size() / 2.0)]
	return true
