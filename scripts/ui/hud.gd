extends CanvasLayer

const BREATHING_SCENE: PackedScene = preload("res://scenes/ui/breathing_minigame.tscn")
const DEATH_SCENE: PackedScene = preload("res://scenes/ui/game_over.tscn")
## Минималистичный HUD, пост-обработка, пауза и экран смерти.

var fear: float = 0.0
var post_material: ShaderMaterial = null
var post_rect: ColorRect = null
var prompt_label: Label = null
var status_label: Label = null
var message_label: Label = null
var hint_label: Label = null
var seed_label: Label = null
var stamina_fill: ColorRect = null
var pause_panel: Control = null
var game_over_panel = null
var _message_timer: float = 0.0
var _hint_timer: float = 14.0
var _player = null


func _ready() -> void:
	GameManager.hud = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_postprocess()
	_build_hud()

	var breathing: Control = BREATHING_SCENE.instantiate()
	add_child(breathing)
	GameManager.breathing = breathing

	game_over_panel = DEATH_SCENE.instantiate()
	add_child(game_over_panel)
	game_over_panel.hide()

	GameManager.death_reached.connect(_on_death_reached)


func _build_postprocess() -> void:
	var shader: Shader = load("res://shaders/horror_postprocess.gdshader") as Shader
	if not shader:
		return
	post_material = ShaderMaterial.new()
	post_material.shader = shader
	var rect := ColorRect.new()
	rect.material = post_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	post_rect = rect


func _make_rect(
	offset_left: float,
	offset_top: float,
	width: float,
	height: float,
	color: Color,
	anchor_x: float = 0.0,
	anchor_y: float = 0.0
) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.anchor_left = anchor_x
	rect.anchor_top = anchor_y
	rect.anchor_right = anchor_x
	rect.anchor_bottom = anchor_y
	rect.offset_left = offset_left
	rect.offset_top = offset_top
	rect.offset_right = offset_left + width
	rect.offset_bottom = offset_top + height
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


func _make_label(
	offset_left: float,
	offset_top: float,
	width: float,
	height: float,
	size: int,
	color: Color,
	anchor_x: float = 0.0,
	anchor_y: float = 0.0
) -> Label:
	var label := Label.new()
	label.anchor_left = anchor_x
	label.anchor_top = anchor_y
	label.anchor_right = anchor_x
	label.anchor_bottom = anchor_y
	label.offset_left = offset_left
	label.offset_top = offset_top
	label.offset_right = offset_left + width
	label.offset_bottom = offset_top + height
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _build_hud() -> void:
	_make_rect(-2.0, -2.0, 4.0, 4.0, Color(0.85, 0.87, 0.82, 0.7), 0.5, 0.5)
	status_label = _make_label(20.0, 18.0, 440.0, 74.0, 17, Color(0.78, 0.80, 0.76, 0.85))
	seed_label = _make_label(20.0, -46.0, 420.0, 24.0, 13, Color(0.45, 0.48, 0.48, 0.7), 0.0, 1.0)
	prompt_label = _make_label(
		-300.0, -84.0, 600.0, 32.0, 20, Color(0.92, 0.90, 0.78, 0.92), 0.5, 1.0
	)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label = _make_label(
		-400.0, 70.0, 800.0, 40.0, 18, Color(0.88, 0.72, 0.55, 0.95), 0.5, 0.0
	)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	hint_label = _make_label(
		-460.0, -180.0, 920.0, 78.0, 17, Color(0.86, 0.89, 0.82, 0.95), 0.5, 1.0
	)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.text = (
		"КАК ИГРАТЬ: WASD — идти, Shift — бежать (шумно), Ctrl — красться, мышь — смотреть\n"
		+ "E — поднять батарейку / залезть в шкаф, F — фонарик, R — заменить батарейку\n"
		+ "Сломался фонарь — тряси мышью. В шкафу: Q — вдох, Space — выдох. [P] — убрать фильтр."
	)

	_make_rect(20.0, -64.0, 180.0, 7.0, Color(0.12, 0.13, 0.14, 0.8), 0.0, 1.0)
	stamina_fill = _make_rect(20.0, -64.0, 180.0, 7.0, Color(0.35, 0.62, 0.58, 0.75), 0.0, 1.0)

	_build_pause_panel()


func _build_pause_panel() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pause_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -150.0
	box.offset_top = -100.0
	box.offset_right = 150.0
	box.offset_bottom = 100.0
	box.add_theme_constant_override("separation", 14)
	pause_panel.add_child(box)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)

	var resume := Button.new()
	resume.text = "Продолжить"
	resume.pressed.connect(func() -> void: GameManager.set_paused(false))
	box.add_child(resume)

	var restart := Button.new()
	restart.text = "Новый лабиринт"
	restart.pressed.connect(GameManager.prepare_new_run)
	box.add_child(restart)
	pause_panel.hide()


func set_pause_visible(value: bool) -> void:
	if pause_panel:
		pause_panel.visible = value


func _process(delta: float) -> void:
	if post_material:
		post_material.set_shader_parameter("time", float(Time.get_ticks_msec()) / 1000.0)
		post_material.set_shader_parameter("fear", fear)
		post_material.set_shader_parameter("shake", clampf(fear * 0.7, 0.0, 1.0))

	_message_timer -= delta
	if message_label and _message_timer <= 0.0:
		message_label.text = ""
	_hint_timer -= delta
	if hint_label and _hint_timer <= 0.0:
		hint_label.text = ""

	_player = GameManager.player
	if not _player or not is_instance_valid(_player):
		return
	if prompt_label:
		prompt_label.text = _player.interaction_hint()
	if status_label:
		var f = _player.get_node("Camera3D/Flashlight")
		var state_text: String = (
			"неисправен — тряси мышью"
			if f.broken
			else ("выключен" if not f.enabled else "работает")
		)
		status_label.text = (
			"ФОНАРИК  %d%%  •  %s\nБАТАРЕЙКИ  %d    [F] вкл  [R] разборка  [Ctrl] тише"
			% [int(f.charge * 100.0), state_text, _player.batteries.size()]
		)
	if stamina_fill:
		stamina_fill.size.x = 180.0 * clampf(_player.stamina / 100.0, 0.0, 1.0)
	if seed_label:
		seed_label.text = (
			"SEED %d   •   [%s]   •   %d:%02d"
			% [
				GameManager.run_seed,
				GameManager.monster.state if GameManager.monster else "—",
				int(GameManager.elapsed) / 60,
				int(GameManager.elapsed) % 60
			]
		)


func toggle_postprocess() -> void:
	if post_rect:
		post_rect.visible = not post_rect.visible
		show_message("Пост-эффект: " + ("вкл" if post_rect.visible else "выкл"), 1.5)


func set_fear(value: float) -> void:
	fear = clampf(value, 0.0, 1.0)


func show_message(text: String, duration: float = 2.0) -> void:
	if message_label:
		message_label.text = text
	_message_timer = duration


func show_death(cause: String) -> void:
	if pause_panel:
		pause_panel.hide()
	if game_over_panel and game_over_panel.has_method("show_death"):
		game_over_panel.show_death(cause)
		game_over_panel.show()


func _on_death_reached(cause: String) -> void:
	show_death(cause)
