extends Node3D

@export var danger_radius: float = 10.0
@export var safe_radius: float = 14.0

var occupant: Node = null
var _door_open_angle: float = -95.0
var _door_closed_angle: float = 0.0
var _door_target: float = 0.0
var _is_open: bool = false
var _panic_active: bool = false
var _monster_was_near: bool = false

@onready var door_pivot: Node3D = $DoorPivot
@onready var door_mesh: MeshInstance3D = $DoorPivot/DoorMesh
@onready var hide_cam_pos: Marker3D = $HideCameraPos
@onready var exit_pos: Marker3D = $ExitPos
@onready var interact_area: Area3D = $InteractArea

var _breathing_ui: Control = null
var _breathing_layer: CanvasLayer = null
var _heartbeat_player: AudioStreamPlayer = null
var _breath_player: AudioStreamPlayer = null
var _look_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("locker")
	_build_visuals()
	_setup_breathing_ui()
	_door_target = _door_closed_angle
	door_pivot.rotation.y = deg_to_rad(_door_closed_angle)

func _build_visuals() -> void:
	# Body box
	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(1.1, 2.4, 0.9)
	body.mesh = body_box
	body.position = Vector3(0, 1.2, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.18)
	mat.metallic = 0.6
	mat.roughness = 0.55
	var noise := FastNoiseLite.new()
	noise.seed = 1234
	noise.frequency = 0.2
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.noise = noise
	mat.albedo_texture = tex
	body.material_override = mat
	add_child(body)

	# Door material
	var door_mat := mat.duplicate()
	door_mat.albedo_color = Color(0.14, 0.15, 0.16)
	door_mesh.material_override = door_mat

	# Slits on door
	for i in range(4):
		var slit := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.55, 0.03, 0.02)
		slit.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.02, 0.02, 0.02)
		smat.emission_enabled = true
		smat.emission = Color(0.01, 0.01, 0.01)
		slit.material_override = smat
		slit.position = Vector3(0.0, 0.35 - i * 0.22, 0.03)
		door_mesh.add_child(slit)

func _setup_breathing_ui() -> void:
	_breathing_layer = CanvasLayer.new()
	_breathing_layer.layer = 5
	add_child(_breathing_layer)
	if ResourceLoader.exists("res://scenes/ui/breathing_minigame.tscn"):
		var scene = load("res://scenes/ui/breathing_minigame.tscn")
		_breathing_ui = scene.instantiate()
		_breathing_layer.add_child(_breathing_ui)
		_breathing_ui.success.connect(_on_breath_success)
		_breathing_ui.failure.connect(_on_breath_failure)
		_breathing_ui.panic_maxed.connect(_on_panic_maxed)
	else:
		# Fallback simple control
		_breathing_ui = Control.new()
		_breathing_ui.visible = false
		_breathing_layer.add_child(_breathing_ui)

func _process(delta: float) -> void:
	# Door animation
	var target_rad := deg_to_rad(_door_target)
	door_pivot.rotation.y = lerp_angle(door_pivot.rotation.y, target_rad, 5.0 * delta)

	if occupant == null:
		return
	if not is_instance_valid(occupant):
		occupant = null
		return

	# Keep player camera inside locker
	_update_occupant_camera(delta)
	_update_panic_state(delta)

func _update_occupant_camera(delta: float) -> void:
	if occupant == null or not occupant.has_method("get_camera"):
		return
	var cam: Camera3D = occupant.get_camera()
	# Gently lock camera to hide position looking out through slits
	var target_pos := hide_cam_pos.global_position
	cam.global_position = cam.global_position.lerp(target_pos, 10.0 * delta)
	# Look out through door slits (door side is +Z local)
	var forward := global_transform.basis.z
	var look_target := hide_cam_pos.global_position + forward * 2.0
	look_target += global_transform.basis.x * _look_offset.x * 0.3
	look_target.y += _look_offset.y * 0.2
	var desired := cam.global_transform.looking_at(look_target, Vector3.UP)
	cam.global_transform.basis = cam.global_transform.basis.slerp(desired.basis, 5.0 * delta)

func _update_panic_state(delta: float) -> void:
	var monster = GameManager.monster
	if monster == null or not is_instance_valid(monster):
		_stop_panic()
		return
	var dist := global_position.distance_to(monster.global_position)
	var monster_near := dist < danger_radius
	var monster_very_close := dist < danger_radius * 0.7

	if monster_near and not _panic_active:
		_start_panic()
	elif not monster_near and _panic_active and dist > safe_radius:
		# Monster passed
		if _breathing_ui and _breathing_ui.has_method("get_calm") and _breathing_ui.get_calm() > 0.6:
			_stop_panic(true)
		elif dist > safe_radius + 2.0:
			_stop_panic(true)

	if _panic_active:
		GameManager.push_fear(clampf(1.0 - (_breathing_ui.get_calm() if _breathing_ui else 0.5), 0.3, 1.0))
		if _heartbeat_player:
			_heartbeat_player.volume_db = lerpf(_heartbeat_player.volume_db, -8.0 + (1.0 - (_breathing_ui.get_calm() if _breathing_ui else 0.5)) * 6.0, 2.0 * delta)
			_heartbeat_player.pitch_scale = lerpf(_heartbeat_player.pitch_scale, 1.0 + (1.0 - (_breathing_ui.get_calm() if _breathing_ui else 0.5)) * 0.4, 2.0 * delta)
		# Camera shake
		if occupant and occupant.has_method("get_camera"):
			var cam: Camera3D = occupant.get_camera()
			var shake: float = (1.0 - (_breathing_ui.get_calm() if _breathing_ui else 0.5)) * 0.004
			cam.rotation.z = randf_range(-shake, shake)

func _start_panic() -> void:
	if _panic_active:
		return
	_panic_active = true
	_monster_was_near = true
	if _breathing_ui and _breathing_ui.has_method("start_minigame"):
		_breathing_ui.start_minigame()
	if _heartbeat_player == null:
		_heartbeat_player = AudioSynth.make_loop_player_2d("heartbeat", -10.0)
		add_child(_heartbeat_player)
	_heartbeat_player.play()
	if _breath_player == null:
		_breath_player = AudioSynth.make_loop_player_2d("breath_panic", -14.0)
		add_child(_breath_player)
	_breath_player.play()
	GameManager.set_fear(0.7)

func _stop_panic(calm: bool = false) -> void:
	if not _panic_active and _breathing_ui and not _breathing_ui.visible:
		GameManager.set_fear(0.0)
		return
	_panic_active = false
	if _breathing_ui and _breathing_ui.has_method("stop_minigame"):
		_breathing_ui.stop_minigame()
	if _heartbeat_player and _heartbeat_player.playing:
		_heartbeat_player.stop()
	if _breath_player and _breath_player.playing:
		_breath_player.stop()
	GameManager.set_fear(0.0)
	if calm:
		AudioSynth.play_2d("breath_calm", -16.0, 0.9, self)

func _on_breath_success() -> void:
	pass

func _on_breath_failure() -> void:
	# Loud gasp - monster can hear. Notify monster.
	var monster = GameManager.monster
	if monster and monster.has_method("on_noise_heard"):
		monster.on_noise_heard(global_position, 1.5)
	# Camera jolt
	if occupant and occupant.has_method("get_camera"):
		var cam: Camera3D = occupant.get_camera()
		cam.rotation.x += randf_range(-0.03, 0.03)

func _on_panic_maxed() -> void:
	# Monster rips door open and kills
	_stop_panic(false)
	var monster = GameManager.monster
	if monster and monster.has_method("force_kill_at_locker"):
		monster.force_kill_at_locker(self)
	else:
		_force_kill()

func _force_kill() -> void:
	_door_target = _door_open_angle
	AudioSynth.play_3d("locker_slam", global_position, -2.0, 0.8, self)
	AudioSynth.play_2d("scare_sting", -2.0, 1.0, self)
	GameManager.trigger_game_over("Монстр нашёл вас в шкафу")

func get_interact_prompt() -> String:
	if occupant != null:
		return "[E] Выйти из шкафа"
	return "[E] Спрятаться в шкафу"

func interact(player: Node) -> void:
	if occupant == null:
		enter_locker(player)
	else:
		exit_locker(player)

func enter_locker(player: Node) -> void:
	if occupant != null:
		return
	occupant = player
	_look_offset = Vector2.ZERO
	_door_target = _door_closed_angle
	AudioSynth.play_3d("locker_close", global_position, -6.0, 1.0, self)
	if player.has_method("enter_hiding"):
		player.enter_hiding(self)
	# Disable interact area so ray doesn't keep hitting weirdly? keep it
	GameManager.set_prompt("[E] Выйти из шкафа")

func exit_locker(player: Node) -> void:
	if occupant != player:
		return
	_stop_panic(true)
	_door_target = _door_open_angle
	AudioSynth.play_3d("locker_open", global_position, -6.0, 1.0, self)
	if player.has_method("exit_hiding"):
		player.exit_hiding(self)
	# Move player to exit position
	player.global_position = exit_pos.global_position
	player.velocity = Vector3.ZERO
	occupant = null
	# Close door after a moment
	await get_tree().create_timer(0.8).timeout
	if occupant == null:
		_door_target = _door_closed_angle
		AudioSynth.play_3d("locker_close", global_position, -10.0, 1.0, self)

func on_mouse_motion(rel: Vector2) -> void:
	_look_offset.x = clampf(_look_offset.x - rel.x * 0.001, -1.0, 1.0)
	_look_offset.y = clampf(_look_offset.y - rel.y * 0.001, -0.6, 0.6)
	_look_offset = _look_offset.lerp(Vector2.ZERO, 0.02)

func is_occupied() -> bool:
	return occupant != null

func has_light_leak() -> bool:
	if occupant == null:
		return false
	if occupant.has_method("is_flashlight_on"):
		return occupant.is_flashlight_on()
	return false

func get_occupant() -> Node:
	return occupant

func force_open_for_kill() -> void:
	_door_target = _door_open_angle
	AudioSynth.play_3d("locker_slam", global_position, -2.0, 0.7, self)
