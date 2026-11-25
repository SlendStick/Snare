extends CanvasLayer

@onready var prompt_label: Label = $Root/PromptLabel
@onready var battery_label: Label = $Root/BatteryLabel
@onready var stamina_bar: ProgressBar = $Root/StaminaBar
@onready var charge_bar: ProgressBar = $Root/ChargeBar
@onready var status_label: Label = $Root/StatusLabel
@onready var crosshair: Label = $Root/Crosshair
@onready var pause_panel: Control = $Root/PausePanel
@onready var game_over_panel: Control = $Root/GameOverPanel
@onready var game_over_reason: Label = $Root/GameOverPanel/VBox/Reason
@onready var restart_button: Button = $Root/GameOverPanel/VBox/RestartButton

var player: Node = null
var _prompt_tween: Tween = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.prompt_changed.connect(_on_prompt_changed)
	GameManager.battery_count_changed.connect(_on_battery_changed)
	GameManager.stamina_changed.connect(_on_stamina_changed)
	GameManager.game_over.connect(_on_game_over)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if pause_panel:
		pause_panel.visible = false
	if game_over_panel:
		game_over_panel.visible = false
	_on_battery_changed(GameManager.get_battery_count())
	_on_stamina_changed(GameManager.stamina, GameManager.max_stamina)

func set_player(p: Node) -> void:
	player = p

func _process(_delta: float) -> void:
	if GameManager.is_game_over:
		return
	# Pause visibility
	if pause_panel:
		pause_panel.visible = GameManager.is_paused

	# Flashlight/charge status
	var fl = null
	if player and player.has_method("get_flashlight"):
		fl = player.get_flashlight()
	if fl:
		var pct: float = fl.get_battery_percent() if fl.has_method("get_battery_percent") else 0.0
		charge_bar.value = pct
		var ch_color := Color(0.3, 0.8, 0.4)
		if pct < 20.0:
			ch_color = Color(0.9, 0.25, 0.2)
		elif pct < 40.0:
			ch_color = Color(0.9, 0.7, 0.2)
		charge_bar.modulate = ch_color

		var status := ""
		if fl.has_method("is_servicing") and fl.is_servicing():
			status = fl.get_service_step_name() if fl.has_method("get_service_step_name") else "Обслуживание..."
		elif fl.has_method("is_broken") and fl.is_broken():
			status = "Фонарик погас — трясите мышью!"
		elif pct <= 0.0:
			status = "Батарея разряжена — нажмите R"
		status_label.text = status
	else:
		status_label.text = ""

func _on_prompt_changed(text: String) -> void:
	if prompt_label:
		prompt_label.text = text
		prompt_label.visible = text != ""

func _on_battery_changed(count: int) -> void:
	if battery_label:
		battery_label.text = "Батарейки: %d" % count

func _on_stamina_changed(value: float, max_value: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = max_value
		stamina_bar.value = value
		stamina_bar.visible = value < max_value - 1.0

func _on_game_over(reason: String) -> void:
	if game_over_panel:
		game_over_panel.visible = true
	if game_over_reason:
		game_over_reason.text = reason
	if pause_panel:
		pause_panel.visible = false

func _on_restart_pressed() -> void:
	GameManager.restart_game()

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_game_over:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				GameManager.restart_game()
		return
	if event.is_action_pressed("pause"):
		# GameManager.toggle_pause() is handled in player; just update UI
		pass
