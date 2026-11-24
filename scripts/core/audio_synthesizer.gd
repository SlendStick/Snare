extends Node
## Синтезатор звуков: все эффекты генерируются в WAV на лету, без внешних файлов.
## Autoload: AudioSynth

const RATE: int = 22050
var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 90210


func get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name] as AudioStreamWAV
	var samples := _generate(name)
	var looped: bool = name == "growl_loop" or name == "ambient" or name == "drone"
	var stream := _to_wav(samples, looped)
	_cache[name] = stream
	return stream


func play_2d(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	get_tree().root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


func play_3d(
	name: String,
	position: Vector3,
	volume_db: float = 0.0,
	pitch: float = 1.0,
	max_distance: float = 28.0
) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(name)
	p.position = position
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_distance
	get_tree().root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


func make_loop_player(name: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(name)
	p.volume_db = volume_db
	return p


func make_loop_player_3d(
	name: String, volume_db: float = 0.0, max_distance: float = 30.0
) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(name)
	p.volume_db = volume_db
	p.max_distance = max_distance
	return p


func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: float = clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _fract(x: float) -> float:
	return x - floor(x)


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _tone(t: float, freq: float) -> float:
	return sin(TAU * freq * t)


func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return exp(-maxf(t - attack, 0.0) / maxf(decay, 0.0001))


func _generate(name: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(RATE * 0.2)
	var lp: float = 0.0
	var lp2: float = 0.0

	match name:
		"step", "step_sprint":
			var strong: bool = name == "step_sprint"
			count = int(RATE * (0.20 if strong else 0.16))
			for i in range(count):
				var t: float = float(i) / RATE
				var thump: float = sin(TAU * (74.0 - 40.0 * t) * t) * exp(-t * 30.0)
				lp = lerpf(lp, _noise(), 0.24)
				var grit: float = lp * exp(-t * 22.0) * 0.75
				var click: float = 0.0
				if i < int(RATE * 0.012):
					click = _noise() * exp(-float(i) / (RATE * 0.0035)) * 0.4
				out.append((thump * 0.8 + grit * 0.4 + click) * (0.85 if strong else 0.55))

		"monster_step":
			count = int(RATE * 0.42)
			for i in range(count):
				var t: float = float(i) / RATE
				var boom: float = sin(TAU * (46.0 - 18.0 * t) * t) * exp(-t * 11.0)
				var second: float = 0.0
				if t > 0.13:
					second = sin(TAU * 58.0 * (t - 0.13)) * exp(-(t - 0.13) * 26.0) * 0.4
				lp = lerpf(lp, _noise(), 0.08)
				out.append((boom * 0.9 + second + lp * exp(-t * 9.0) * 0.5) * 0.9)

		"click", "empty":
			count = int(RATE * 0.07)
			for i in range(count):
				var t: float = float(i) / RATE
				var metal: float = sin(TAU * (980.0 + 2400.0 * t) * t) * exp(-t * 95.0)
				out.append(
					(
						(metal * 0.45 + _noise() * exp(-t * 160.0) * 0.25)
						* (0.45 if name == "empty" else 0.8)
					)
				)

		"spark":
			count = int(RATE * 0.3)
			for i in range(count):
				var t: float = float(i) / RATE
				var crackle: float = 0.0
				if _rng.randf() < 0.16:
					crackle = _noise()
				lp = lerpf(lp, crackle, 0.6)
				out.append(lp * exp(-t * 7.0) * 0.7 + _tone(t, 2400.0) * exp(-t * 40.0) * 0.06)

		"rattle":
			count = int(RATE * 0.4)
			for i in range(count):
				var t: float = float(i) / RATE
				var bump: float = 0.0
				if _rng.randf() < 0.22:
					bump = _noise()
				lp = lerpf(lp, bump, 0.45)
				lp2 = lerpf(lp2, lp, 0.18)
				var metallic: float = sin(TAU * 1750.0 * t) * absf(lp - lp2)
				out.append(((lp - lp2) * 0.55 + metallic * 0.6) * _env(t, 0.01, 0.16))

		"screw":
			count = int(RATE * 0.55)
			for i in range(count):
				var t: float = float(i) / RATE
				var phase: float = t * (70.0 + 45.0 * sin(t * 19.0))
				var saw: float = 2.0 * _fract(phase) - 1.0
				lp = lerpf(lp, _noise(), 0.12)
				out.append(
					(saw * 0.16 + lp * 0.5) * (0.55 + 0.45 * sin(t * 41.0)) * _env(t, 0.03, 0.3)
				)

		"battery_in":
			count = int(RATE * 0.25)
			for i in range(count):
				var t: float = float(i) / RATE
				var clack: float = 0.0
				if t < 0.03 or (t > 0.12 and t < 0.15):
					clack = _noise() * exp(-((t if t < 0.03 else t - 0.12) * 180.0))
				out.append(clack * 0.55 + sin(TAU * 120.0 * t) * exp(-t * 16.0) * 0.3)

		"locker_creak":
			count = int(RATE * 1.1)
			for i in range(count):
				var t: float = float(i) / RATE
				var wobble: float = sin(TAU * (3.0 + 7.0 * t) * t)
				var saw: float = 2.0 * _fract(t * (110.0 + wobble * 34.0)) - 1.0
				lp = lerpf(lp, _noise(), 0.05)
				var env: float = _env(t, 0.12, 0.45)
				out.append((saw * 0.13 + lp * 0.14) * env * (0.6 + 0.4 * wobble))

		"door_slam":
			count = int(RATE * 0.5)
			for i in range(count):
				var t: float = float(i) / RATE
				var boom: float = sin(TAU * (95.0 - 60.0 * t) * t) * exp(-t * 8.0)
				lp = lerpf(lp, _noise(), 0.3)
				out.append((boom * 0.75 + lp * exp(-t * 12.0) * 0.35) * _env(t, 0.002, 0.2))

		"heartbeat":
			count = int(RATE * 0.92)
			for i in range(count):
				var t: float = float(i) / RATE
				var d1: float = t - 0.04
				var d2: float = t - 0.31
				var b1: float = (
					sin(TAU * 52.0 * maxf(d1, 0.0)) * exp(-maxf(d1, 0.0) * 26.0)
					if d1 >= 0.0
					else 0.0
				)
				var b2: float = (
					sin(TAU * 43.0 * maxf(d2, 0.0)) * exp(-maxf(d2, 0.0) * 30.0) * 0.72
					if d2 >= 0.0
					else 0.0
				)
				out.append((b1 + b2) * 0.85)

		"breath_in", "breath_out":
			var inhale: bool = name == "breath_in"
			count = int(RATE * (0.6 if inhale else 0.72))
			for i in range(count):
				var t: float = float(i) / RATE
				var u: float = t / float(count) * RATE
				lp = lerpf(lp, _noise(), 0.12)
				lp2 = lerpf(lp2, lp, 0.1)
				var airy: float = (lp - lp2) * 1.7
				var shape: float = (0.25 + u * 0.75) if inhale else (1.0 - u * 0.75)
				out.append(airy * shape * 0.75)

		"gasp":
			count = int(RATE * 0.8)
			for i in range(count):
				var t: float = float(i) / RATE
				lp = lerpf(lp, _noise(), 0.1)
				lp2 = lerpf(lp2, lp, 0.08)
				var shiver: float = 1.0 + sin(TAU * 17.0 * t) * 0.35
				var shape: float = (
					exp(-pow((t - 0.16) / 0.14, 2.0)) * 1.0 + exp(-pow((t - 0.55) / 0.2, 2.0)) * 0.6
				)
				out.append((lp - lp2) * 2.0 * shape * shiver)

		"roar":
			count = int(RATE * 1.35)
			for i in range(count):
				var t: float = float(i) / RATE
				var u: float = t / 1.35
				var env: float = _env(t, 0.06, 0.55)
				var growl: float = sin(TAU * (54.0 + 22.0 * sin(t * 9.0)) * t)
				var saw: float = 2.0 * _fract(t * (88.0 + 40.0 * u)) - 1.0
				lp = lerpf(lp, _noise(), 0.16)
				var wet: float = sin(TAU * 7.0 * t) * 0.5 + 0.5
				out.append(clampf((growl * 0.5 + saw * 0.22 + lp * 0.65 * wet) * env, -1.0, 1.0))

		"growl_loop":
			count = int(RATE * 2.0)
			var phase_lp: float = 0.0
			for i in range(count):
				var t: float = float(i) / RATE
				var breath: float = 0.5 + 0.5 * sin(TAU * 0.78 * t - PI * 0.5)
				var rumble: float = sin(TAU * 39.0 * t) * 0.3 + sin(TAU * 57.0 * t) * 0.12
				phase_lp = lerpf(phase_lp, _noise(), 0.045)
				var gurgle: float = (
					sin(TAU * (180.0 + 90.0 * breath) * t) * exp(-_fract(t * 0.78) * 7.0) * 0.12
				)
				out.append((rumble + phase_lp * 0.5 * (0.35 + breath * 0.65) + gurgle) * 0.55)

		"ambient", "drone":
			count = int(RATE * 4.0)
			var hum_lp: float = 0.0
			for i in range(count):
				var t: float = float(i) / RATE
				hum_lp = lerpf(hum_lp, _noise(), 0.008)
				var drone: float = sin(TAU * 41.0 * t) * 0.16 + sin(TAU * 41.7 * t) * 0.11
				var air: float = hum_lp * 0.5
				out.append((drone + air) * (0.75 + 0.25 * sin(TAU * 0.11 * t)))

		"scream":
			count = int(RATE * 1.4)
			for i in range(count):
				var t: float = float(i) / RATE
				var u: float = t / 1.4
				var env: float = _env(t, 0.03, 0.7)
				var f: float = 320.0 + 900.0 * u
				var dissonance: float = sin(TAU * f * t) * 0.45 + sin(TAU * f * 1.41 * t) * 0.3
				lp = lerpf(lp, _noise(), 0.25)
				out.append(clampf((dissonance + lp * 0.55) * env, -1.0, 1.0))

		_:
			count = int(RATE * 0.1)
			for i in range(count):
				out.append(0.0)

	# Мягкий fade по краям, чтобы не было щелчков.
	var fade: int = mini(160, count / 8)
	for i in range(fade):
		var k: float = float(i) / float(fade)
		out[i] *= k
		out[count - 1 - i] *= k
	return out
