class_name PlayerController
extends CharacterBody3D
## Контроллер от первого лица: ходьба, бег, приседание, взаимодействие, скрытие в шкафу.

const EYE_HEIGHT: float = 1.62
const CROUCH_HEIGHT: float = 1.08
const MOUSE_SENSITIVITY: float = 0.0022

var yaw: float = 0.0
var pitch: float = 0.0
var stamina: float = 100.0
var crouched: bool = false
var hidden: bool = false
var hidden_locker = null
var service_mode: bool = false
var batteries: Array = []  # BatteryItem
var target_interactable = null
var fear: float = 0.0
var tremor: float = 0.0

var _bob: float = 0.0
var _time: float = 0.0
var _noise_timer: float = 0.0
var _light_noise_timer: float = 0.0
var _sway := Vector2.ZERO
var _heartbeat_timer: float = 0.0
var _last_breathing_end: float = -99.0
var _breathing_was_active: bool = false
var _ray: RayCast3D = null
var _camera: Camera3D = null

@onready var flashlight = $Camera3D/Flashlight


func _ready() -> void:
	GameManager.player = self
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	collision_layer = 4
	collision_mask = 1
	_camera = $Camera3D
	_ray = $Camera3D/InteractRay
	_ray.collide_with_areas = true
	_ray.collision_mask = 3
	_ray.target_position = Vector3(0.0, 0.0, -3.2)


func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_game_over or GameManager.is_paused:
		return

	if event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		flashlight.register_shake(rel)
		var factor: float = 0.12 if service_mode else 1.0
		if hidden:
			factor = 0.35
		yaw -= rel.x * MOUSE_SENSITIVITY * factor
		pitch -= rel.y * MOUSE_SENSITIVITY * factor
		pitch = clampf(pitch, -1.25, 1.25)
		_sway.x = clampf(_sway.x + rel.x * 0.0009, -0.05, 0.05)
		_sway.y = clampf(_sway.y - rel.y * 0.0009, -0.05, 0.05)
		return

	if event is InputEventMouseButton:
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			flashlight.on_wheel(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			flashlight.on_wheel(-1.0)
		elif event.button_index == MOUSE_BUTTON_LEFT and service_mode and not hidden:
			flashlight.on_action()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				if hidden and GameManager.breathing and GameManager.breathing.active:
					return
				if flashlight.service_active and not hidden:
					flashlight.on_action()
				else:
					interact()
			KEY_Q:
				if hidden and GameManager.breathing:
					GameManager.breathing.handle_key(KEY_Q)
			KEY_SPACE:
				if hidden and GameManager.breathing:
					GameManager.breathing.handle_key(KEY_SPACE)
			KEY_R:
				if not hidden:
					if flashlight.service_active:
						flashlight.cancel_service()
					else:
						flashlight.begin_service()
			KEY_F:
				if not hidden:
					flashlight.toggle()
			KEY_TAB:
				if flashlight.service_active:
					flashlight.cancel_service()
			KEY_ESCAPE:
				if flashlight.service_active:
					flashlight.cancel_service()
				else:
					GameManager.set_paused(not GameManager.is_paused)


func _physics_process(delta: float) -> void:
	_time += delta
	tremor = maxf(0.0, tremor - delta * 1.6)
	var panic: float = GameManager.breathing.panic if GameManager.breathing else 0.0
	if fear > 0.42 or panic > 0.15:
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = lerpf(1.05, 0.58, clampf(maxf(fear, panic), 0.0, 1.0))
			AudioSynth.play_2d("heartbeat", -10.0 + maxf(fear, panic) * 8.0)

	if hidden:
		velocity = Vector3.ZERO
		_maybe_start_breathing()
		_light_noise_timer -= delta
		if flashlight.enabled and not flashlight.broken and _light_noise_timer <= 0.0:
			_light_noise_timer = 1.0
			GameManager.notify_light(global_position, 0.9)
		_camera.position.y = lerpf(_camera.position.y, CROUCH_HEIGHT, delta * 8.0)
		var shake: float = (
			tremor + (GameManager.breathing.panic if GameManager.breathing else 0.0) * 0.5
		)
		_camera.rotation.x = pitch + sin(_time * 27.0) * shake * 0.01
		_camera.rotation.z = sin(_time * 19.0) * shake * 0.012
		rotation.y = yaw
		return

	var move_input := (
		Vector2(
			(
				(1.0 if Input.is_key_pressed(KEY_D) else 0.0)
				- (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
			),
			(
				(1.0 if Input.is_key_pressed(KEY_W) else 0.0)
				- (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
			)
		)
		. clamped(1.0)
	)
	crouched = Input.is_key_pressed(KEY_CTRL) and not service_mode
	var running: bool = (
		Input.is_key_pressed(KEY_SHIFT)
		and not crouched
		and not service_mode
		and move_input.length() > 0.1
		and stamina > 0.0
	)

	if running:
		stamina = maxf(0.0, stamina - 27.0 * delta)
	else:
		stamina = minf(100.0, stamina + 17.0 * delta)

	var speed: float = 3.05
	if crouched:
		speed = 1.55
	elif running:
		speed = 5.5
	if service_mode:
		speed = 0.85

	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var target_velocity: Vector3 = (forward * move_input.y + right * move_input.x) * speed
	var accel: float = 11.0 if is_on_floor() else 3.0
	velocity.x = lerpf(velocity.x, target_velocity.x, clampf(delta * accel, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, target_velocity.z, clampf(delta * accel, 0.0, 1.0))
	velocity.y -= 12.0 * delta
	move_and_slide()

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if planar_speed > 0.35:
		_bob += delta * planar_speed * 2.3
	_noise_timer -= delta
	if planar_speed > 0.5 and _noise_timer <= 0.0:
		_noise_timer = 0.30 if running else (0.80 if crouched else 0.50)
		AudioSynth.play_2d(
			"step_sprint" if running else "step",
			-8.0 if crouched else (-2.0 if running else -7.0),
			randf_range(0.93, 1.07)
		)
		if not crouched:
			GameManager.emit_noise(global_position, 1.0 if running else 0.32, "step")

	var eye: float = CROUCH_HEIGHT if crouched else EYE_HEIGHT
	var bob_amount: float = minf(planar_speed / 3.0, 1.0)
	_camera.position.y = lerpf(
		_camera.position.y,
		eye + sin(_bob * 2.0) * 0.038 * bob_amount,
		clampf(delta * 10.0, 0.0, 1.0)
	)
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 5.0, 0.0, 1.0))
	_camera.position.x = lerpf(
		_camera.position.x, cos(_bob) * 0.022 * bob_amount + _sway.x, clampf(delta * 8.0, 0.0, 1.0)
	)
	_camera.rotation.x = pitch + sin(_time * 31.0) * tremor * 0.012
	_camera.rotation.z = (
		-cos(_bob) * 0.010 * bob_amount - _sway.x * 0.35 + cos(_time * 23.0) * tremor * 0.01
	)
	rotation.y = yaw

	_update_interaction()
	_update_fear(delta)


func _maybe_start_breathing() -> void:
	var breathing = GameManager.breathing
	if not breathing:
		return
	if _breathing_was_active and not breathing.active:
		_last_breathing_end = _time
	_breathing_was_active = breathing.active
	if breathing.active or GameManager.is_game_over:
		return
	var monster = GameManager.monster
	if not monster or not is_instance_valid(monster) or monster.state == "KILL":
		return
	if (
		global_position.distance_to(monster.global_position) <= 10.0
		and _time - _last_breathing_end > 6.0
	):
		breathing.start(self.hidden_locker, monster)


func _update_interaction() -> void:
	_ray.force_raycast_update()
	var collider: Object = _ray.get_collider()
	if collider and collider.has_method("interact") and collider != self:
		target_interactable = collider
	else:
		target_interactable = null


func _update_fear(delta: float) -> void:
	var target_fear: float = 0.0
	if GameManager.monster and is_instance_valid(GameManager.monster):
		var d: float = global_position.distance_to(GameManager.monster.global_position)
		var proximity: float = clampf(1.0 - d / 20.0, 0.0, 1.0)
		target_fear = proximity * (1.25 if GameManager.monster.state == "CHASE" else 0.8)
	fear = lerpf(fear, clampf(target_fear, 0.0, 1.0), clampf(delta * 2.5, 0.0, 1.0))
	if GameManager.hud and is_instance_valid(GameManager.hud):
		var panic: float = GameManager.breathing.panic if GameManager.breathing else 0.0
		GameManager.hud.set_fear(maxf(fear, panic * 0.75))


func interact() -> void:
	if hidden:
		if hidden_locker:
			hidden_locker.exit_locker(self)
		return
	if target_interactable and is_instance_valid(target_interactable):
		target_interactable.interact(self)


func interaction_hint() -> String:
	if hidden:
		return "Выйти из шкафа [E]"
	if service_mode and flashlight.has_method("service_status"):
		var s: String = flashlight.service_status()
		if s != "":
			return s
	if (
		target_interactable
		and is_instance_valid(target_interactable)
		and target_interactable.has_method("interact_text")
	):
		return target_interactable.interact_text(self)
	return ""


func enter_locker(locker) -> void:
	hidden = true
	hidden_locker = locker
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	global_position = locker.global_position
	yaw = locker.look_yaw
	pitch = 0.0
	GameManager.lockers_used += 1
	if flashlight.enabled and not flashlight.broken:
		GameManager.message("Свет идёт из щелей — монстр может заметить!", 3.0)
	else:
		GameManager.message("Ты внутри. Дыши ровно: [Q] вдох, [Space] выдох.", 3.0)
	if GameManager.monster and is_instance_valid(GameManager.monster):
		var d: float = global_position.distance_to(GameManager.monster.global_position)
		var state: String = GameManager.monster.state
		var start_breathing: bool = d <= 12.0 or state == "CHASE" or state == "CHECK_LOCKER"
		GameManager.monster.player_entered_locker(locker)
		if start_breathing and GameManager.breathing and is_instance_valid(GameManager.breathing):
			GameManager.breathing.start(locker, GameManager.monster)


func exit_locker(_locker = null) -> void:
	if not hidden:
		return
	var locker = hidden_locker
	hidden = false
	hidden_locker = null
	collision_layer = 4
	collision_mask = 1
	if locker and is_instance_valid(locker):
		global_position = locker.exit_position
	if GameManager.breathing and is_instance_valid(GameManager.breathing):
		GameManager.breathing.stop()
	if GameManager.monster and is_instance_valid(GameManager.monster):
		GameManager.monster.player_left_locker()


func add_battery(charge: float) -> bool:
	if batteries.size() >= 6:
		GameManager.message("Инвентарь полон (6 батареек).")
		return false
	batteries.append(BatteryItem.new(charge))
	GameManager.message("Батарейка в инвентаре: " + str(int(charge * 100.0)) + "%", 1.5)
	return true


func consume_battery() -> float:
	if batteries.is_empty():
		return -1.0
	var item: BatteryItem = batteries.pop_back() as BatteryItem
	return item.charge


func add_tremor(amount: float) -> void:
	tremor = clampf(tremor + amount, 0.0, 1.5)


func die(cause: String) -> void:
	GameManager.report_death(cause)
