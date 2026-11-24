extends Control
## Экран смерти с мгновенным рестартом и новым сидом лабиринта.

var cause_label: Label = null
var stats_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.0, 0.0, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -240.0
	box.offset_top = -130.0
	box.offset_right = 240.0
	box.offset_bottom = 130.0
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := Label.new()
	title.text = "ТЫ ПОГИБ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.78, 0.12, 0.10))
	box.add_child(title)

	cause_label = Label.new()
	cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cause_label.add_theme_font_size_override("font_size", 19)
	box.add_child(cause_label)

	stats_label = Label.new()
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 15)
	stats_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.62))
	box.add_child(stats_label)

	var restart := Button.new()
	restart.text = "НОВЫЙ ЛАБИРИНТ"
	restart.add_theme_font_size_override("font_size", 20)
	restart.pressed.connect(GameManager.prepare_new_run)
	box.add_child(restart)


func show_death(cause: String) -> void:
	if cause_label:
		cause_label.text = cause
	var seconds: int = int(GameManager.elapsed)
	if stats_label:
		stats_label.text = (
			"Время: %d:%02d   •   Батареек: %d   •   Укрытий: %d   •   Seed: %d"
			% [
				seconds / 60,
				seconds % 60,
				GameManager.batteries_found,
				GameManager.lockers_used,
				GameManager.run_seed
			]
		)
