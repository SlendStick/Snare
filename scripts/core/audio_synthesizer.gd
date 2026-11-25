extends Node

# Procedural audio generator for horror SFX.
# Generates AudioStreamWAV buffers at runtime so the project has no external assets.

var _cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func get_sfx(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var stream: AudioStreamWAV = _generate(name)
	_cache[name] = stream
	return stream

func play_2d(name: String, volume_db: float = 0.0, pitch: float = 1.0, parent: Node = null) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = get_sfx(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = "Master"
	(parent if parent != null else get_tree().current_scene).add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p

func play_3d(name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, parent: Node = null) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_sfx(name)
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 8.0
	p.max_distance = 30.0
	p.bus = "Master"
	(parent if parent != null else get_tree().current_scene).add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p

func make_loop_player_3d(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var s := get_sfx(name)
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 8.0
	p.max_distance = 35.0
	p.bus = "Master"
	return p

func make_loop_player_2d(name: String, volume_db: float = -6.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = get_sfx(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = "Master"
	return p

func _generate(name: String) -> AudioStreamWAV:
	match name:
		"footstep":
			return _make_wav(_gen_noise_burst(0.11, 220.0, 0.35), 22050)
		"footstep_run":
			return _make_wav(_gen_noise_burst(0.09, 320.0, 0.45), 22050)
		"flashlight_click":
			return _make_wav(_gen_click(0.04, 1800.0), 22050)
		"flashlight_click_dead":
			return _make_wav(_gen_click(0.06, 400.0, 0.3), 22050)
		"flashlight_spark":
			return _make_wav(_gen_spark(0.18), 22050)
		"flashlight_rattle":
			return _make_wav(_gen_rattle(0.35), 22050)
		"cap_unscrew":
			return _make_wav(_gen_screw(0.45, 1.0), 22050)
		"cap_screw":
			return _make_wav(_gen_screw(0.45, -1.0), 22050)
		"cap_click":
			return _make_wav(_gen_click(0.06, 2200.0, 0.8), 22050)
		"battery_insert":
			return _make_wav(_gen_thud(0.15, 160.0), 22050)
		"battery_remove":
			return _make_wav(_gen_thud(0.12, 120.0, 0.5), 22050)
		"battery_pickup":
			return _make_wav(_gen_pickup(0.3), 22050)
		"locker_open":
			return _make_wav(_gen_creak(0.55, 1.0), 22050)
		"locker_close":
			return _make_wav(_gen_creak(0.45, -1.0), 22050)
		"locker_slam":
			return _make_wav(_gen_slam(0.5), 22050)
		"heartbeat":
			return _make_wav(_gen_heartbeat(0.8), 22050, true)
		"breath_calm":
			return _make_wav(_gen_breath(1.6, 0.25), 22050, true)
		"breath_panic":
			return _make_wav(_gen_breath(0.9, 0.7), 22050, true)
		"breath_gasp":
			return _make_wav(_gen_gasp(0.5), 22050)
		"monster_breath":
			return _make_wav(_gen_monster_breath(2.4), 22050, true)
		"monster_growl":
			return _make_wav(_gen_monster_growl(1.4), 22050)
		"monster_roar":
			return _make_wav(_gen_monster_roar(1.8), 22050)
		"monster_step":
			return _make_wav(_gen_monster_step(0.35), 22050)
		"scare_sting":
			return _make_wav(_gen_scare(1.2), 22050)
		"ambience":
			return _make_wav(_gen_ambience(4.0), 22050, true)
		_:
			return _make_wav(_gen_click(0.05, 440.0), 22050)

func _make_wav(samples: PackedFloat32Array, sample_rate: int, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	else:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav

func _env(t: float, length: float, attack: float = 0.01, release: float = 0.1) -> float:
	var a := clampf(t / maxf(attack, 0.001), 0.0, 1.0)
	var r := clampf((length - t) / maxf(release, 0.001), 0.0, 1.0)
	return minf(a, r)

func _white_noise(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(-1.0, 1.0)

func _gen_noise_burst(duration: float, cutoff: float, amp: float = 0.5) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(duration * 1000.0 + cutoff)
	var lp := 0.0
	var rc := 1.0 / (cutoff * TAU)
	var dt := 1.0 / sr
	var alpha := dt / (rc + dt)
	for i in n:
		var t := float(i) / sr
		lp += alpha * (_white_noise(rng) - lp)
		out[i] = lp * _env(t, duration, 0.005, 0.06) * amp
	return out

func _gen_click(duration: float, freq: float, amp: float = 0.6) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 13 + duration * 1000)
	for i in n:
		var t := float(i) / sr
		var s := sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 2.3 * t) * 0.2 + _white_noise(rng) * 0.2
		out[i] = s * _env(t, duration, 0.001, duration * 0.7) * amp
	return out

func _gen_spark(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99173
	for i in n:
		var t := float(i) / sr
		var crackle := 0.0
		if rng.randf() < 0.04:
			crackle = rng.randf_range(-1.0, 1.0)
		var hiss := _white_noise(rng) * 0.15
		out[i] = (crackle + hiss) * _env(t, duration, 0.001, 0.08) * 0.45
	return out

func _gen_rattle(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7731
	for i in n:
		var t := float(i) / sr
		var pulse := maxf(0.0, sin(TAU * 28.0 * t))
		var grain := _white_noise(rng) * pulse
		var clack := sin(TAU * 900.0 * t) * pow(maxf(0.0, sin(TAU * 14.0 * t)), 8.0)
		out[i] = (grain * 0.5 + clack * 0.4) * _env(t, duration, 0.01, 0.05) * 0.5
	return out

func _gen_screw(duration: float, direction: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 441 + int(direction * 10)
	for i in n:
		var t := float(i) / sr
		var p := t / duration
		var freq := lerpf(180.0, 420.0, p if direction > 0 else 1.0 - p)
		var grit := _white_noise(rng) * 0.25 * (0.5 + 0.5 * sin(TAU * 18.0 * t))
		var tone := sin(TAU * freq * t) * 0.2
		out[i] = (grit + tone) * _env(t, duration, 0.02, 0.05) * 0.45
	return out

func _gen_thud(duration: float, freq: float, amp: float = 0.7) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq)
	for i in n:
		var t := float(i) / sr
		var s := sin(TAU * freq * t * exp(-t * 8.0)) + _white_noise(rng) * 0.1
		out[i] = s * exp(-t * 18.0) * amp
	return out

func _gen_pickup(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / sr
		var f := lerpf(500.0, 1200.0, t / duration)
		var s := sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.2
		out[i] = s * _env(t, duration, 0.005, 0.12) * 0.35
	return out

func _gen_creak(duration: float, direction: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511
	for i in n:
		var t := float(i) / sr
		var p := t / duration
		var f := lerpf(220.0, 520.0, p if direction > 0 else 1.0 - p)
		var s := sin(TAU * f * t) * 0.25 + sin(TAU * f * 1.52 * t) * 0.15 + _white_noise(rng) * 0.08
		s *= 0.7 + 0.3 * sin(TAU * 6.0 * t)
		out[i] = s * _env(t, duration, 0.03, 0.08) * 0.45
	return out

func _gen_slam(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 882
	for i in n:
		var t := float(i) / sr
		var impact := sin(TAU * 90.0 * t) * exp(-t * 14.0)
		var noise := _white_noise(rng) * exp(-t * 9.0) * 0.5
		out[i] = (impact + noise) * 0.8
	return out

func _gen_heartbeat(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / sr
		var beat := 0.0
			for b: float in [0.0, 0.22]:
				var dt: float = t - b
			if dt >= 0.0:
				beat += sin(TAU * 55.0 * dt) * exp(-dt * 18.0) * (1.0 if b == 0.0 else 0.7)
		out[i] = beat * 0.6
	return out

func _gen_breath(duration: float, intensity: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(intensity * 1000)
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		var cycle := fmod(t, duration) / duration
		var inhale := smoothstep(0.0, 0.35, cycle) * (1.0 - smoothstep(0.35, 0.5, cycle))
		var exhale := smoothstep(0.5, 0.7, cycle) * (1.0 - smoothstep(0.7, 1.0, cycle))
		var env := (inhale * 0.7 + exhale) * intensity
		lp += 0.08 * (_white_noise(rng) - lp)
		out[i] = lp * env * 0.8
	return out

func _gen_gasp(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 333
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		lp += 0.2 * (_white_noise(rng) - lp)
		var tone := sin(TAU * 320.0 * t) * 0.15
		out[i] = (lp + tone) * _env(t, duration, 0.02, 0.2) * 0.7
	return out

func _gen_monster_breath(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6661
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		var cycle := fmod(t, duration) / duration
		var env := smoothstep(0.0, 0.25, cycle) * (1.0 - smoothstep(0.45, 0.8, cycle))
		env = maxf(env, smoothstep(0.55, 0.75, cycle) * (1.0 - smoothstep(0.75, 1.0, cycle)) * 0.8)
		lp += 0.03 * (_white_noise(rng) - lp)
		var rattle := sin(TAU * 38.0 * t) * 0.2 * env
		out[i] = (lp * 1.2 + rattle) * env * 0.55
	return out

func _gen_monster_growl(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 901
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		lp += 0.04 * (_white_noise(rng) - lp)
		var low := sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 82.0 * t) * 0.3
		out[i] = (low + lp * 0.4) * _env(t, duration, 0.08, 0.3) * 0.6
	return out

func _gen_monster_roar(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 902
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		lp += 0.12 * (_white_noise(rng) - lp)
		var f := lerpf(70.0, 45.0, t / duration)
		var s := sin(TAU * f * t) * 0.5 + sin(TAU * f * 1.9 * t) * 0.25 + lp * 0.5
		out[i] = s * _env(t, duration, 0.03, 0.4) * 0.85
	return out

func _gen_monster_step(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1201
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		lp += 0.06 * (_white_noise(rng) - lp)
		var boom := sin(TAU * 45.0 * t) * exp(-t * 10.0)
		out[i] = (boom + lp * 0.3 * exp(-t * 8.0)) * 0.8
	return out

func _gen_scare(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1313
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		lp += 0.2 * (_white_noise(rng) - lp)
		var f := lerpf(180.0, 60.0, t / duration)
		var s := sin(TAU * f * t) * 0.4 + sin(TAU * f * 2.7 * t) * 0.2 + lp * 0.6
		out[i] = s * _env(t, duration, 0.005, 0.5) * 0.9
	return out

func _gen_ambience(duration: float) -> PackedFloat32Array:
	var sr := 22050
	var n := int(duration * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in n:
		var t := float(i) / sr
		lp += 0.01 * (_white_noise(rng) - lp)
		var drone := sin(TAU * 38.0 * t) * 0.15 + sin(TAU * 57.0 * t) * 0.08
		out[i] = (lp * 0.5 + drone) * 0.25
	return out
