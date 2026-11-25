extends Node3D

signal service_mode_changed(active: bool)
signal battery_changed(charge: float, max_charge: float)
signal state_changed

@onready var spot: SpotLight3D = $SpotLight3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var head_mesh: MeshInstance3D = $HeadMesh
@onready var cap: Node3D = $Cap
@onready var cap_mesh: MeshInstance3D = $Cap/CapMesh
@onready var battery_slot: Node3D = $BatterySlot

enum ServiceStep { NONE, UNSCREW, SWAP, SCREW }

var is_on: bool = true
var wants_on: bool = true
var battery_charge: float = 100.0
var max_battery_charge: float = 100.0
var drain_per_second: float = 0.55 # ~3 minutes full

var broken_contact: bool = false
var flicker_timer: float = 0.0
var next_flicker_time: float = 5.0
var _flicker_active: float = 0.0
var _rng := RandomNumberGenerator.new()

# Shake to fix
var _shake_energy: float = 0.0
var _shake_threshold: float = 1800.0 # accumulated mouse movement
var _shake_decay: float = 1200.0
var _last_shake_dir: Vector2 = Vector2.ZERO

# Service mode
var service_active: bool = false
var service_step: int = ServiceStep.NONE
var unscrew_progress: float = 0.0 # 0 closed, 1 fully unscrewed
var cap_on: bool = true
var has_battery_inside: bool = true
var _service_base_pos: Vector3
var _service_base_rot: Vector3
var _wheel_accum: float = 0.0
var _swap_done: bool = false

# Visual
var _base_light_energy: float = 3.0
var _target_light_energy: float = 3.0
var _flicker_noise_t: float = 0.0

# Audio
var _rattle_player: AudioStreamPlayer3D = null

# Battery visual
var _battery_mesh: MeshInstance3D = null

func _ready() -> void:
	_rng.randomize()
	_base_light_energy = spot.light_energy
	_service_base_pos = position
	_service_base_rot = rotation
	_schedule_next_flicker()
	_setup_materials()
	_ensure_battery_mesh()
	_update_battery_visual()
	battery_changed.emit(battery_charge, max_battery_charge)

func _setup_materials() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.16, 0.17)
	mat.metallic = 0.8
	mat.roughness = 0.35
	body_mesh.material_override = mat
	var hmat := mat.duplicate()
	hmat.albedo_color = Color(0.12, 0.13, 0.14)
	head_mesh.material_override = hmat
	var cmat := mat.duplicate()
	cmat.albedo_color = Color(0.18, 0.18, 0.19)
	cap_mesh.material_override = cmat

func _ensure_battery_mesh() -> void:
	_battery_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.018
	cyl.height = 0.09
	_battery_mesh.mesh = cyl
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.1, 0.35, 0.15)
	bmat.metallic = 0.2
	bmat.roughness = 0.6
	_battery_mesh.material_override = bmat
	_battery_mesh.transform = Transform3D(1,0,0, 0,-4.37114e-08,-1, 0,1,-4.37114e-08, 0,0,0)
	battery_slot.add_child(_battery_mesh)

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_game_over or GameManager.is_paused:
		return
	if event is InputEventMouseMotion:
		_on_mouse_motion(event.relative)
	if service_active:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_apply_wheel(1.0)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_apply_wheel(-1.0)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				_try_swap_battery()
				get_viewport().set_input_as_handled()
		if event.is_action_pressed("interact"):
			_try_swap_battery()
			get_viewport().set_input_as_handled()
		if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			# Esc during service: cancel service but leave disassembled
			cancel_service_mode()
			get_viewport().set_input_as_handled()
		if event.is_action_pressed("flashlight_service"):
			# R again toggles out? better ignore or cancel; spec says Esc/Tab cancel
			pass

func _on_mouse_motion(rel: Vector2) -> void:
	# Shake detection always active when broken contact
	var mag := rel.length()
	if broken_contact and wants_on and cap_on and has_battery_inside and battery_charge > 0.0:
		_shake_energy += mag * 3.0
		# Bonus for direction changes
		if _last_shake_dir.length() > 0.1 and rel.length() > 0.1:
			var dot := _last_shake_dir.normalized().dot(rel.normalized())
			if dot < -0.2:
				_shake_energy += mag * 4.0
		if rel.length() > 0.5:
			_last_shake_dir = rel
		# Visual shake of flashlight
		rotation.x = _service_base_rot.x + randf_range(-0.08, 0.08) * clampf(_shake_energy / _shake_threshold, 0.0, 1.0)
		rotation.z = _service_base_rot.z + randf_range(-0.08, 0.08) * clampf(_shake_energy / _shake_threshold, 0.0, 1.0)
		if _shake_energy >= _shake_threshold:
			_fix_contact()

	# Service mode gestures: circular motion for unscrew/screw
	if service_active and (service_step == ServiceStep.UNSCREW or service_step == ServiceStep.SCREW):
		# Circular motion detection: accumulate signed angle-ish movement
		var cross := rel.x * 0.5 - rel.y * 0.5
		if service_step == ServiceStep.UNSCREW:
			_wheel_accum += abs(rel.x) * 0.003 + abs(rel.y) * 0.003
		else:
			_wheel_accum += abs(rel.x) * 0.003 + abs(rel.y) * 0.003

func _process(delta: float) -> void:
	_flicker_noise_t += delta
	_update_shake_decay(delta)
	_update_flicker(delta)
	_update_drain(delta)
	_update_light(delta)
	_update_service_animation(delta)

func _update_shake_decay(delta: float) -> void:
	if _shake_energy > 0.0:
		_shake_energy = maxf(0.0, _shake_energy - _shake_decay * delta)
	if not broken_contact:
		# Gently return rotation
		rotation.x = lerpf(rotation.x, _service_base_rot.x, 10.0 * delta)
		rotation.z = lerpf(rotation.z, _service_base_rot.z, 10.0 * delta)

func _schedule_next_flicker() -> void:
	var base := randf_range(4.0, 12.0)
	if battery_charge < 20.0:
		base *= 0.45
	next_flicker_time = base

func _update_flicker(delta: float) -> void:
	if not wants_on or not cap_on or not has_battery_inside or battery_charge <= 0.0:
		return
	if broken_contact:
		return
	flicker_timer += delta
	if flicker_timer >= next_flicker_time:
		flicker_timer = 0.0
		_schedule_next_flicker()
		# Random: small flicker or full contact break
		var break_chance := 0.25
		if battery_charge < 20.0:
			break_chance = 0.4
		# Near monster increases chance slightly
		var monster = GameManager.monster
		if monster and GameManager.player:
			var d := GameManager.player.global_position.distance_to(monster.global_position)
			if d < 12.0:
				break_chance += 0.15
		if _rng.randf() < break_chance:
			_trigger_contact_break()
		else:
			_trigger_flicker()

func _trigger_flicker() -> void:
	_flicker_active = randf_range(0.15, 0.45)
	AudioSynth.play_3d("flashlight_spark", global_position, -12.0, randf_range(0.9, 1.2), self)

func _trigger_contact_break() -> void:
	broken_contact = true
	is_on = false
	spot.light_energy = 0.0
	AudioSynth.play_3d("flashlight_spark", global_position, -8.0, randf_range(0.8, 1.0), self)
	AudioSynth.play_3d("flashlight_click_dead", global_position, -10.0, 0.8, self)
	state_changed.emit()

func _fix_contact() -> void:
	broken_contact = false
	_shake_energy = 0.0
	AudioSynth.play_3d("flashlight_rattle", global_position, -8.0, 1.0, self)
	if wants_on and cap_on and has_battery_inside and battery_charge > 0.0:
		is_on = true
		spot.light_energy = _base_light_energy
	state_changed.emit()

func _update_drain(delta: float) -> void:
	if is_on and wants_on and cap_on and has_battery_inside and not broken_contact:
		battery_charge -= drain_per_second * delta
		if battery_charge <= 0.0:
			battery_charge = 0.0
			is_on = false
			wants_on = false
			broken_contact = false
			AudioSynth.play_3d("flashlight_click_dead", global_position, -10.0, 0.7, self)
		battery_changed.emit(battery_charge, max_battery_charge)

func _update_light(delta: float) -> void:
	var should_be_on := wants_on and cap_on and has_battery_inside and battery_charge > 0.0 and not broken_contact and not service_active
	is_on = should_be_on

	var energy := 0.0
	if should_be_on:
		energy = _base_light_energy
		# Dim below 20%
		if battery_charge < 20.0:
			energy *= lerpf(0.25, 0.7, battery_charge / 20.0)
		# Flicker noise
		if battery_charge < 20.0:
			var n := sin(_flicker_noise_t * 30.0) * 0.5 + sin(_flicker_noise_t * 73.0) * 0.3
			if n > 0.7:
				energy *= 0.2
		if _flicker_active > 0.0:
			_flicker_active -= delta
			var fn := randf()
			if fn < 0.4:
				energy *= 0.05
			elif fn < 0.7:
				energy *= 0.4
		# Subtle instability
		energy *= 0.95 + 0.05 * sin(_flicker_noise_t * 12.0)
	spot.light_energy = lerpf(spot.light_energy, energy, 15.0 * delta)
	spot.visible = spot.light_energy > 0.01

func toggle() -> void:
	if service_active:
		return
	if not cap_on or not has_battery_inside:
		AudioSynth.play_3d("flashlight_click_dead", global_position, -12.0, 0.8, self)
		return
	if battery_charge <= 0.0:
		AudioSynth.play_3d("flashlight_click_dead", global_position, -12.0, 0.7, self)
		wants_on = false
		return
	if broken_contact:
		AudioSynth.play_3d("flashlight_click_dead", global_position, -10.0, 0.9, self)
		return
	wants_on = !wants_on
	AudioSynth.play_3d("flashlight_click", global_position, -10.0, 1.0 if wants_on else 0.85, self)
	state_changed.emit()

func is_light_on() -> bool:
	return is_on and spot.visible

func is_broken() -> bool:
	return broken_contact

func start_service_mode() -> void:
	if service_active:
		return
	if GameManager.player and GameManager.player.is_hidden:
		return
	service_active = true
	service_step = ServiceStep.UNSCREW
	unscrew_progress = 0.0 if cap_on else 1.0
	_swap_done = false
	_wheel_accum = 0.0
	# If cap already off, jump to appropriate step
	if not cap_on:
		service_step = ServiceStep.SWAP
	AudioSynth.play_3d("flashlight_click", global_position, -14.0, 0.7, self)
	service_mode_changed.emit(true)
	state_changed.emit()

func cancel_service_mode() -> void:
	if not service_active:
		return
	service_active = false
	service_step = ServiceStep.NONE
	_wheel_accum = 0.0
	# return flashlight position
	position = _service_base_pos
	rotation = _service_base_rot
	service_mode_changed.emit(false)
	state_changed.emit()

func _finish_service_mode() -> void:
	service_active = false
	service_step = ServiceStep.NONE
	_wheel_accum = 0.0
	position = _service_base_pos
	rotation = _service_base_rot
	AudioSynth.play_3d("cap_click", global_position, -8.0, 1.0, self)
	service_mode_changed.emit(false)
	state_changed.emit()

func _apply_wheel(direction: float) -> void:
	if not service_active:
		return
	if service_step == ServiceStep.UNSCREW and direction > 0:
		unscrew_progress = clampf(unscrew_progress + 0.08, 0.0, 1.0)
		AudioSynth.play_3d("cap_unscrew", global_position, -14.0, 1.0 + unscrew_progress * 0.3, self)
		if unscrew_progress >= 1.0:
			cap_on = false
			service_step = ServiceStep.SWAP
			_swap_done = false
			_update_battery_visual()
	elif service_step == ServiceStep.SCREW and direction < 0:
		unscrew_progress = clampf(unscrew_progress - 0.08, 0.0, 1.0)
		AudioSynth.play_3d("cap_screw", global_position, -14.0, 1.0 + (1.0 - unscrew_progress) * 0.2, self)
		if unscrew_progress <= 0.0:
			cap_on = true
			_finish_service_mode()

func _try_swap_battery() -> void:
	if not service_active or service_step != ServiceStep.SWAP:
		return
	if has_battery_inside:
		# Remove old battery
		has_battery_inside = false
		var old_charge := battery_charge
		battery_charge = 0.0
		_update_battery_visual()
		AudioSynth.play_3d("battery_remove", global_position, -10.0, 1.0, self)
		# Immediately try to insert new one if available
		var new_charge := GameManager.consume_battery()
		if new_charge >= 0.0:
			has_battery_inside = true
			battery_charge = new_charge
			broken_contact = false
			_update_battery_visual()
			AudioSynth.play_3d("battery_insert", global_position, -8.0, 1.0, self)
		battery_changed.emit(battery_charge, max_battery_charge)
		# Move to screw step
		service_step = ServiceStep.SCREW
		state_changed.emit()
	else:
		# No battery inside, try insert
		var new_charge := GameManager.consume_battery()
		if new_charge >= 0.0:
			has_battery_inside = true
			battery_charge = new_charge
			broken_contact = false
			_update_battery_visual()
			AudioSynth.play_3d("battery_insert", global_position, -8.0, 1.0, self)
			battery_changed.emit(battery_charge, max_battery_charge)
		service_step = ServiceStep.SCREW
		state_changed.emit()

func _update_service_animation(delta: float) -> void:
	# Cap visual
	var cap_target_z := 0.13 + unscrew_progress * 0.18
	cap.position.z = lerpf(cap.position.z, cap_target_z, 10.0 * delta)
	cap.rotation.z = unscrew_progress * TAU * 1.5
	cap.visible = true

	# Flashlight pose during service
	var target_pos := _service_base_pos
	var target_rot := _service_base_rot
	if service_active:
		target_pos = _service_base_pos + Vector3(-0.05, 0.05, 0.12)
		target_rot = _service_base_rot + Vector3(deg_to_rad(-25), deg_to_rad(15), deg_to_rad(-10))
	position = position.lerp(target_pos, 6.0 * delta)
	if not (broken_contact and not service_active):
		rotation.x = lerpf(rotation.x, target_rot.x, 6.0 * delta)
		rotation.y = lerpf(rotation.y, target_rot.y, 6.0 * delta)
		rotation.z = lerpf(rotation.z, target_rot.z, 6.0 * delta)

	# Circular motion accumulation can also advance screw/unscrew
	if service_active and _wheel_accum > 0.25:
		if service_step == ServiceStep.UNSCREW:
			unscrew_progress = clampf(unscrew_progress + _wheel_accum * 0.15, 0.0, 1.0)
			if unscrew_progress >= 1.0:
				cap_on = false
				service_step = ServiceStep.SWAP
				_update_battery_visual()
		elif service_step == ServiceStep.SCREW:
			unscrew_progress = clampf(unscrew_progress - _wheel_accum * 0.15, 0.0, 1.0)
			if unscrew_progress <= 0.0:
				cap_on = true
				_finish_service_mode()
		_wheel_accum = 0.0

func _update_battery_visual() -> void:
	if _battery_mesh:
		_battery_mesh.visible = has_battery_inside and (not cap_on or service_active)

func get_battery_percent() -> float:
	return battery_charge

func get_service_step_name() -> String:
	match service_step:
		ServiceStep.UNSCREW:
			return "Открутите крышку (колесо мыши)"
		ServiceStep.SWAP:
			if has_battery_inside:
				return "Извлеките и вставьте батарейку (ЛКМ/E)"
			return "Вставьте батарейку (ЛКМ/E)"
		ServiceStep.SCREW:
			return "Закрутите крышку (колесо мыши вниз)"
		_:
			return ""

func is_servicing() -> bool:
	return service_active
