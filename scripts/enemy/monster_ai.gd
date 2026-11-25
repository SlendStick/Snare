extends CharacterBody3D

enum State { PATROL, INVESTIGATE, CHASE, SEARCH, CHECK_LOCKER, KILL }

@export var patrol_speed: float = 2.2
@export var investigate_speed: float = 2.8
@export var chase_speed: float = 4.8
@export var search_speed: float = 2.6
@export var sight_range: float = 16.0
@export var sight_angle_deg: float = 70.0
@export var hearing_range: float = 18.0

var state: int = State.PATROL
var maze_generator: RuntimeMazeGenerator = null
var target: Node3D = null

@onready var body_root: Node3D = $BodyRoot
@onready var sight_ray: RayCast3D = $BodyRoot/SightRay
@onready var kill_area: Area3D = $KillArea
@onready var breath_player: AudioStreamPlayer3D = $BreathPlayer

var _path: PackedVector3Array = PackedVector3Array()
var _path_idx: int = 0
var _path_timer: float = 0.0
var _state_timer: float = 0.0
var _last_known_player_pos: Vector3 = Vector3.ZERO
var _investigate_pos: Vector3 = Vector3.ZERO
var _search_points: Array[Vector3] = []
var _search_idx: int = 0
var _target_locker: Node = null
var _saw_player_enter_locker: bool = false
var _kill_cooldown: float = 0.0

# Animation
var _anim_t: float = 0.0
var _step_timer: float = 0.0
var _roar_cooldown: float = 0.0

# Body parts
var _head: Node3D
var _jaw: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D

var _locker_check_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("monster")
	_rng.randomize()
	_build_body()
	_setup_audio()
	kill_area.body_entered.connect(_on_kill_area_body_entered)
	GameManager.register_monster(self)
	_enter_state(State.PATROL)

func set_maze_generator(m: Node) -> void:
	if m is RuntimeMazeGenerator:
		maze_generator = m

func set_target(t: Node3D) -> void:
	target = t

func _setup_audio() -> void:
	var s := AudioSynth.get_sfx("monster_breath")
	breath_player.stream = s
	breath_player.volume_db = -6.0
	breath_player.max_distance = 35.0
	breath_player.unit_size = 6.0
	breath_player.autoplay = true
	breath_player.play()

func _build_body() -> void:
	# Procedural monster: tall, hunched, elongated limbs, dark organic material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.055, 0.06)
	mat.roughness = 0.95
	mat.metallic = 0.05
	var noise := FastNoiseLite.new()
	noise.seed = 666
	noise.frequency = 0.15
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	mat.albedo_texture = tex
	var ntex := NoiseTexture2D.new()
	ntex.width = 256
	ntex.height = 256
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 6.0
	var nnoise := FastNoiseLite.new()
	nnoise.seed = 667
	nnoise.frequency = 0.18
	nnoise.fractal_octaves = 5
	ntex.noise = nnoise
	mat.normal_enabled = true
	mat.normal_texture = ntex
	mat.normal_scale = 1.2

	var dark_mat := mat.duplicate()
	dark_mat.albedo_color = Color(0.04, 0.035, 0.04)

	# Torso
	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.32
	torso_mesh.height = 1.1
	torso.mesh = torso_mesh
	torso.material_override = mat
	torso.position = Vector3(0, 1.75, 0)
	torso.rotation.x = deg_to_rad(18) # hunched
	body_root.add_child(torso)

	# Hips/lower torso
	var hips := MeshInstance3D.new()
	var hips_mesh := CapsuleMesh.new()
	hips_mesh.radius = 0.26
	hips_mesh.height = 0.7
	hips.mesh = hips_mesh
	hips.material_override = dark_mat
	hips.position = Vector3(0, 1.15, 0.05)
	body_root.add_child(hips)

	# Head
	_head = Node3D.new()
	_head.position = Vector3(0, 2.35, -0.15)
	body_root.add_child(_head)

	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.22
	skull_mesh.height = 0.48
	skull.mesh = skull_mesh
	skull.material_override = dark_mat
	skull.scale = Vector3(1.0, 0.9, 1.2)
	_head.add_child(skull)

	_jaw = Node3D.new()
	_jaw.position = Vector3(0, -0.08, -0.12)
	_head.add_child(_jaw)
	var jaw_mesh_i := MeshInstance3D.new()
	var jaw_mesh := BoxMesh.new()
	jaw_mesh.size = Vector3(0.22, 0.08, 0.25)
	jaw_mesh_i.mesh = jaw_mesh
	jaw_mesh_i.material_override = dark_mat
	jaw_mesh_i.position = Vector3(0, -0.03, -0.05)
	_jaw.add_child(jaw_mesh_i)

	# Eyes (emissive small spheres)
	for side in [-1, 1]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.025
		em.height = 0.05
		eye.mesh = em
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(0.9, 0.2, 0.15)
		emat.emission_enabled = true
		emat.emission = Color(1.0, 0.25, 0.15)
		emat.emission_energy_multiplier = 2.5
		eye.material_override = emat
		eye.position = Vector3(side * 0.07, 0.02, -0.22)
		_head.add_child(eye)

	# Shoulders / arms
	_left_arm = _make_limb(mat, Vector3(0.09, 0.09, 0.09), 1.15, Vector3(-0.38, 1.95, 0.0), -12.0)
	_right_arm = _make_limb(mat, Vector3(0.09, 0.09, 0.09), 1.15, Vector3(0.38, 1.95, 0.0), 12.0)

	# Legs
	_left_leg = _make_limb(dark_mat, Vector3(0.11, 0.11, 0.11), 1.1, Vector3(-0.14, 0.85, 0.0), 0.0)
	_right_leg = _make_limb(dark_mat, Vector3(0.11, 0.11, 0.11), 1.1, Vector3(0.14, 0.85, 0.0), 0.0)

	# Spine bumps
	for i in range(3):
		var bump := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.06
		bm.height = 0.12
		bump.mesh = bm
		bump.material_override = dark_mat
		bump.position = Vector3(0, 2.0 - i * 0.22, 0.18 + i * 0.04)
		body_root.add_child(bump)

func _make_limb(mat: Material, _scale: Vector3, length: float, pos: Vector3, z_rot_deg: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation.z = deg_to_rad(z_rot_deg)
	body_root.add_child(pivot)
	var mesh_i := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.07
	mesh.height = length
	mesh_i.mesh = mesh
	mesh_i.material_override = mat
	mesh_i.position = Vector3(0, -length * 0.45, 0)
	pivot.add_child(mesh_i)
	return pivot

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	if target == null:
		target = GameManager.player
	_state_timer += delta
	_path_timer -= delta
	_roar_cooldown -= delta
	_kill_cooldown -= delta
	_anim_t += delta

	_update_perception(delta)
	_update_state(delta)
	_update_movement(delta)
	_update_animation(delta)
	_update_audio_proximity(delta)
	move_and_slide()

func _update_perception(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var player_hidden: bool = target.has_method("get") and target.get("is_hidden")
	var can_see := _can_see_player()

	if can_see and not player_hidden:
		_last_known_player_pos = target.global_position
		if state != State.CHASE and state != State.KILL and state != State.CHECK_LOCKER:
			_enter_state(State.CHASE)
		_saw_player_enter_locker = false
	elif can_see and player_hidden:
		var locker = target.current_locker if target.get("current_locker") != null else null
		if locker:
			_target_locker = locker
			_saw_player_enter_locker = true
			_last_known_player_pos = locker.global_position
			if state == State.CHASE:
				_enter_state(State.CHECK_LOCKER)
	elif state == State.CHASE and player_hidden:
		# Player disappeared while we were chasing - maybe entered locker nearby
		var locker2 = target.get("current_locker")
		if locker2 and is_instance_valid(locker2):
			var d := global_position.distance_to(locker2.global_position)
			if d < 8.0 and _state_timer < 1.5:
				_target_locker = locker2
				_saw_player_enter_locker = true
				_last_known_player_pos = locker2.global_position
				_enter_state(State.CHECK_LOCKER)

	# Hearing: player noise
	if target.has_method("get_noise_level"):
		var noise: float = target.get_noise_level()
		var dist := global_position.distance_to(target.global_position)
		if noise > 0.5 and dist < hearing_range * noise and state in [State.PATROL, State.SEARCH]:
			_investigate_pos = target.global_position
			_enter_state(State.INVESTIGATE)

	# Flashlight light attraction
	if target.has_method("is_flashlight_on") and target.is_flashlight_on() and not player_hidden:
		var dist := global_position.distance_to(target.global_position)
		if dist < 14.0 and state in [State.PATROL, State.SEARCH]:
			_investigate_pos = target.global_position
			_enter_state(State.INVESTIGATE)

	# Light leaking from locker attracts monster
	_locker_check_timer -= delta
	if _locker_check_timer <= 0.0:
		_locker_check_timer = 1.5
		if state in [State.PATROL, State.SEARCH, State.INVESTIGATE]:
			for locker in get_tree().get_nodes_in_group("locker"):
				if locker.has_method("has_light_leak") and locker.has_light_leak():
					var d := global_position.distance_to(locker.global_position)
					if d < 12.0:
						_investigate_pos = locker.global_position
						_last_known_player_pos = locker.global_position
						if state != State.INVESTIGATE:
							_enter_state(State.INVESTIGATE)
						break

func _can_see_player() -> bool:
	if target == null:
		return false
	var to_player := target.global_position + Vector3(0, 1.2, 0) - (global_position + Vector3(0, 2.0, 0))
	var dist := to_player.length()
	if dist > sight_range:
		return false
	var forward := -global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to(to_player.normalized()))
	if angle > sight_angle_deg:
		# Very close can still be detected
		if dist > 3.0:
			return false
	sight_ray.target_position = sight_ray.to_local(target.global_position + Vector3(0, 1.2, 0))
	sight_ray.force_raycast_update()
	if sight_ray.is_colliding():
		var col = sight_ray.get_collider()
		if col == target:
			return true
		# Check parent chain
		var c: Node = col
		for _i in range(3):
			if c == target:
				return true
			c = c.get_parent()
		return false
	return false

func _enter_state(new_state: int) -> void:
	if state == new_state:
		return
	var prev := state
	state = new_state
	_state_timer = 0.0
	_path = PackedVector3Array()
	_path_idx = 0
	_path_timer = 0.0

	match state:
		State.PATROL:
			_pick_patrol_target()
		State.INVESTIGATE:
			_set_path_to(_investigate_pos)
		State.CHASE:
			if _roar_cooldown <= 0.0:
				AudioSynth.play_3d("monster_roar", global_position, -2.0, randf_range(0.95, 1.05), self)
				_roar_cooldown = 6.0
			_set_path_to(target.global_position if target else global_position)
		State.SEARCH:
			_build_search_points(_last_known_player_pos)
		State.CHECK_LOCKER:
			if _target_locker and is_instance_valid(_target_locker):
				_set_path_to(_target_locker.global_position)
		State.KILL:
			velocity = Vector3.ZERO

func _update_state(delta: float) -> void:
	match state:
		State.PATROL:
			if _path_idx >= _path.size():
				if _state_timer > 1.0:
					_pick_patrol_target()
			if _state_timer > 12.0:
				_pick_patrol_target()
		State.INVESTIGATE:
			if global_position.distance_to(_investigate_pos) < 1.5 or _state_timer > 10.0:
				_enter_state(State.SEARCH)
				_last_known_player_pos = _investigate_pos
				_build_search_points(_investigate_pos)
		State.CHASE:
			_path_timer -= delta
			if _path_timer <= 0.0:
				if target:
					_set_path_to(target.global_position)
				_path_timer = 0.5
			# If can't see player for a while, go search
			if not _can_see_player():
				if _state_timer > 3.5:
					_enter_state(State.SEARCH)
			else:
				_state_timer = 0.0 # reset while seeing
				_last_known_player_pos = target.global_position
			# Catch player if close
			if target and not target.get("is_hidden"):
				if global_position.distance_to(target.global_position) < 1.4:
					_enter_state(State.KILL)
		State.SEARCH:
			if _path_idx >= _path.size():
				_search_idx += 1
				if _search_idx < _search_points.size():
					_set_path_to(_search_points[_search_idx])
				else:
					_enter_state(State.PATROL)
			if _state_timer > 15.0:
				_enter_state(State.PATROL)
		State.CHECK_LOCKER:
			if _target_locker == null or not is_instance_valid(_target_locker):
				_enter_state(State.SEARCH)
				return
			_path_timer -= delta
			if _path_timer <= 0.0:
				_set_path_to(_target_locker.global_position)
				_path_timer = 0.8
			var dist := global_position.distance_to(_target_locker.global_position)
			if dist < 1.8:
				# Check locker
				if _saw_player_enter_locker or (_target_locker.has_method("is_occupied") and _target_locker.is_occupied()):
					if _target_locker.has_method("is_occupied") and _target_locker.is_occupied():
						_kill_in_locker(_target_locker)
					else:
						_enter_state(State.SEARCH)
				else:
					# Didn't see them enter; pass by / search around
					_enter_state(State.SEARCH)
			if _state_timer > 12.0:
				_enter_state(State.PATROL)
		State.KILL:
			if _state_timer > 0.1:
				_do_kill()

func _update_movement(delta: float) -> void:
	if state == State.KILL:
		velocity.x = move_toward(velocity.x, 0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 10.0 * delta)
		if not is_on_floor():
			velocity.y -= 18.0 * delta
		return

	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.1

	if _path_idx >= _path.size():
		velocity.x = move_toward(velocity.x, 0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 5.0 * delta)
		return

	var target_pos := _path[_path_idx]
	target_pos.y = global_position.y
	var to_target := target_pos - global_position
	to_target.y = 0
	if to_target.length() < 0.5:
		_path_idx += 1
		return

	var dir := to_target.normalized()
	var speed := patrol_speed
	match state:
		State.INVESTIGATE:
			speed = investigate_speed
		State.CHASE:
			speed = chase_speed
		State.SEARCH:
			speed = search_speed
		State.CHECK_LOCKER:
			speed = investigate_speed

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	# Rotate to face movement
	var desired_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, 4.0 * delta)

func _update_animation(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.2
	var speed_factor := 1.0
	if state == State.CHASE:
		speed_factor = 1.8
	elif state == State.PATROL:
		speed_factor = 0.8

	if moving:
		var t := _anim_t * 5.0 * speed_factor
		if _left_leg:
			_left_leg.rotation.x = sin(t) * 0.45
		if _right_leg:
			_right_leg.rotation.x = sin(t + PI) * 0.45
		if _left_arm:
			_left_arm.rotation.x = sin(t + PI) * 0.35
		if _right_arm:
			_right_arm.rotation.x = sin(t) * 0.35
		if _head:
			_head.rotation.y = sin(_anim_t * 1.2) * 0.08
			_head.position.y = 2.35 + sin(t * 2.0) * 0.02
		if _jaw:
			_jaw.rotation.x = 0.1 + absf(sin(_anim_t * 2.5)) * 0.08
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.55 / speed_factor
			AudioSynth.play_3d("monster_step", global_position, -8.0, randf_range(0.85, 1.1), self)
			# Camera shake if close
			if target and global_position.distance_to(target.global_position) < 10.0:
				if target.has_method("on_monster_nearby"):
					target.on_monster_nearby(clampf(1.0 - global_position.distance_to(target.global_position) / 10.0, 0.0, 1.0))
	else:
		if _left_leg: _left_leg.rotation.x = lerpf(_left_leg.rotation.x, 0, 5*delta)
		if _right_leg: _right_leg.rotation.x = lerpf(_right_leg.rotation.x, 0, 5*delta)
		if _left_arm: _left_arm.rotation.x = lerpf(_left_arm.rotation.x, 0.15, 5*delta)
		if _right_arm: _right_arm.rotation.x = lerpf(_right_arm.rotation.x, 0.15, 5*delta)
		if _jaw: _jaw.rotation.x = 0.05 + absf(sin(_anim_t * 1.5)) * 0.04

func _update_audio_proximity(_delta: float) -> void:
	if target == null:
		return
	var dist := global_position.distance_to(target.global_position)
	if breath_player:
		breath_player.volume_db = lerpf(-14.0, -2.0, clampf(1.0 - dist / 25.0, 0.0, 1.0))
	# Fear level based on proximity
	var fear := clampf(1.0 - dist / 18.0, 0.0, 1.0)
	if state == State.CHASE:
		fear = maxf(fear, 0.7)
	GameManager.push_fear(fear * 0.8)

func _pick_patrol_target() -> void:
	if maze_generator == null or target == null:
		return
	# Director AI: bias toward player but not too close
	var player_pos := target.global_position
	var bias := _rng.randf()
	var goal: Vector3
	if bias < 0.45:
		# Move somewhat toward player
		goal = maze_generator.random_floor_cell_near(player_pos, 8.0, 20.0)
	else:
		goal = maze_generator.random_floor_cell_near(global_position, 8.0, 24.0)
	_investigate_pos = goal
	_set_path_to(goal)

func _build_search_points(center: Vector3) -> void:
	_search_points.clear()
	_search_idx = 0
	if maze_generator == null:
		_search_points.append(center)
		return
	for _i in range(3):
		_search_points.append(maze_generator.random_floor_cell_near(center, 2.0, 8.0))
	if _search_points.size() > 0:
		_set_path_to(_search_points[0])

func _set_path_to(dest: Vector3) -> void:
	if maze_generator == null:
		_path = PackedVector3Array([dest])
		_path_idx = 0
		return
	var p := maze_generator.get_astar_path(global_position, dest)
	if p.size() == 0:
		# Direct fallback
		_path = PackedVector3Array([dest])
	else:
		_path = p
	_path_idx = 0
	# Skip first point if it's very close
	if _path.size() > 1 and global_position.distance_to(_path[0]) < 0.5:
		_path_idx = 1

func on_noise_heard(pos: Vector3, intensity: float = 1.0) -> void:
	if state in [State.CHASE, State.KILL]:
		if intensity > 0.8:
			_last_known_player_pos = pos
		return
	var dist := global_position.distance_to(pos)
	if dist < hearing_range * intensity:
		_investigate_pos = pos
		_last_known_player_pos = pos
		_enter_state(State.INVESTIGATE)

func force_kill_at_locker(locker: Node) -> void:
	_target_locker = locker
	_saw_player_enter_locker = true
	global_position = locker.global_position + locker.global_transform.basis.z * 1.2
	global_position.y = 0.0
	_kill_in_locker(locker)

func _kill_in_locker(locker: Node) -> void:
	if state == State.KILL:
		return
	state = State.KILL
	_state_timer = 0.0
	velocity = Vector3.ZERO
	_path = PackedVector3Array()
	# Face locker
	var to_locker := locker.global_position - global_position
	to_locker.y = 0
	if to_locker.length() > 0.01:
		rotation.y = atan2(-to_locker.normalized().x, -to_locker.normalized().z)
	if locker.has_method("force_open_for_kill"):
		locker.force_open_for_kill()
	AudioSynth.play_3d("monster_roar", global_position, 0.0, 0.9, self)
	AudioSynth.play_2d("scare_sting", -1.0, 1.0, self)
	await get_tree().create_timer(0.6).timeout
	GameManager.trigger_game_over("Монстр вырвал дверь шкафа")

func _do_kill() -> void:
	if GameManager.is_game_over:
		return
	AudioSynth.play_2d("scare_sting", 0.0, 1.0, self)
	GameManager.trigger_game_over("Монстр настиг вас")

func _on_kill_area_body_entered(body: Node) -> void:
	if body == target and state != State.KILL:
		if body.get("is_hidden"):
			return
		_enter_state(State.KILL)
