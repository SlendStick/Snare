extends CharacterBody3D

@export var walk_speed: float = 3.6
@export var run_speed: float = 6.2
@export var crouch_speed: float = 2.0
@export var mouse_sensitivity: float = 0.0022
@export var gravity: float = 18.0
@export var jump_velocity: float = 0.0 # no jump in horror

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var hand: Node3D = $Head/Camera3D/Hand
@onready var flashlight = $Head/Camera3D/Hand/Flashlight
@onready var footstep_timer: Timer = $FootstepTimer

var maze_generator: Node = null

# Movement state
var is_crouching: bool = false
var is_running: bool = false
var stamina: float = 100.0
var max_stamina: float = 100.0
var stamina_drain: float = 22.0
var stamina_regen: float = 14.0
var stamina_regen_delay: float = 1.2
var _stamina_regen_timer: float = 0.0

# Head bob / sway
var _bob_time: float = 0.0
var _bob_amount: float = 0.035
var _bob_speed: float = 7.5
var _sway_target: Vector2 = Vector2.ZERO
var _sway_current: Vector2 = Vector2.ZERO
var _hand_base_pos: Vector3
var _head_base_y: float

# Interaction / state
var is_hidden: bool = false
var current_locker: Node = null
var is_servicing_flashlight: bool = false
var _look_enabled: bool = true

# Noise
var noise_level: float = 0.0 # 0..1, decays over time

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hand_base_pos = hand.position
	_head_base_y = head.position.y
	footstep_timer.timeout.connect(_on_footstep)
	GameManager.register_player(self)
	if flashlight and flashlight.has_signal("service_mode_changed"):
		flashlight.service_mode_changed.connect(_on_flashlight_service_mode_changed)

func set_maze_generator(m: Node) -> void:
	maze_generator = m

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_game_over:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_sway_target.x -= event.relative.x * 0.0008
		_sway_target.y -= event.relative.y * 0.0008
		if _look_enabled and not is_hidden:
			rotate_y(-event.relative.x * mouse_sensitivity)
			camera.rotate_x(-event.relative.y * mouse_sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		elif is_hidden and current_locker and current_locker.has_method("on_mouse_motion"):
			current_locker.on_mouse_motion(event.relative)

	if event.is_action_pressed("pause"):
		GameManager.toggle_pause()
		return

	if GameManager.is_paused:
		return

	if event.is_action_pressed("interact") and not is_servicing_flashlight:
		_try_interact()

	if event.is_action_pressed("flashlight_toggle") and not is_hidden:
		if flashlight and flashlight.has_method("toggle"):
			flashlight.toggle()

	if event.is_action_pressed("flashlight_service") and not is_hidden:
		if flashlight and flashlight.has_method("start_service_mode"):
			flashlight.start_service_mode()

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	if GameManager.is_paused:
		return

	_update_stamina(delta)
	_update_noise(delta)
	_update_sway(delta)

	if is_hidden:
		velocity = Vector3.ZERO
		GameManager.set_prompt("[E] Выйти из шкафа")
		return

	_handle_movement(delta)
	_handle_head_bob(delta)
	_update_interaction_prompt()
	move_and_slide()
	_update_footsteps()

func _handle_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	if direction.length() > 1.0:
		direction = direction.normalized()

	is_crouching = Input.is_action_pressed("crouch") and not is_servicing_flashlight
	var wants_run := Input.is_action_pressed("run") and not is_crouching and not is_servicing_flashlight and input_dir.y < -0.1
	is_running = wants_run and stamina > 5.0 and direction.length() > 0.1

	var speed := walk_speed
	if is_servicing_flashlight:
		speed = 1.4
	elif is_crouching:
		speed = crouch_speed
	elif is_running:
		speed = run_speed

	if direction.length() > 0.1:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0, speed * 6.0 * delta)

	# Crouch camera height
	var target_head_y := _head_base_y - (0.45 if is_crouching else 0.0)
	head.position.y = lerpf(head.position.y, target_head_y, 8.0 * delta)

func _update_stamina(delta: float) -> void:
	if is_running:
		stamina -= stamina_drain * delta
		_stamina_regen_timer = stamina_regen_delay
	else:
		_stamina_regen_timer -= delta
		if _stamina_regen_timer <= 0.0:
			stamina += stamina_regen * delta
	stamina = clampf(stamina, 0.0, max_stamina)
	GameManager.set_stamina(stamina)

func _update_noise(delta: float) -> void:
	var target_noise := 0.0
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.2:
		if is_running:
			target_noise = 1.0
		elif is_crouching:
			target_noise = 0.15
		else:
			target_noise = 0.4
	if is_servicing_flashlight:
		target_noise = maxf(target_noise, 0.1)
	noise_level = lerpf(noise_level, target_noise, 5.0 * delta)

func get_noise_level() -> float:
	return noise_level

func is_flashlight_on() -> bool:
	return flashlight != null and flashlight.has_method("is_light_on") and flashlight.is_light_on()

func _handle_head_bob(delta: float) -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.3 and is_on_floor():
		var bob_speed := _bob_speed * (1.4 if is_running else (0.7 if is_crouching else 1.0))
		_bob_time += delta * bob_speed
		var amount := _bob_amount * (1.3 if is_running else (0.6 if is_crouching else 1.0))
		camera.position.y = sin(_bob_time) * amount
		camera.position.x = cos(_bob_time * 0.5) * amount * 0.5
	else:
		_bob_time = lerpf(_bob_time, 0.0, 5.0 * delta)
		camera.position.y = lerpf(camera.position.y, 0.0, 5.0 * delta)
		camera.position.x = lerpf(camera.position.x, 0.0, 5.0 * delta)

func _update_sway(delta: float) -> void:
	_sway_target = _sway_target.lerp(Vector2.ZERO, 6.0 * delta)
	_sway_current = _sway_current.lerp(_sway_target, 8.0 * delta)
	hand.position = _hand_base_pos + Vector3(_sway_current.x, _sway_current.y, 0.0)
	hand.rotation.z = lerpf(hand.rotation.z, _sway_current.x * 2.0, 8.0 * delta)
	hand.rotation.x = lerpf(hand.rotation.x, _sway_current.y * 2.0, 8.0 * delta)

func _update_interaction_prompt() -> void:
	if is_hidden:
		return
	if is_servicing_flashlight:
		GameManager.set_prompt("Обслуживание фонарика: колесо мыши - крышка, ЛКМ - батарейка, Esc - отмена")
		return
	interact_ray.force_raycast_update()
	if interact_ray.is_colliding():
		var col = interact_ray.get_collider()
		var node = _find_interactable(col)
		if node and node.has_method("get_interact_prompt"):
			GameManager.set_prompt(node.get_interact_prompt())
			return
	# Default prompt
	if flashlight and flashlight.has_method("is_broken") and flashlight.is_broken():
		GameManager.set_prompt("Фонарик барахлит: интенсивно трясите мышью")
	else:
		GameManager.set_prompt("")

func _try_interact() -> void:
	if is_hidden:
		if current_locker and current_locker.has_method("exit_locker"):
			current_locker.exit_locker(self)
		return
	interact_ray.force_raycast_update()
	if not interact_ray.is_colliding():
		return
	var col = interact_ray.get_collider()
	var node = _find_interactable(col)
	if node and node.has_method("interact"):
		node.interact(self)

func _find_interactable(node: Node) -> Node:
	var cur := node
	for _i in range(4):
		if cur == null:
			return null
		if cur.has_method("interact") and cur.has_method("get_interact_prompt"):
			return cur
		cur = cur.get_parent()
	return null

func enter_hiding(locker: Node) -> void:
	is_hidden = true
	current_locker = locker
	velocity = Vector3.ZERO
	if flashlight and flashlight.has_method("set_enabled_by_user"):
		# Player can choose to turn off; don't force, but flashlight might be on - let them toggle
		pass
	# Hide body collisions? Keep collision but maybe move to safe spot handled by locker
	collision_layer = 0
	collision_mask = 0

func exit_hiding(_locker: Node) -> void:
	is_hidden = false
	current_locker = null
	collision_layer = 2
	collision_mask = 1
	GameManager.set_prompt("")

func _on_flashlight_service_mode_changed(active: bool) -> void:
	is_servicing_flashlight = active
	_look_enabled = not active
	if active:
		GameManager.set_prompt("Обслуживание фонарика: колесо мыши - крышка, ЛКМ - батарейка, Esc - отмена")
	else:
		_look_enabled = true
		GameManager.set_prompt("")

func get_camera() -> Camera3D:
	return camera

func get_flashlight():
	return flashlight

func _update_footsteps() -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.4 and is_on_floor() and not is_hidden:
		var interval := 0.55
		if is_running:
			interval = 0.32
		elif is_crouching:
			interval = 0.75
		footstep_timer.wait_time = interval
		if footstep_timer.is_stopped():
			_on_footstep()
			footstep_timer.start()
	else:
		if not footstep_timer.is_stopped():
			footstep_timer.stop()

func _on_footstep() -> void:
	if is_hidden:
		return
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if horiz_speed < 0.4 or not is_on_floor():
		return
	var sfx := "footstep_run" if is_running else "footstep"
	var vol := -10.0 if is_crouching else (-4.0 if is_running else -7.0)
	AudioSynth.play_3d(sfx, global_position, vol, randf_range(0.9, 1.1), self)
	# Camera shake on heavy run
	if is_running:
		camera.position.y -= 0.01

func on_monster_nearby(strength: float) -> void:
	# Called by monster; add subtle camera shake
	if is_hidden:
		return
	camera.rotation.z = lerpf(camera.rotation.z, randf_range(-0.003, 0.003) * strength, 0.5)
