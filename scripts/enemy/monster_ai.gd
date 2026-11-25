class_name MonsterAI
extends CharacterBody3D
## Конечный автомат монстра: PATROL → INVESTIGATE → CHASE → SEARCH → CHECK_LOCKER → KILL.

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var state: String = "PATROL"
var target: Vector3 = Vector3.ZERO
var last_seen: Vector3 = Vector3.ZERO
var known_locker = null
var path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
var player_visible: bool = false
var _move_speed: float = 2.0

var _maze = null
var _player = null
var _repath_timer: float = 0.0
var _state_timer: float = 2.0
var _lost_sight: float = 0.0
var _step_timer: float = 0.0
var _anim_time: float = 0.0
var _kill_committed: bool = false
var _vision_ray: RayCast3D = null
var _growl: AudioStreamPlayer3D = null
var _torso: Node3D = null
var _head: Node3D = null
var _jaw: Node3D = null
var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _leg_l: Node3D = null
var _leg_r: Node3D = null
var _eyes: Array[MeshInstance3D] = []


func _ready() -> void:
	GameManager.monster = self
	collision_layer = 4
	collision_mask = 1
	_maze = GameManager.maze
	_player = GameManager.player
	_build_body()

	_vision_ray = RayCast3D.new()
	_vision_ray.collision_mask = 5
	_vision_ray.collide_with_areas = false
	_vision_ray.add_exception_rid(get_rid())
	add_child(_vision_ray)

	_growl = AudioSynth.make_loop_player_3d("growl_loop", -8.0, 38.0)
	add_child(_growl)
	_growl.play()

	var pc: Vector2i = RuntimeMazeGenerator.world_to_cell(global_position)
	var cell: Vector2i = _maze.random_visited_cell(pc, 5, 12)
	target = RuntimeMazeGenerator.cell_center(cell)
	_set_target(target)


func spawn_away_from(player_pos: Vector3) -> void:
	var pc: Vector2i = RuntimeMazeGenerator.world_to_cell(player_pos)
	var cell: Vector2i = _maze.random_visited_cell(pc, 6, 13)
	global_position = RuntimeMazeGenerator.cell_center(cell, 0.0)
	target = global_position
	path = PackedVector3Array()
	path_index = 0
	_repath_timer = 0.0
	var next_cell: Vector2i = _maze.random_visited_cell(cell, 3, 8)
	_set_target(RuntimeMazeGenerator.cell_center(next_cell))


func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or not _player:
		return
	_anim_time += delta
	_repath_timer -= delta
	_state_timer -= delta
	_update_vision(delta)
	_run_state()
	_move(delta)
	_animate(delta)
	_update_audio(delta)


func _update_vision(delta: float) -> void:
	if not is_instance_valid(_player) or _player.hidden:
		player_visible = false
		_lost_sight += delta
		return
	var to_player: Vector3 = (
		_player.global_position
		+ Vector3(0.0, 1.3, 0.0)
		- (global_position + Vector3(0.0, 2.25, 0.0))
	)
	var dist: float = to_player.length()
	var forward: Vector3 = -global_transform.basis.z
	var in_cone: bool = dist < 19.0 and forward.dot(to_player.normalized()) > 0.57
	if not in_cone:
		player_visible = false
		_lost_sight += delta
		return
	_vision_ray.global_position = global_position + Vector3(0.0, 2.25, 0.0)
	_vision_ray.look_at(_player.global_position + Vector3(0.0, 1.3, 0.0), Vector3.UP)
	_vision_ray.target_position = Vector3(0.0, 0.0, -dist)
	_vision_ray.force_raycast_update()
	var hit: Object = _vision_ray.get_collider()
	player_visible = hit == _player
	if player_visible:
		_lost_sight = 0.0
		last_seen = _player.global_position
	else:
		_lost_sight += delta


func _run_state() -> void:
	var speed: float = 2.0
	match state:
		"PATROL":
			speed = 1.9
			if player_visible:
				_enter_chase()
				return
			if _state_timer <= 0.0 or path.is_empty():
				var pc: Vector2i = RuntimeMazeGenerator.world_to_cell(_player.global_position)
				var cell: Vector2i = _maze.random_visited_cell(pc, 5, 13)
				_set_target(RuntimeMazeGenerator.cell_center(cell))
				_state_timer = randf_range(8.0, 13.0)

		"INVESTIGATE":
			speed = 3.1
			if player_visible:
				_enter_chase()
				return
			if path.is_empty() or _state_timer <= 0.0:
				state = "SEARCH"
				_state_timer = 9.0

		"CHASE":
			speed = 5.35
			if player_visible:
				_set_target(_player.global_position)
				if (
					global_position.distance_to(_player.global_position) < 1.65
					and not _player.hidden
				):
					kill_player("Монстр догнал тебя.")
					return
			else:
				if _player.hidden and known_locker:
					state = "CHECK_LOCKER"
					_state_timer = 11.0
					_set_target(known_locker.global_position)
					return
				if _lost_sight > 2.4:
					state = "SEARCH"
					_state_timer = 10.0
					_set_target(last_seen)

		"SEARCH":
			speed = 2.7
			if player_visible:
				_enter_chase()
				return
			if known_locker and global_position.distance_to(known_locker.global_position) < 3.0:
				state = "CHECK_LOCKER"
				_state_timer = 10.0
			elif path.is_empty() or _state_timer <= 0.0:
				if randf() < 0.6:
					var around := RuntimeMazeGenerator.world_to_cell(last_seen)
					var cell: Vector2i = _maze.random_visited_cell(around, 1, 3)
					_set_target(
						(
							RuntimeMazeGenerator.cell_center(cell)
							+ Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
						)
					)
					_state_timer = randf_range(3.0, 5.0)
				else:
					state = "PATROL"
					_state_timer = 6.0

		"CHECK_LOCKER":
			speed = 2.9
			if not known_locker or not is_instance_valid(known_locker):
				state = "PATROL"
				return
			_set_target(known_locker.global_position)
			if global_position.distance_to(known_locker.global_position) < 2.3:
				velocity = Vector3.ZERO
				if _state_timer > 6.0:
					known_locker.knock()
					_state_timer = 6.0
				if not GameManager.breathing or not GameManager.breathing.active:
					if GameManager.breathing:
						GameManager.breathing.start(known_locker, self)
			if _state_timer <= 0.0:
				calm_down()

		"KILL":
			speed = 6.0
			_set_target(_player.global_position)

	_move_speed = speed


func _set_target(new_target: Vector3) -> void:
	if path.size() > 0 and _repath_timer > 0.0 and target.distance_to(new_target) < 1.8:
		return
	target = new_target
	_repath_timer = 0.65
	path = _maze.find_path(global_position, new_target)
	path_index = 0


func _move(delta: float) -> void:
	if (
		path.size() == 0
		and (state == "CHASE" or state == "KILL" or state == "CHECK_LOCKER")
		and target.distance_squared_to(global_position) > 0.36
	):
		# Цель в той же клетке: A* не даёт пути, но до цели всё равно нужно дойти.
		var direct: Vector3 = (
			Vector3(target.x - global_position.x, 0.0, target.z - global_position.z).normalized()
		)
		velocity.x = lerpf(velocity.x, direct.x * _move_speed, clampf(delta * 5.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, direct.z * _move_speed, clampf(delta * 5.0, 0.0, 1.0))
	elif path.size() == 0:
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	else:
		var wp: Vector3 = path[path_index]
		var to: Vector3 = Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
		if to.length() < 0.65:
			path_index += 1
			if path_index >= path.size():
				path = PackedVector3Array()
				path_index = 0
				return
			wp = path[path_index]
			to = Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
		if to.length() > 0.01:
			var desired: Vector3 = to.normalized() * _move_speed
			velocity.x = lerpf(velocity.x, desired.x, clampf(delta * 4.5, 0.0, 1.0))
			velocity.z = lerpf(velocity.z, desired.z, clampf(delta * 4.5, 0.0, 1.0))
			var face_angle: float = atan2(-velocity.x, -velocity.z)
			rotation.y = lerpf(rotation.y, face_angle, clampf(delta * 3.0, 0.0, 1.0))

	velocity.y -= 12.0 * delta
	move_and_slide()


func _enter_chase() -> void:
	if state != "CHASE":
		AudioSynth.play_3d("roar", global_position + Vector3(0.0, 2.0, 0.0), 1.0)
		if _player:
			_player.add_tremor(0.8)
	if known_locker and _player.hidden:
		state = "CHECK_LOCKER"
	else:
		state = "CHASE"
	_state_timer = 14.0
	_set_target(_player.global_position)


func hear_noise(origin: Vector3, intensity: float, _kind: String) -> void:
	if state == "CHASE" or state == "KILL" or state == "CHECK_LOCKER":
		return
	var d: float = global_position.distance_to(origin)
	if d > 7.0 + 22.0 * intensity:
		return
	state = "INVESTIGATE"
	_state_timer = randf_range(7.0, 11.0)
	last_seen = origin
	_set_target(origin)


func notice_light(_origin: Vector3, intensity: float) -> void:
	if state == "CHASE" or state == "KILL" or state == "CHECK_LOCKER":
		return
	if randf() > intensity:
		return
	state = "INVESTIGATE"
	_state_timer = 8.0
	_set_target(_player.global_position if _player else global_position)


func player_entered_locker(locker) -> void:
	known_locker = locker
	last_seen = locker.global_position
	if player_visible or global_position.distance_to(locker.global_position) < 4.0:
		state = "CHECK_LOCKER"
		_state_timer = 11.0
		_set_target(locker.global_position)


func player_left_locker() -> void:
	known_locker = null
	if state == "CHECK_LOCKER" or state == "SEARCH":
		state = "CHASE"
		_state_timer = 10.0
		_set_target(_player.global_position)


func on_breathing_success() -> void:
	if state != "CHECK_LOCKER":
		return
	calm_down()
	GameManager.message("Монстр пронюхал вокруг и ушёл.", 3.0)


func on_breathing_failure() -> void:
	if state == "KILL":
		return
	kill_player("Паника выдала тебя: монстр сорвал дверцу.")


func calm_down() -> void:
	state = "PATROL"
	known_locker = null
	_state_timer = randf_range(7.0, 11.0)
	path = PackedVector3Array()
	if GameManager.breathing:
		GameManager.breathing.stop()


func kill_player(cause: String) -> void:
	if _kill_committed:
		return
	_kill_committed = true
	state = "KILL"
	AudioSynth.play_3d("roar", global_position + Vector3(0.0, 2.0, 0.0), 3.0)
	AudioSynth.play_3d("scream", _player.global_position, 2.0)
	if known_locker and is_instance_valid(known_locker):
		known_locker.break_open()
	if _player:
		_player.add_tremor(1.5)
	await get_tree().create_timer(0.55).timeout
	if _player:
		_player.die(cause)


func _update_audio(delta: float) -> void:
	var speed2: float = velocity.x * velocity.x + velocity.z * velocity.z
	_step_timer -= delta
	if speed2 > 1.0 and _step_timer <= 0.0:
		_step_timer = 0.56 if state != "CHASE" else 0.38
		AudioSynth.play_3d("monster_step", global_position, -3.0)
		var d: float = global_position.distance_to(_player.global_position)
		if d < 14.0:
			_player.add_tremor(clampf(1.0 - d / 14.0, 0.0, 1.0) * 0.14)
	if _growl:
		_growl.volume_db = -3.0 if state == "CHASE" else (-8.0 if state == "SEARCH" else -11.0)


func _animate(delta: float) -> void:
	var walking: float = clampf(
		sqrt(velocity.x * velocity.x + velocity.z * velocity.z) / 4.0, 0.0, 1.0
	)
	var stride: float = _anim_time * (7.5 if state == "CHASE" else 5.5)
	if _leg_l:
		_leg_l.rotation.x = sin(stride) * 0.55 * walking
		_leg_r.rotation.x = -sin(stride) * 0.55 * walking
	if _arm_l:
		_arm_l.rotation.x = -sin(stride) * 0.62 * walking + 0.12
		_arm_r.rotation.x = sin(stride) * 0.62 * walking + 0.12
	if _torso:
		_torso.rotation.z = sin(_anim_time * 2.7) * 0.045
		_torso.rotation.x = 0.16 + sin(stride * 0.5) * 0.03 * walking
	if _head:
		_head.rotation.x = sin(_anim_time * 1.9) * 0.11 - (0.12 if state == "CHASE" else 0.0)
		_head.rotation.z = sin(_anim_time * 1.3) * 0.08
	if _jaw:
		var open_target: float = 0.55 if state == "CHASE" or state == "KILL" else 0.12
		_jaw.rotation.x = lerpf(
			_jaw.rotation.x,
			open_target + sin(_anim_time * 6.0) * 0.05,
			clampf(delta * 5.0, 0.0, 1.0)
		)
	for eye in _eyes:
		if is_instance_valid(eye):
			var mat: StandardMaterial3D = eye.material_override as StandardMaterial3D
			if mat:
				mat.emission_energy_multiplier = 0.7 + 0.6 * absf(sin(_anim_time * 2.3))


func _build_body() -> void:
	var visual := Node3D.new()
	add_child(visual)
	var flesh: Material = ProcMaterials.flesh()
	var dark: Material = ProcMaterials.dark()

	_add_box(visual, Vector3(0.0, 1.05, 0.0), Vector3(0.78, 0.62, 0.5), flesh)
	_torso = Node3D.new()
	_torso.position = Vector3(0.0, 1.22, 0.0)
	_torso.rotation.x = 0.16
	visual.add_child(_torso)
	_add_box(_torso, Vector3(0.0, 0.72, -0.06), Vector3(1.02, 1.45, 0.62), flesh)
	_add_box(_torso, Vector3(0.0, 1.28, -0.18), Vector3(1.18, 0.4, 0.7), flesh)

	# Крючковатые отростки на спине.
	for i in range(5):
		var spike := MeshInstance3D.new()
		var smesh := BoxMesh.new()
		smesh.size = Vector3(0.11, 0.34 - float(i) * 0.03, 0.16)
		spike.mesh = smesh
		spike.material_override = dark
		spike.position = Vector3(0.0, 0.45 + float(i) * 0.26, 0.34)
		spike.rotation.x = -0.5
		_torso.add_child(spike)

	_head = Node3D.new()
	_head.position = Vector3(0.0, 1.58, -0.24)
	_torso.add_child(_head)
	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.29
	skull_mesh.height = 0.52
	skull.mesh = skull_mesh
	skull.material_override = flesh
	skull.scale = Vector3(1.0, 1.25, 0.85)
	_head.add_child(skull)

	_jaw = Node3D.new()
	_jaw.position = Vector3(0.0, -0.19, -0.13)
	_head.add_child(_jaw)
	_add_box(_jaw, Vector3(0.0, -0.09, -0.13), Vector3(0.38, 0.14, 0.42), dark)
	for i in range(6):
		var tooth := MeshInstance3D.new()
		var tmesh := BoxMesh.new()
		tmesh.size = Vector3(0.035, 0.09, 0.035)
		tooth.mesh = tmesh
		tooth.material_override = ProcMaterials.emissive(Color(0.35, 0.31, 0.24), 0.15)
		tooth.position = Vector3(-0.15 + float(i) * 0.06, -0.01, -0.30)
		_jaw.add_child(tooth)

	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var emesh := SphereMesh.new()
		emesh.radius = 0.042
		emesh.height = 0.06
		eye.mesh = emesh
		eye.material_override = ProcMaterials.emissive(Color(0.85, 0.18, 0.06), 0.9).duplicate()
		eye.position = Vector3(side * 0.14, 0.06, -0.25)
		_head.add_child(eye)
		_eyes.append(eye)

	_arm_l = _make_arm(_torso, -0.62)
	_arm_r = _make_arm(_torso, 0.62)
	_leg_l = _make_leg(visual, -0.30)
	_leg_r = _make_leg(visual, 0.30)


func _make_arm(parent: Node3D, x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 1.28, 0.0)
	parent.add_child(pivot)
	_add_limb(pivot, Vector3(0.0, -0.52, 0.0), 0.11, 1.1, ProcMaterials.flesh())
	var elbow := Node3D.new()
	elbow.position = Vector3(0.0, -1.04, 0.0)
	pivot.add_child(elbow)
	_add_limb(elbow, Vector3(0.0, -0.56, -0.05), 0.075, 1.25, ProcMaterials.flesh())
	for i in range(3):
		var claw := MeshInstance3D.new()
		var cmesh := CylinderMesh.new()
		cmesh.top_radius = 0.035
		cmesh.bottom_radius = 0.0
		cmesh.height = 0.28
		claw.mesh = cmesh
		claw.material_override = ProcMaterials.dark()
		claw.position = Vector3(-0.07 + float(i) * 0.07, -1.22, -0.08)
		claw.rotation.x = PI
		elbow.add_child(claw)
	return pivot


func _make_leg(parent: Node3D, x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 1.05, 0.0)
	parent.add_child(pivot)
	_add_limb(pivot, Vector3(0.0, -0.55, 0.0), 0.14, 1.12, ProcMaterials.flesh())
	_add_box(pivot, Vector3(0.0, -1.09, -0.15), Vector3(0.24, 0.12, 0.48), ProcMaterials.dark())
	return pivot


func _add_limb(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.85
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
