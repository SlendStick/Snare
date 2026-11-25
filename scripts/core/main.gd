extends Node3D
## Точка сборки: окружение, генератор, игрок, монстр и интерфейс.

const MAZE_SCENE: PackedScene = preload("res://scenes/world/maze_generator.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const MONSTER_SCENE: PackedScene = preload("res://scenes/enemy/monster.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")


func _ready() -> void:
	var ambient := AudioSynth.make_loop_player("ambient", -21.0)
	add_child(ambient)
	ambient.play()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.007, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_energy = 0.035
	env.fog_enabled = true
	env.fog_light_color = Color(0.012, 0.014, 0.018)
	env.fog_density = 0.055
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var weak_moon := DirectionalLight3D.new()
	weak_moon.light_energy = 0.016
	weak_moon.light_color = Color(0.45, 0.52, 0.68)
	weak_moon.rotation_degrees = Vector3(38.0, 24.0, 0.0)
	add_child(weak_moon)

	var maze = MAZE_SCENE.instantiate()
	add_child(maze)

	# Первое кольцо чанков строится до появления игрока и монстра.
	for x in range(-1, 2):
		for y in range(-1, 2):
			maze.ensure_chunk(Vector2i(x, y))

	var hud = HUD_SCENE.instantiate()
	add_child(hud)

	var player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = RuntimeMazeGenerator.cell_center(maze.spawn_cell, 0.04)

	var monster = MONSTER_SCENE.instantiate()
	add_child(monster)
	monster.spawn_away_from(player.global_position)

	GameManager.message("Ты застрял. Найди батарейки, прячься в шкафах и не шуми.", 5.0)
