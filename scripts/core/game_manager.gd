extends Node
## Глобальное состояние забега. Autoload: GameManager

signal death_reached(cause: String)

var run_seed: int = 0
var is_game_over: bool = false
var is_paused: bool = false

var maze = null
var player = null
var monster = null
var hud = null
var breathing = null

var batteries_found: int = 0
var lockers_used: int = 0
var elapsed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if run_seed == 0:
		run_seed = randi()


func _process(delta: float) -> void:
	if not is_game_over and not is_paused and not get_tree().paused:
		elapsed += delta


## Полная перезагрузка сцены с новым сидом (лабиринт создаётся заново).
func prepare_new_run() -> void:
	is_game_over = false
	is_paused = false
	run_seed = randi()
	batteries_found = 0
	lockers_used = 0
	elapsed = 0.0
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().reload_current_scene()


func report_death(cause: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	death_reached.emit(cause)
	if hud and is_instance_valid(hud):
		hud.show_death(cause)


func set_paused(value: bool) -> void:
	if is_game_over:
		return
	is_paused = value
	get_tree().paused = value
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED)
	if hud and is_instance_valid(hud):
		hud.set_pause_visible(value)


## Оповещение монстра о шуме. intensity: 0..1
func emit_noise(origin: Vector3, intensity: float, kind: String = "step") -> void:
	if monster and is_instance_valid(monster):
		monster.hear_noise(origin, intensity, kind)


func notify_light(origin: Vector3, intensity: float) -> void:
	if monster and is_instance_valid(monster):
		monster.notice_light(origin, intensity)


func message(text: String, duration: float = 2.0) -> void:
	if hud and is_instance_valid(hud):
		hud.show_message(text, duration)
