extends Node

signal game_over(reason: String)
signal game_restarted
signal player_spawned(player: Node3D)
signal monster_spawned(monster: Node3D)
signal battery_count_changed(count: int)
signal stamina_changed(value: float, max_value: float)
signal prompt_changed(text: String)

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var run_seed: int = 0

var player: Node3D = null
var monster: Node3D = null
var maze_generator: Node = null

var is_game_over: bool = false
var is_paused: bool = false

var battery_inventory: Array[float] = [] # charge values 0..100
var stamina: float = 100.0
var max_stamina: float = 100.0

var fear_level: float = 0.0 # 0..1, drives postprocess

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	new_run()

func new_run() -> void:
	run_seed = int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
	rng.seed = run_seed
	is_game_over = false
	is_paused = false
	battery_inventory.clear()
	stamina = max_stamina
	fear_level = 0.0
	get_tree().paused = false

func register_player(p: Node3D) -> void:
	player = p
	player_spawned.emit(p)

func register_monster(m: Node3D) -> void:
	monster = m
	monster_spawned.emit(m)

func register_maze(m: Node) -> void:
	maze_generator = m

func add_battery(charge: float = 100.0) -> void:
	battery_inventory.append(clampf(charge, 0.0, 100.0))
	battery_count_changed.emit(battery_inventory.size())

func consume_battery() -> float:
	if battery_inventory.is_empty():
		return -1.0
	# Take the highest charge battery first (player would choose best)
	var best_idx := 0
	for i in range(1, battery_inventory.size()):
		if battery_inventory[i] > battery_inventory[best_idx]:
			best_idx = i
	var charge: float = battery_inventory[best_idx]
	battery_inventory.remove_at(best_idx)
	battery_count_changed.emit(battery_inventory.size())
	return charge

func get_battery_count() -> int:
	return battery_inventory.size()

func set_stamina(value: float) -> void:
	stamina = clampf(value, 0.0, max_stamina)
	stamina_changed.emit(stamina, max_stamina)

func set_fear(value: float) -> void:
	fear_level = clampf(value, 0.0, 1.0)

func push_fear(value: float) -> void:
	fear_level = clampf(maxf(fear_level, value), 0.0, 1.0)

func _process(delta: float) -> void:
	# Decay fear slowly; sources push it up each frame
	if fear_level > 0.0:
		fear_level = maxf(0.0, fear_level - delta * 0.35)

func set_prompt(text: String) -> void:
	prompt_changed.emit(text)

func trigger_game_over(reason: String = "Вас поймали") -> void:
	if is_game_over:
		return
	is_game_over = true
	game_over.emit(reason)
	# Delay pause slightly so death audio/camera can play
	await get_tree().create_timer(0.8).timeout
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func restart_game() -> void:
	get_tree().paused = false
	new_run()
	game_restarted.emit()
	get_tree().reload_current_scene()

func toggle_pause() -> void:
	if is_game_over:
		return
	is_paused = !is_paused
	get_tree().paused = is_paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED
