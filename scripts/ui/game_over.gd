extends Control

signal restart_requested

@onready var reason_label: Label = $VBox/Reason
@onready var restart_button: Button = $VBox/RestartButton

func _ready() -> void:
	if restart_button:
		restart_button.pressed.connect(func(): restart_requested.emit())

func show_game_over(reason: String) -> void:
	visible = true
	if reason_label:
		reason_label.text = reason

func hide_game_over() -> void:
	visible = false
