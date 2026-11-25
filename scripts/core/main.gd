extends Node3D

@onready var maze: RuntimeMazeGenerator = $MazeGenerator
@onready var player: CharacterBody3D = $Player
@onready var monster: Node3D = $Monster
@onready var hud: CanvasLayer = $HUD
@onready var post_rect: ColorRect = $PostProcess/ColorRect

var _ambience_player: AudioStreamPlayer = null

func _ready() -> void:
	GameManager.new_run()
	_setup_environment()
	_wire_refs()
	_spawn_player()
	_start_ambience()
	GameManager.game_restarted.connect(_on_game_restarted)

func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.04, 0.045, 0.06)
	env.ambient_light_energy = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.025, 0.03)
	env.fog_light_energy = 0.2
	env.fog_density = 0.045
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = false # GL Compatibility friendly; density fog gives similar feel
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.08
	env_node.environment = env
	add_child(env_node)

func _wire_refs() -> void:
	GameManager.register_player(player)
	GameManager.register_monster(monster)
	GameManager.register_maze(maze)
	maze.set_player(player)
	if player.has_method("set_maze_generator"):
		player.set_maze_generator(maze)
	if monster.has_method("set_maze_generator"):
		monster.set_maze_generator(maze)
	if monster.has_method("set_target"):
		monster.set_target(player)
	if hud.has_method("set_player"):
		hud.set_player(player)

func _spawn_player() -> void:
	var spawn := maze.get_spawn_position()
	player.global_position = spawn + Vector3(0, 0.2, 0)
	# Place monster far away
	var monster_pos := maze.random_floor_cell_near(spawn, 24.0, 40.0)
	monster.global_position = monster_pos + Vector3(0, 0.1, 0)

func _start_ambience() -> void:
	_ambience_player = AudioSynth.make_loop_player_2d("ambience", -14.0)
	add_child(_ambience_player)
	_ambience_player.play()

func _process(_delta: float) -> void:
	# Drive postprocess shader
	if post_rect and post_rect.material is ShaderMaterial:
		var mat: ShaderMaterial = post_rect.material
		mat.set_shader_parameter("fear", GameManager.fear_level)
		var pulse := 0.0
		if GameManager.fear_level > 0.3:
			pulse = (sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5) * GameManager.fear_level
		mat.set_shader_parameter("pulse", pulse)

func _on_game_restarted() -> void:
	pass
