class_name FlashlightController
extends Node3D
## Фонарик в руке: нестабильный контакт, встряхивание мышью и пошаговая замена батарейки.

const SHAKE_THRESHOLD: float = 12.0
const DRAIN_PER_SECOND: float = 0.0062

var charge: float = 0.68
var enabled: bool = true
var broken: bool = false
var service_active: bool = false
var service_step: int = 0  # 0 — крышку открутить, 1 — батарейку заменить, 2 — закрутить
var cap_angle: float = 0.0
var battery_inserted: bool = true
var shake_score: float = 0.0
var shake_impulse: float = 0.0

var _last_mouse_dir := Vector2.ZERO
var _glitch_timer: float = 3.5
var _glitch_left: float = 0.0
var _rattle_timer: float = 0.0
var _screw_sound_timer: float = 0.0
var _notice_timer: float = 0.0
var _time: float = 0.0

var _player = null
var _light: SpotLight3D = null
var _cone: MeshInstance3D = null
var _lens: MeshInstance3D = null
var _lens_material: StandardMaterial3D = null
var _cap: Node3D = null
var _battery: Node3D = null
var _base_pos: Vector3 = Vector3(0.26, -0.27, -0.48)


func _ready() -> void:
	_player = get_parent().get_parent()
	_build_model()
	position = _base_pos


func _build_model() -> void:
	var dark_metal: Material = ProcMaterials.metal()
	var rust: Material = ProcMaterials.rust()

	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.055
	body_mesh.bottom_radius = 0.062
	body_mesh.height = 0.38
	body_mesh.radial_segments = 16
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = dark_metal
	body.rotation.x = PI * 0.5
	body.position.z = 0.02
	add_child(body)

	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.067
	grip_mesh.bottom_radius = 0.067
	grip_mesh.height = 0.13
	var grip := MeshInstance3D.new()
	grip.mesh = grip_mesh
	grip.material_override = rust
	grip.rotation.x = PI * 0.5
	grip.position.z = 0.13
	add_child(grip)

	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.115
	head_mesh.bottom_radius = 0.075
	head_mesh.height = 0.15
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = dark_metal
	head.rotation.x = PI * 0.5
	head.position.z = -0.21
	add_child(head)

	var bezel_mesh := CylinderMesh.new()
	bezel_mesh.top_radius = 0.12
	bezel_mesh.bottom_radius = 0.12
	bezel_mesh.height = 0.035
	var bezel := MeshInstance3D.new()
	bezel.mesh = bezel_mesh
	bezel.material_override = rust
	bezel.rotation.x = PI * 0.5
	bezel.position.z = -0.30
	add_child(bezel)

	_lens_material = (
		ProcMaterials.emissive(Color(1.0, 0.93, 0.75), 1.0).duplicate() as StandardMaterial3D
	)
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.095
	lens_mesh.bottom_radius = 0.095
	lens_mesh.height = 0.012
	_lens = MeshInstance3D.new()
	_lens.mesh = lens_mesh
	_lens.material_override = _lens_material
	_lens.rotation.x = PI * 0.5
	_lens.position.z = -0.318
	add_child(_lens)

	_cap = Node3D.new()
	_cap.position.z = 0.29
	add_child(_cap)
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.063
	cap_mesh.bottom_radius = 0.063
	cap_mesh.height = 0.13
	var cap_visual := MeshInstance3D.new()
	cap_visual.mesh = cap_mesh
	cap_visual.material_override = dark_metal
	cap_visual.rotation.x = PI * 0.5
	_cap.add_child(cap_visual)

	_battery = Node3D.new()
	_battery.position.z = 0.10
	add_child(_battery)
	var bat_mesh := CylinderMesh.new()
	bat_mesh.top_radius = 0.041
	bat_mesh.bottom_radius = 0.041
	bat_mesh.height = 0.17
	var bat_visual := MeshInstance3D.new()
	bat_visual.mesh = bat_mesh
	bat_visual.material_override = ProcMaterials.rust()
	bat_visual.rotation.x = PI * 0.5
	_battery.add_child(bat_visual)
	_battery.visible = false

	_light = SpotLight3D.new()
	_light.position.z = -0.33
	_light.spot_angle = deg_to_rad(29.0)
	_light.spot_angle_attenuation = 0.35
	_light.spot_range = 21.0
	_light.light_color = Color(1.0, 0.92, 0.76)
	_light.light_energy = 0.0
	_light.shadow_enabled = true
	add_child(_light)

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 2.5
	cone_mesh.bottom_radius = 0.04
	cone_mesh.height = 6.4
	cone_mesh.radial_segments = 20
	_cone = MeshInstance3D.new()
	_cone.mesh = cone_mesh
	_cone.material_override = ProcMaterials.light_cone()
	_cone.rotation.x = -PI * 0.5
	_cone.position.z = -3.5
	_cone.visible = false
	add_child(_cone)

	var particles := CPUParticles3D.new()
	particles.amount = 26
	particles.lifetime = 3.2
	particles.emitting = true
	particles.direction = Vector3(0.0, 0.0, -1.0)
	particles.spread = 28.0
	particles.initial_velocity_min = 0.08
	particles.initial_velocity_max = 0.35
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.22, 0.22, 2.6)
	particles.gravity = Vector3.ZERO
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.022)
	particles.mesh = quad
	particles.material_override = ProcMaterials.dust()
	particles.position.z = -1.3
	add_child(particles)


func _process(delta: float) -> void:
	_time += delta
	shake_score = maxf(0.0, shake_score - delta * 2.0)
	shake_impulse = maxf(0.0, shake_impulse - delta * 2.2)
	_screw_sound_timer = maxf(0.0, _screw_sound_timer - delta)
	_notice_timer = maxf(0.0, _notice_timer - delta)

	var energy := 0.0
	if broken:
		# Контакт мёртв: кнопка не поможет, только встряхивание.
		_rattle_timer -= delta
		if shake_impulse > 0.25 and _rattle_timer <= 0.0:
			_rattle_timer = 0.24
			AudioSynth.play_2d("rattle", -13.0, randf_range(0.9, 1.2))
	elif service_active or absf(cap_angle) > 0.03 or not battery_inserted:
		# Разобранный фонарик не светит.
		pass
	elif enabled and charge > 0.0:
		charge = maxf(0.0, charge - DRAIN_PER_SECOND * delta)
		if charge <= 0.0:
			enabled = false
			AudioSynth.play_2d("click", -4.0)
			GameManager.message("Батарейка села. Нажми [R] для замены.")
		else:
			energy = 3.4 if charge > 0.2 else 1.9
			if charge < 0.2 and randf() < 0.045:
				energy *= randf_range(0.1, 0.6)
			_glitch_timer -= delta
			if _glitch_timer <= 0.0:
				_trigger_glitch()
			if _glitch_left > 0.0:
				_glitch_left -= delta
				energy *= 0.0 if randf() < 0.38 else randf_range(0.15, 0.85)
				if randf() < 0.22:
					AudioSynth.play_2d("spark", -14.0, randf_range(0.9, 1.3))
			if energy > 0.2 and _notice_timer <= 0.0:
				_notice_timer = 1.4
				GameManager.notify_light(global_position, 0.35)

	_light.light_energy = energy
	_cone.visible = energy > 0.25
	_lens_material.emission_energy_multiplier = 0.2 + energy * 0.6

	# Визуал: дрожь от встряхивания и поднесение фонаря к лицу в режиме обслуживания.
	var jitter := Vector3.ZERO
	if shake_impulse > 0.01:
		jitter = (
			Vector3(sin(_time * 63.0), cos(_time * 71.0), sin(_time * 49.0)) * shake_impulse * 0.075
		)
	var target_pos := _base_pos
	if service_active:
		target_pos = Vector3(0.02, -0.13, -0.31)
	position = position.lerp(target_pos + jitter, clampf(delta * 12.0, 0.0, 1.0))
	if service_active:
		rotation.z = lerpf(rotation.z, sin(_time * 2.0) * 0.04, delta * 6.0)
	else:
		rotation.z = lerpf(rotation.z, 0.0, delta * 8.0)

	if is_instance_valid(_cap):
		_cap.rotation.z = cap_angle
		_cap.position.z = 0.29 + maxf(0.0, -cap_angle) * 0.045
	if is_instance_valid(_battery):
		var bat_z: float = 0.10 if battery_inserted else 0.56
		_battery.position.z = lerpf(_battery.position.z, bat_z, clampf(delta * 9.0, 0.0, 1.0))
		_battery.visible = not battery_inserted or _battery.position.z > 0.2


func _trigger_glitch() -> void:
	_glitch_timer = randf_range(4.0, 9.0) * (0.75 + charge * 0.4)
	_glitch_left = randf_range(0.14, 0.5)
	AudioSynth.play_2d("spark", randf_range(-13.0, -7.0), randf_range(0.85, 1.25))
	var monster_near: float = 0.0
	if GameManager.monster and is_instance_valid(GameManager.monster):
		var d: float = global_position.distance_to(GameManager.monster.global_position)
		monster_near = clampf(1.0 - d / 18.0, 0.0, 1.0)
	var break_chance: float = 0.07 + (1.0 - charge) * 0.16 + monster_near * 0.09
	if randf() < break_chance:
		break_contact()


func break_contact() -> void:
	if broken:
		return
	broken = true
	_glitch_left = 0.0
	AudioSynth.play_2d("spark", -4.0)
	GameManager.message("Контакт пропал! Тряхни мышью, чтобы починить фонарик.", 3.0)


func repair() -> void:
	if not broken:
		return
	broken = false
	shake_score = 0.0
	shake_impulse = 0.4
	_glitch_timer = randf_range(4.0, 8.0)
	enabled = charge > 0.0
	AudioSynth.play_2d("click", -4.0)
	GameManager.message("Контакт восстановлен.")


func toggle() -> void:
	if service_active:
		return
	AudioSynth.play_2d("click", -6.0)
	if broken:
		GameManager.message("Кнопка не помогает. Тряхни мышью.", 2.5)
		return
	if charge <= 0.0:
		GameManager.message("Батарейка разряжена — нажми [R].")
		return
	enabled = not enabled
	GameManager.message("Фонарик " + ("включён" if enabled else "выключен"), 1.2)


func register_shake(relative: Vector2) -> void:
	var amount: float = relative.length()
	if amount < 2.5:
		return
	var direction := relative.normalized()
	if _last_mouse_dir != Vector2.ZERO and direction.dot(_last_mouse_dir) < -0.2:
		shake_score += minf(amount, 120.0) * 0.055
	else:
		shake_score += minf(amount, 120.0) * 0.006
	_last_mouse_dir = direction
	shake_impulse = clampf(shake_impulse + amount * 0.005, 0.0, 1.0)
	if broken and shake_score >= SHAKE_THRESHOLD:
		repair()


func begin_service() -> void:
	if service_active:
		return
	service_active = true
	if _player:
		_player.service_mode = true
	if absf(cap_angle) < 0.1:
		service_step = 0
	elif not battery_inserted:
		service_step = 1
	else:
		service_step = 2
	AudioSynth.play_2d("click", -8.0)
	_show_service_hint()


func cancel_service() -> void:
	if not service_active:
		return
	service_active = false
	if _player:
		_player.service_mode = false
	GameManager.message("Фонарик остался разобранным. [R] — продолжить сборку.", 3.0)


func on_wheel(direction: float) -> void:
	if not service_active:
		return
	if _screw_sound_timer <= 0.0:
		AudioSynth.play_2d("screw", -11.0, randf_range(0.9, 1.1))
		_screw_sound_timer = 0.12
	if service_step == 0 and direction > 0.0:
		cap_angle = clampf(cap_angle - 0.45, -4.95, 0.0)
		if cap_angle <= -4.9:
			service_step = 1
			AudioSynth.play_2d("battery_in", -8.0)
			_show_service_hint()
	elif service_step == 2 and direction < 0.0:
		cap_angle = clampf(cap_angle + 0.45, -4.95, 0.0)
		if cap_angle >= -0.01:
			_finish_service()


func on_action() -> void:
	if not service_active or service_step != 1:
		return
	if battery_inserted:
		battery_inserted = false
		AudioSynth.play_2d("rattle", -9.0)
		GameManager.message("Старая батарейка вытряхнута. [E] — вставить новую.", 2.5)
	elif _player and _player.batteries.size() > 0:
		charge = _player.consume_battery()
		battery_inserted = true
		service_step = 2
		AudioSynth.play_2d("battery_in", -4.0)
		_show_service_hint()
	else:
		GameManager.message("В инвентаре нет батареек.", 2.0)


func _finish_service() -> void:
	cap_angle = 0.0
	battery_inserted = true
	service_active = false
	broken = false
	enabled = charge > 0.0
	if _player:
		_player.service_mode = false
	AudioSynth.play_2d("click", -3.0)
	GameManager.message(
		"Фонарик собран." if enabled else "Фонарик собран, но батарейка пуста.", 2.0
	)


func _show_service_hint() -> void:
	var hint := ""
	match service_step:
		0:
			hint = "Открутить крышку: крути колесо мыши вверх"
		1:
			hint = "[E] вытряхнуть старую батарейку, затем [E] вставить новую"
		2:
			hint = "Закрутить крышку: колесо мыши вниз"
	GameManager.message(hint, 3.0)


func service_status() -> String:
	if not service_active and absf(cap_angle) < 0.03:
		return ""
	return "Обслуживание: " + str(service_step + 1) + "/3"
