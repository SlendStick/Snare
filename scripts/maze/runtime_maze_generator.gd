class_name RuntimeMazeGenerator
extends Node3D
## Лабиринт растёт чанками вокруг игрока прямо во время игры.
## Глобальный граф клеток (recursive backtracker + дополнительные петли) гарантирует,
## что каждый новый чанк присоединяется к уже существующему минимум одним проходом.

signal chunk_generated(coord: Vector2i)

const CELL_SIZE: float = 4.0
const CHUNK_CELLS: int = 4
const CHUNK_SIZE: float = CELL_SIZE * float(CHUNK_CELLS)
const GENERATE_RADIUS: int = 2
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var seed_value: int = 0
var rng := RandomNumberGenerator.new()
var cells: Dictionary = {}  # Vector2i -> {"visited": bool, "walls": [bool x4]}
var chunks: Dictionary = {}  # Vector2i -> MazeChunk
var lockers: Array = []
var astar := MazeGridAStar.new()
var spawn_cell := Vector2i(1, 1)
var current_chunk := Vector2i.ZERO
var pending: Array[Vector2i] = []

var _chunk_scene: PackedScene = preload("res://scenes/world/maze_chunk.tscn")


func _ready() -> void:
	seed_value = GameManager.run_seed if GameManager.run_seed != 0 else randi()
	rng.seed = seed_value
	GameManager.maze = self
	ensure_chunk(Vector2i.ZERO)
	update_around(Vector3.ZERO)
	chunk_generated.connect(_on_chunk_generated)


func _process(_delta: float) -> void:
	if GameManager.player and is_instance_valid(GameManager.player):
		update_around(GameManager.player.global_position)
	# Плавная подгрузка: максимум два чанка за кадр, туман скрывает «проявление» коридоров.
	var budget: int = 2
	while pending.size() > 0 and budget > 0:
		var c: Vector2i = pending.pop_front()
		ensure_chunk(c)
		budget -= 1


func _on_chunk_generated(_coord: Vector2i) -> void:
	pass


static func chunk_of_cell(c: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(c.x) / float(CHUNK_CELLS)), floori(float(c.y) / float(CHUNK_CELLS))
	)


static func chunk_of_world(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK_SIZE), floori(p.z / CHUNK_SIZE))


static func cell_center(c: Vector2i, y: float = 0.0) -> Vector3:
	return MazeGridAStar.cell_center(c, y)


static func world_to_cell(p: Vector3) -> Vector2i:
	return MazeGridAStar.world_to_cell(p)


func cell_data(c: Vector2i) -> Dictionary:
	if not cells.has(c):
		cells[c] = {"visited": false, "walls": [true, true, true, true]}
	return cells[c]


func is_visited(c: Vector2i) -> bool:
	return bool(cell_data(c)["visited"])


func is_open(c: Vector2i, dir: int) -> bool:
	return not bool(cell_data(c)["walls"][dir])


func _mark_visited(c: Vector2i) -> void:
	cell_data(c)["visited"] = true


func _inside(c: Vector2i, cc: Vector2i) -> bool:
	return chunk_of_cell(c) == cc


func carve(c: Vector2i, dir: int) -> void:
	var nb: Vector2i = c + DIRS[dir]
	var a: Dictionary = cell_data(c)
	var b: Dictionary = cell_data(nb)
	a["walls"][dir] = false
	b["walls"][(dir + 2) % 4] = false
	astar.set_open(c, dir, true)
	# Если соседняя сторона уже отрисована — убираем её стену.
	_visual_remove_wall(c, dir)
	_visual_remove_wall(nb, (dir + 2) % 4)


func _visual_remove_wall(c: Vector2i, dir: int) -> void:
	var chunk = chunks.get(chunk_of_cell(c))
	if chunk and chunk.get("built") == true:
		chunk.remove_wall(c, dir)


func update_around(world_position: Vector3) -> void:
	var cc := chunk_of_world(world_position)
	if cc == current_chunk:
		return
	current_chunk = cc
	for x in range(-GENERATE_RADIUS, GENERATE_RADIUS + 1):
		for y in range(-GENERATE_RADIUS, GENERATE_RADIUS + 1):
			var c: Vector2i = cc + Vector2i(x, y)
			if chunks.has(c) or pending.has(c):
				continue
			pending.append(c)
	pending.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.distance_squared_to(cc) < b.distance_squared_to(cc)
	)


func ensure_chunk(cc: Vector2i) -> void:
	if chunks.has(cc):
		return
	if cc == Vector2i.ZERO:
		_generate_chunk(cc)
		return
	var anchor_found: bool = false
	for d in DIRS:
		if chunks.has(cc + d):
			anchor_found = true
			break
	if not anchor_found:
		# Рекурсивно строим цепочку к началу — изолированных островов не бывает.
		var step := Vector2i(0, 0)
		if cc.x != 0:
			step.x = 1 if cc.x > 0 else -1
		elif cc.y != 0:
			step.y = 1 if cc.y > 0 else -1
		ensure_chunk(cc - step)
	_generate_chunk(cc)


func _generate_chunk(cc: Vector2i) -> void:
	var chunk = _chunk_scene.instantiate()
	chunk.name = "Chunk_%d_%d" % [cc.x, cc.y]
	chunks[cc] = chunk

	var local: Array[Vector2i] = []
	for dx in range(CHUNK_CELLS):
		for dy in range(CHUNK_CELLS):
			var c := Vector2i(cc.x * CHUNK_CELLS + dx, cc.y * CHUNK_CELLS + dy)
			cell_data(c)
			astar.add_cell(c)
			local.append(c)

	# Граница с уже существующими чанками: отсюда вырастает дерево нового чанка.
	var border: Array = []
	for c in local:
		for d in range(4):
			var nb: Vector2i = c + DIRS[d]
			if not _inside(nb, cc) and is_visited(nb):
				border.append([c, d])
	border.shuffle()

	var root: Vector2i = local[rng.randi_range(0, local.size() - 1)]
	if border.size() > 0:
		root = border[0][0]
	_mark_visited(root)
	if border.size() > 0:
		carve(root, border[0][1])

	# Recursive backtracker внутри чанка.
	var stack: Array[Vector2i] = [root]
	while stack.size() > 0:
		var cur: Vector2i = stack[stack.size() - 1]
		var options: Array[int] = []
		for d in range(4):
			var nb: Vector2i = cur + DIRS[d]
			if _inside(nb, cc) and not is_visited(nb):
				options.append(d)
		if options.is_empty():
			stack.pop_back()
		else:
			var d: int = options[rng.randi_range(0, options.size() - 1)]
			var nb: Vector2i = cur + DIRS[d]
			carve(cur, d)
			_mark_visited(nb)
			stack.append(nb)

	# Дополнительные проходы к соседним чанкам и петли внутри: монстру есть где маневрировать.
	var linked_outside: Dictionary = {}
	for pair in border:
		if linked_outside.size() >= 3:
			break
		var inside: Vector2i = pair[0]
		var d: int = pair[1]
		var nb: Vector2i = inside + DIRS[d]
		var key: int = MazeGridAStar.cell_id(nb)
		if linked_outside.has(key):
			continue
		if not is_open(inside, d):
			carve(inside, d)
		linked_outside[key] = true

	for _i in range(3):
		var c: Vector2i = local[rng.randi_range(0, local.size() - 1)]
		var d: int = rng.randi_range(0, 3)
		var nb: Vector2i = c + DIRS[d]
		if _inside(nb, cc) and is_visited(nb) and not is_open(c, d):
			carve(c, d)

	add_child(chunk)
	chunk.build(self, cc, rng)
	chunk_generated.emit(cc)


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return astar.find_path(from, to)


## Случайная посещённая клетка на расстоянии от around (в клетках).
func random_visited_cell(around: Vector2i, min_dist: int, max_dist: int) -> Vector2i:
	var pool: Array[Vector2i] = []
	for c in cells:
		if not bool(cells[c]["visited"]):
			continue
		var d: int = absi(c.x - around.x) + absi(c.y - around.y)
		if d >= min_dist and d <= max_dist:
			pool.append(c)
	if pool.is_empty():
		return spawn_cell
	return pool[rng.randi_range(0, pool.size() - 1)]


func register_locker(locker: Node) -> void:
	if not lockers.has(locker):
		lockers.append(locker)


func get_locker_positions_near(pos: Vector3, radius: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for l in lockers:
		if not is_instance_valid(l):
			continue
		if l.global_position.distance_to(pos) <= radius:
			result.append(l.global_position)
	return result
