class_name Sounds
## Small sounds made in code, so the project needs no audio files yet.


## A soft gravel crunch for each step.
static func footstep() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.11)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var low := 0.0
	for i in n:
		var t := float(i) / n
		var envelope := pow(1.0 - t, 2.5) * minf(t * 40.0, 1.0)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.3)
		var grit := rng.randf_range(-1.0, 1.0) * 0.25 if rng.randf() < 0.3 else 0.0
		data.encode_s16(i * 2, int(clampf((low + grit) * envelope * 0.9, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)


## A gentle two-note chime for noticing something.
static func chime() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.6)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var a := sin(TAU * 880.0 * t) * exp(-t * 6.0)
		var b := sin(TAU * 1318.5 * t) * exp(-maxf(t - 0.09, 0.0) * 5.0) * (1.0 if t > 0.09 else 0.0)
		data.encode_s16(i * 2, int(clampf((a + b) * 0.28, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
