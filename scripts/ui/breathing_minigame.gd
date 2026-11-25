extends Control

signal success
signal failure
signal panic_maxed

@export var max_failures: int = 3

var active: bool = false
var _pulse_t: float = 0.0
var _cycle_duration: float = 1.8 # seconds per breath cycle
var _phase: float = 0.0 # 0..1
var _expect_left: bool = true # alternate Q / E
var _input_window_open: bool = false
var _window_center: float = 0.5
var _window_half: float = 0.12
var _hits: int = 0
var _fails: int = 0
var _calm: float = 0.5 # 0..1, higher is calmer
var _needed_calm_hits: int = 5
var _hit_this_cycle: bool = false
var _missed_this_cycle: bool = false
var _feedback: String = ""
var _feedback_t: float = 0.0

@onready var label: Label = $Label
@onready var sublabel: Label = $SubLabel

func _ready() -> void:
	visible = false
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func start_minigame() -> void:
	active = true
	visible = true
	set_process(true)
	_pulse_t = 0.0
	_phase = 0.0
	_expect_left = true
	_hits = 0
	_fails = 0
	_calm = 0.35
	_hit_this_cycle = false
	_missed_this_cycle = false
	_feedback = "Контролируй дыхание..."
	_feedback_t = 1.5
	_update_labels()

func stop_minigame() -> void:
	active = false
	visible = false
	set_process(false)

func is_active() -> bool:
	return active

func get_calm() -> float:
	return _calm

func get_failures() -> int:
	return _fails

func _process(delta: float) -> void:
	if not active:
		return
	_pulse_t += delta
	var prev_phase := _phase
	_phase = fmod(_pulse_t, _cycle_duration) / _cycle_duration

	# Detect cycle boundary
	if _phase < prev_phase:
		if not _hit_this_cycle and _input_window_open:
			_register_miss()
		_hit_this_cycle = false
		_missed_this_cycle = false

	# Input window around center of cycle (exhale/inhale beat)
	var dist := absf(_phase - _window_center)
	_input_window_open = dist < 0.25

	if _feedback_t > 0.0:
		_feedback_t -= delta

	_update_labels()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("breath_left"):
		_handle_breath_input(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("breath_right"):
		_handle_breath_input(false)
		get_viewport().set_input_as_handled()

func _handle_breath_input(is_left: bool) -> void:
	if _hit_this_cycle:
		return
	if is_left != _expect_left:
		_register_miss()
		return
	var dist := absf(_phase - _window_center)
	if dist <= _window_half:
		_register_hit()
	else:
		_register_miss()

func _register_hit() -> void:
	_hit_this_cycle = true
	_hits += 1
	_calm = clampf(_calm + 0.18, 0.0, 1.0)
	_expect_left = not _expect_left
	_feedback = "Тихо..."
	_feedback_t = 0.8
	AudioSynth.play_2d("breath_calm", -18.0, randf_range(0.95, 1.05), self)
	success.emit()
	if _calm >= 1.0 or _hits >= _needed_calm_hits:
		_calm = 1.0
		_feedback = "Дыхание ровное"
		_feedback_t = 1.0

func _register_miss() -> void:
	if _missed_this_cycle:
		return
	_missed_this_cycle = true
	_hit_this_cycle = true # prevent double miss
	_fails += 1
	_calm = clampf(_calm - 0.28, 0.0, 1.0)
	_expect_left = not _expect_left
	_feedback = "Срыв! Тише!"
	_feedback_t = 1.0
	AudioSynth.play_2d("breath_gasp", -6.0, randf_range(0.9, 1.1), self)
	failure.emit()
	if _fails >= max_failures or _calm <= 0.0:
		panic_maxed.emit()

func _update_labels() -> void:
	if label:
		var key := "Q" if _expect_left else "E"
		var phase_name := "ВДОХ" if _phase < 0.5 else "ВЫДОХ"
		label.text = "%s  [%s]" % [phase_name, key]
	if sublabel:
		var bar := ""
		var filled := int(_calm * 10)
		for i in range(10):
			bar += "█" if i < filled else "░"
		sublabel.text = "%s\n%s" % [bar, _feedback if _feedback_t > 0 else ""]

func _draw() -> void:
	if not active:
		return
	var center := size * 0.5 + Vector2(0, 40)
	var radius := 52.0
	# Outer ring
	draw_arc(center, radius, 0, TAU, 64, Color(0.4, 0.45, 0.5, 0.25), 3.0)
	# Timing window arc
	var start_a := (_window_center - _window_half) * TAU - PI * 0.5
	var end_a := (_window_center + _window_half) * TAU - PI * 0.5
	draw_arc(center, radius, start_a, end_a, 24, Color(0.3, 0.8, 0.4, 0.7), 5.0)
	# Current phase marker
	var a := _phase * TAU - PI * 0.5
	var p1 := center + Vector2(cos(a), sin(a)) * (radius - 10)
	var p2 := center + Vector2(cos(a), sin(a)) * (radius + 10)
	var col := Color(0.9, 0.95, 1.0, 0.9)
	if absf(_phase - _window_center) <= _window_half:
		col = Color(0.4, 1.0, 0.5, 0.95)
	draw_line(p1, p2, col, 4.0)
	# Pulsing inner circle
	var pulse_r := 18.0 + sin(_pulse_t * 2.5) * 4.0 * (1.0 - _calm)
	draw_arc(center, pulse_r, 0, TAU, 48, Color(0.8, 0.3, 0.3, 0.25 + (1.0 - _calm) * 0.35), 2.0)
