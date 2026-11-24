class_name BreathingMinigame
extends Control
## Ритм-механика в шкафу: [Q] вдох, [Space] выдох строго в зелёной зоне кольца.

var active: bool = false
var phase: int = 0  # 0 — вдох, 1 — выдох
var time_in_phase: float = 0.0
var phase_duration: float = 1.9
var target_time: float = 0.95
var timing_window: float = 0.42
var mistakes: int = 0
var successes: int = 0
var panic: float = 0.0
var monster = null
var locker = null

var _prompt: Label = null
var _counter: Label = null
var _flash: float = 0.0
var _flash_good: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -150
	_prompt.offset_bottom = -110
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 26)
	add_child(_prompt)

	_counter = Label.new()
	_counter.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_counter.offset_top = -108
	_counter.offset_bottom = -82
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.add_theme_font_size_override("font_size", 17)
	add_child(_counter)


func start(locker_node, monster_node) -> void:
	active = true
	visible = true
	locker = locker_node
	monster = monster_node
	mistakes = 0
	successes = 0
	panic = 0.2
	phase = 0
	time_in_phase = 0.0
	phase_duration = 1.9
	target_time = 0.95
	timing_window = 0.46
	_update_labels()
	queue_redraw()


func stop() -> void:
	active = false
	visible = false
	panic = 0.0
	queue_redraw()


func handle_key(keycode: int) -> void:
	if not active:
		return
	var expected: int = KEY_Q if phase == 0 else KEY_SPACE
	if keycode != expected:
		_miss(false)
		return
	if absf(time_in_phase - target_time) <= timing_window * 0.5:
		_success()
	else:
		_miss(false)


func _process(delta: float) -> void:
	if not active:
		return
	time_in_phase += delta
	panic = minf(1.0, panic + delta * 0.055)
	_flash = maxf(0.0, _flash - delta * 2.2)
	if time_in_phase >= phase_duration:
		_miss(true)
		return
	_update_labels()
	queue_redraw()


func _success() -> void:
	successes += 1
	panic = maxf(0.0, panic - 0.3)
	_flash = 1.0
	_flash_good = true
	AudioSynth.play_2d("breath_in" if phase == 0 else "breath_out", -5.0)
	if successes >= 3:
		stop()
		if monster and is_instance_valid(monster):
			monster.on_breathing_success()
		return
	_next_phase()


func _miss(_timed_out: bool) -> void:
	mistakes += 1
	panic = minf(1.0, panic + 0.32)
	_flash = 1.0
	_flash_good = false
	AudioSynth.play_2d("gasp", -1.0)
	GameManager.message("Срыв дыхания! " + str(mistakes) + "/3", 1.5)
	if mistakes >= 3:
		stop()
		if monster and is_instance_valid(monster):
			monster.on_breathing_failure()
		return
	_next_phase()


func _next_phase() -> void:
	phase = 1 - phase
	time_in_phase = 0.0
	phase_duration = randf_range(1.7, 2.1)
	target_time = phase_duration * 0.52
	timing_window = 0.40 if mistakes > 0 else 0.46
	_update_labels()


func _update_labels() -> void:
	if not _prompt:
		return
	_prompt.text = "ВДОХ  [Q]" if phase == 0 else "ВЫДОХ  [SPACE]"
	_counter.text = "Ровно: %d/3     Срывы: %d/3" % [successes, mistakes]


func _draw() -> void:
	if not active:
		return
	var center := Vector2(size.x * 0.5, size.y * 0.72)
	var radius: float = minf(52.0, size.y * 0.09)
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.05, 0.05, 0.06, 0.75), 12.0, true)

	var start_a: float = (
		-PI * 0.5 + TAU * clampf((target_time - timing_window * 0.5) / phase_duration, 0.0, 1.0)
	)
	var end_a: float = (
		-PI * 0.5 + TAU * clampf((target_time + timing_window * 0.5) / phase_duration, 0.0, 1.0)
	)
	draw_arc(center, radius, start_a, end_a, 32, Color(0.15, 0.75, 0.40, 0.85), 12.0, true)

	var progress: float = clampf(time_in_phase / phase_duration, 0.0, 1.0)
	var marker_a: float = -PI * 0.5 + TAU * progress
	var marker := center + Vector2(cos(marker_a), sin(marker_a)) * radius
	var marker_color: Color = Color(0.95, 0.92, 0.82)
	if _flash > 0.0:
		marker_color = Color(0.2, 1.0, 0.4) if _flash_good else Color(1.0, 0.2, 0.12)
	draw_circle(marker, 7.0, marker_color)

	var inner: Color = Color(0.55, 0.10, 0.10, 0.35 + panic * 0.4)
	draw_arc(center, radius - 17.0, 0.0, TAU * clampf(panic, 0.0, 1.0), 48, inner, 4.0, true)
