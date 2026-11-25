class_name MazeChunk
extends Node3D
## Один чанк = 4x4 клетки по 4 метра. Вся геометрия собирается из примитивов.

const CELL_SIZE: float = 4.0
const CHUNK_CELLS: int = 4
const CHUNK_SIZE: float = 16.0

var built: bool = false
var coord: Vector2i = Vector2i.ZERO
var wall_nodes: Dictionary = {}
var _gen = null
var _locker_scene: PackedScene = preload("res://scenes/world/locker.tscn")
var _battery_scene: PackedScene = preload("res://scenes/world/battery_pickup.tscn")


static func wall_key(c: Vector2i, dir: int) -> String:
	match dir:
		0:
			return "H%d,%d" % [c.x, c.y]
		1:
			return "V%d,%d" % [c.x + 1, c.y]
		2:
			return "H%d,%d" % [c.x, c.y + 1]
		_:
			return "V%d,%d" % [c.x, c.y]


static func wall_center(c: Vector2i, dir: int) -> Vector3:
	match dir:
		0:
			return Vector3((float(c.x) + 0.5) * CELL_SIZE, 1.6, float(c.y) * CELL_SIZE)
		1:
			return Vector3(float(c.x + 1) * CELL_SIZE, 1.6, (float(c.y) + 0.5) * CELL_SIZE)
		2:
			return Vector3((float(c.x) + 0.5) * CELL_SIZE, 1.6, float(c.y + 1) * CELL_SIZE)
		_:
			return Vector3(float(c.x) * CELL_SIZE, 1.6, (float(c.y) + 0.5) * CELL_SIZE)


func build(gen, cc: Vector2i, rng: RandomNumberGenerator) -> void:
	if built:
		return
	_gen = gen
	coord = cc
	var origin := Vector3(float(cc.x) * CHUNK_SIZE, 0.0, float(cc.y) * CHUNK_SIZE)

	_add_box(
		origin + Vector3(CHUNK_SIZE * 0.5, -0.16, CHUNK_SIZE * 0.5),
		Vector3(CHUNK_SIZE, 0.32, CHUNK_SIZE),
		ProcMaterials.floor(),
		true
	)
	_add_box(
		origin + Vector3(CHUNK_SIZE * 0.5, 3.36, CHUNK_SIZE * 0.5),
		Vector3(CHUNK_SIZE, 0.32, CHUNK_SIZE),
		ProcMaterials.ceiling(),
		true
	)

	var locker_cells: Dictionary = {}
	var locker_count: int = 0
	var battery_count: int = 0

	for dx in range(CHUNK_CELLS):
		for dy in range(CHUNK_CELLS):
			var c := Vector2i(cc.x * CHUNK_CELLS + dx, cc.y * CHUNK_CELLS + dy)
			for d in range(4):
				if gen.is_open(c, d):
					continue
				var key := wall_key(c, d)
				if wall_nodes.has(key):
					continue
				var horizontal: bool = d == 0 or d == 2
				var size := (
					Vector3(CELL_SIZE + 0.16, 3.2, 0.24)
					if horizontal
					else Vector3(0.24, 3.2, CELL_SIZE + 0.16)
				)
				var body := _add_box(wall_center(c, d), size, ProcMaterials.wall(), true)
				wall_nodes[key] = body

			# Трубы и арматура под потолком — ориентиры в темноте.
			if rng.randf() < 0.30:
				_add_pipe(c, rng)

			# Шкафы: плотность ≈ 0.28 на клетку, не более 5 на чанк.
			if locker_count < 5 and not locker_cells.has(c) and rng.randf() < 0.28:
				var dirs: Array[int] = []
				for d in range(4):
					if not gen.is_open(c, d):
						dirs.append(d)
				if not dirs.is_empty():
					var d: int = dirs[rng.randi_range(0, dirs.size() - 1)]
					var locker = _locker_scene.instantiate()
					locker.name = "Locker_%d_%d_%d" % [c.x, c.y, d]
					add_child(locker)
					locker.setup(gen, c, d, rng)
					gen.register_locker(locker)
					locker_cells[c] = true
					locker_count += 1

			# Батарейки разбросаны по полу; часть спрятана в нишах у стен.
			if battery_count < 6 and rng.randf() < 0.32:
				var pickup = _battery_scene.instantiate()
				pickup.name = "Battery_%d_%d" % [c.x, c.y]
				add_child(pickup)
				pickup.setup(c, rng, locker_cells.has(c))
				battery_count += 1

	built = true


func remove_wall(c: Vector2i, dir: int) -> void:
	var key := wall_key(c, dir)
	if wall_nodes.has(key):
		var node = wall_nodes[key]
		wall_nodes.erase(key)
		if is_instance_valid(node):
			# Не удаляем узел: скрываем и выключаем коллизию, чтобы не дёргать рендер.
			node.visible = false
			if node is CollisionObject3D:
				node.collision_layer = 0
				node.collision_mask = 0


func _add_box(pos: Vector3, size: Vector3, mat: Material, collide: bool) -> Node3D:
	var body: Node3D
	if collide:
		var static_body := StaticBody3D.new()
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		body = static_body
	else:
		body = Node3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	body.add_child(mesh)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
	add_child(body)
	return body


func _add_pipe(c: Vector2i, rng: RandomNumberGenerator) -> void:
	var horizontal: bool = rng.randf() < 0.5
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.055
	cylinder.bottom_radius = 0.055
	cylinder.height = CELL_SIZE * 0.85
	cylinder.radial_segments = 8
	var mesh := MeshInstance3D.new()
	mesh.mesh = cylinder
	mesh.material_override = ProcMaterials.rust() if rng.randf() < 0.5 else ProcMaterials.metal()
	var center := Vector3((float(c.x) + 0.5) * CELL_SIZE, 0.0, (float(c.y) + 0.5) * CELL_SIZE)
	mesh.position = center + Vector3(0.0, 2.72, -CELL_SIZE * 0.42)
	if horizontal:
		mesh.rotation.z = PI * 0.5
		mesh.position = center + Vector3(-CELL_SIZE * 0.42, 2.72, -CELL_SIZE * 0.42)
	else:
		mesh.rotation.x = PI * 0.5
		mesh.position = center + Vector3(-CELL_SIZE * 0.42, 2.72, -CELL_SIZE * 0.42)
	add_child(mesh)

	# Кронштейн
	var bracket := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.12, 0.35, 0.12)
	bracket.mesh = bmesh
	bracket.material_override = ProcMaterials.metal()
	bracket.position = mesh.position + Vector3(0.0, -0.2, 0.0)
	add_child(bracket)
