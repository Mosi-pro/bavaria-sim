extends RefCounted
## Selbst erzeugte Raumgeräusche der begehbaren Leitstelle (keine Fremdaufnahmen):
## Gesprächsgemurmel, Kaffeemaschine, Mikrowelle, Wasser, Serverlüfter, Kühlschrank, Türen.

const RATE := 16000
static var _cache := {}

static func get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var data: PackedFloat32Array
	var loop := false
	match name:
		"murmur":
			data = _murmur(rng, 6.0, 3)
			loop = true
		"murmur_soft":
			data = _murmur(rng, 5.0, 2)
			loop = true
		"coffee":
			data = _coffee(rng)
		"microwave":
			data = _hum(rng, 6.0, 100.0, 0.18, 0.06)
			_append_ding(data)
		"water":
			data = _water(rng, 2.2)
		"server":
			data = _hum(rng, 4.0, 120.0, 0.05, 0.22)
			loop = true
		"fridge":
			data = _hum(rng, 3.0, 50.0, 0.12, 0.02)
			loop = true
		"door":
			data = _door(rng)
		"cabinet":
			data = _door(rng, 0.5)
		"ding":
			data = PackedFloat32Array()
			data.resize(int(RATE * 0.1))
			_append_ding(data)
		"step":
			data = _step(rng)
		_:
			data = PackedFloat32Array([0.0])
	var s := _to_wav(data, loop)
	_cache[name] = s
	return s

static func _to_wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w

## Zweipol-Bandpass (Resonanzfilter) über ein Signal.
static func _bandpass(x: PackedFloat32Array, f: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * f / RATE
	var alpha := sin(w0) / (2.0 * q)
	var b0 := alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha
	var out := PackedFloat32Array()
	out.resize(x.size())
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	for i in x.size():
		var y := (b0 * x[i] - b0 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1; x1 = x[i]; y2 = y1; y1 = y
		out[i] = y
	return out

static func _noise(rng: RandomNumberGenerator, n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		a[i] = rng.randf_range(-1.0, 1.0)
	return a

## Leises Stimmengewirr: gefiltertes Rauschen mit Silbenhüllkurve und Sprechpausen.
static func _murmur(rng: RandomNumberGenerator, sec: float, voices: int) -> PackedFloat32Array:
	var n := int(sec * RATE)
	var mix := PackedFloat32Array()
	mix.resize(n)
	for v in voices:
		var src := _noise(rng, n)
		var f1 := rng.randf_range(420.0, 650.0)
		var f2 := rng.randf_range(1100.0, 1700.0)
		var a := _bandpass(src, f1, 4.0)
		var b := _bandpass(src, f2, 5.0)
		var syl := rng.randf_range(3.5, 5.5)
		var talk := rng.randf() < 0.5
		var seg := 0.0
		for i in n:
			var t := float(i) / RATE
			seg -= 1.0 / RATE
			if seg <= 0.0:
				talk = not talk if rng.randf() < 0.6 else talk
				seg = rng.randf_range(0.6, 1.8)
			var env := maxf(0.0, sin(t * TAU * syl + sin(t * 2.1 + v) * 2.0)) * (1.0 if talk else 0.0)
			mix[i] += (a[i] * 0.7 + b[i] * 0.4) * env * 0.5
	# weicher Übergang am Schleifenende
	var fade := int(0.25 * RATE)
	for i in fade:
		var k := float(i) / fade
		mix[i] *= k
		mix[n - 1 - i] *= k
	return mix

static func _hum(rng: RandomNumberGenerator, sec: float, f: float, tone: float, noise: float) -> PackedFloat32Array:
	var n := int(sec * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var src := _bandpass(_noise(rng, n), 700.0, 0.6)
	# ganzzahlige Periodenzahl für nahtlose Schleifen
	var fr := roundf(f * sec) / sec
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * fr * t) * 0.6 + sin(TAU * fr * 2.0 * t) * 0.3 + sin(TAU * fr * 3.0 * t) * 0.1) * tone + src[i] * noise
	return out

static func _append_ding(data: PackedFloat32Array) -> void:
	var start := maxi(0, data.size() - int(0.9 * RATE))
	for i in range(start, data.size()):
		var t := float(i - start) / RATE
		data[i] = data[i] * 0.3 + sin(TAU * 1760.0 * t) * exp(-t * 4.0) * 0.35 + sin(TAU * 2640.0 * t) * exp(-t * 6.0) * 0.12

static func _coffee(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(4.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var src := _noise(rng, n)
	var grind := _bandpass(src, 900.0, 1.2)
	var hiss := _bandpass(src, 3500.0, 0.8)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		if t < 1.6:
			v += grind[i] * (0.6 + 0.4 * sin(TAU * 38.0 * t)) * 0.7 + sin(TAU * 140.0 * t) * 0.12
		elif t < 4.2:
			v += sin(TAU * 60.0 * t) * 0.18 * (1.0 + 0.3 * sin(TAU * 7.0 * t)) + hiss[i] * 0.25
		v *= minf(1.0, t * 20.0) * minf(1.0, (4.5 - t) * 6.0)
		out[i] = v
	return out

static func _water(rng: RandomNumberGenerator, sec: float) -> PackedFloat32Array:
	var n := int(sec * RATE)
	var a := _bandpass(_noise(rng, n), 2200.0, 1.0)
	var b := _bandpass(_noise(rng, n), 600.0, 2.0)
	for i in n:
		var t := float(i) / RATE
		a[i] = (a[i] * 0.5 + b[i] * 0.3 * (0.5 + 0.5 * sin(TAU * 9.0 * t + sin(t * 31.0)))) * minf(1.0, t * 8.0) * minf(1.0, (sec - t) * 4.0)
	return a

static func _door(rng: RandomNumberGenerator, vol := 1.0) -> PackedFloat32Array:
	var n := int(0.45 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var src := _bandpass(_noise(rng, n), 300.0, 1.5)
	for i in n:
		var t := float(i) / RATE
		var click := sin(TAU * 1800.0 * t) * exp(-t * 90.0) * 0.4
		var thump := (sin(TAU * 85.0 * t) * 0.6 + src[i] * 0.5) * exp(-maxf(0.0, t - 0.03) * 22.0) * (1.0 if t > 0.03 else 0.0)
		out[i] = (click + thump) * vol
	return out

static func _step(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.12 * RATE)
	var out := _bandpass(_noise(rng, n), 180.0, 1.0)
	for i in n:
		var t := float(i) / RATE
		out[i] *= exp(-t * 40.0) * 0.9
	return out
