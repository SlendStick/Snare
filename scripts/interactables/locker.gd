class_name Locker
extends StaticBody3D
## Высокий шкаф со щелями в дверце. Укрытие от монстра.

const CELL_SIZE: float = 4.0
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var used: bool = false
var exit_position: Vector3 = Vector3.ZERO
var look_yaw: float = 0.0
var gen = null
var door_pivot: Node3D = null
var _shaking: bool = false


func setup(gen_node, cell: Vector2i, dir: int, rng: RandomNumberGenerator) -> void:
	gen = gen_node
	var center := Vector3((float(cell.x) + 0.5) * CELL_SIZE, 0.0, (float(cell.y) + 0.5) * CELL_SIZE)
	var dv: Vector2i = DIRS[dir]
	var outward := Vector3(float(dv.x), 0.0, float(dv.y))
	var front := -outward
	global_position = center + outward * (CELL_SIZE * 0.5 - 0.38)
	rotation.y = atan2(front.x, front.z)
	look_yaw = atan2(-front.x, -front.z)
	exit_position = global_position + front * 1.15
	exit_position.y = 0.06
	_build(rng)


func _build(rng: RandomNumberGenerator) -> void:
	collision_layer = 1
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.22, 2.5, 0.74)
	col.position = Vector3(0.0, 1.25, 0.0)
	col.shape = shape
	add_child(col)

	var metal: Material = ProcMaterials.metal()
	var dark: Material = ProcMaterials.dark()
	_add_box(Vector3(0.0, 1.25, -0.34), Vector3(1.18, 2.5, 0.06), metal)
	_add_box(Vector3(-0.58, 1.25, 0.0), Vector3(0.06, 2.5, 0.70), metal)
	_add_box(Vector3(0.58, 1.25, 0.0), Vector3(0.06, 2.5, 0.70), metal)
	_add_box(Vector3(0.0, 2.47, 0.0), Vector3(1.2, 0.06, 0.74), metal)
	_add_box(Vector3(0.0, 0.05, 0.0), Vector3(1.2, 0.08, 0.74), metal)
	_add_box(Vector3(0.0, 1.25, -0.29), Vector3(1.05, 2.3, 0.02), dark)

	# Дверь из горизонтальных планок: между ними остаются настоящие щели.
	door_pivot = Node3D.new()
	door_pivot.position = Vector3(-0.55, 0.0, 0.32)
	add_child(door_pivot)
	for i in range(10):
		var y: float = 0.30 + float(i) * 0.21
		_add_box_to(
			door_pivot,
			Vector3(0.55, y, 0.0),
			Vector3(1.06, 0.145, 0.045),
			metal if rng.randf() < 0.85 else ProcMaterials.rust()
		)
	_add_box_to(door_pivot, Vector3(0.03, 1.25, 0.0), Vector3(0.05, 2.45, 0.05), metal)
	_add_box_to(
		door_pivot, Vector3(0.90, 1.12, 0.06), Vector3(0.045, 0.30, 0.07), ProcMaterials.rust()
	)


func _add_box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	return _add_box_to(self, pos, size, mat)


func _add_box_to(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


func interact_text(_player: Node) -> String:
	return "Выйти из шкафа [E]" if used else "Спрятаться в шкафу [E]"


func interact(player) -> void:
	if used:
		if player.hidden_locker == self:
			exit_locker(player)
		return
	if not player.hidden:
		enter_locker(player)


func enter_locker(player) -> void:
	used = true
	player.enter_locker(self)
	AudioSynth.play_3d("locker_creak", global_position, -3.0)
	_animate_door(-2.0, 0.32, 0.55)


func exit_locker(player) -> void:
	used = false
	player.exit_locker(self)
	AudioSynth.play_3d("locker_creak", global_position, -3.0, 0.92)
	_animate_door(-1.7, 0.28, 0.42)


func knock() -> void:
	if _shaking or not is_instance_valid(door_pivot):
		return
	_shaking = true
	var t := create_tween()
	t.tween_property(door_pivot, "rotation:y", -0.16, 0.08)
	t.tween_property(door_pivot, "rotation:y", 0.0, 0.09)
	t.tween_property(door_pivot, "rotation:y", 0.13, 0.08)
	t.tween_property(door_pivot, "rotation:y", 0.0, 0.12)
	t.finished.connect(func() -> void: _shaking = false)


func break_open() -> void:
	AudioSynth.play_3d("door_slam", global_position, 4.0)
	if is_instance_valid(door_pivot):
		var t := create_tween()
		t.tween_property(door_pivot, "rotation:y", -2.6, 0.12).set_ease(Tween.EASE_OUT)
		t.tween_property(door_pivot, "rotation:y", -1.9, 0.2)


func _animate_door(open_angle: float, open_time: float, close_time: float) -> void:
	if not is_instance_valid(door_pivot):
		return
	var t := create_tween()
	t.tween_property(door_pivot, "rotation:y", open_angle, open_time).set_ease(Tween.EASE_OUT)
	t.tween_property(door_pivot, "rotation:y", 0.0, close_time).set_ease(Tween.EASE_IN)
