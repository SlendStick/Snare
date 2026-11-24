class_name MazeGridAStar
extends RefCounted
## AStar3D по клеткам лабиринта. Рёбра создаются только там, где проломлена стена.
## Перестраивать Navier baking не нужно: добавление чанка просто добавляет точки и рёбра.

const CELL_SIZE: float = 4.0
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var _astar: AStar3D = AStar3D.new()
var _cells: Dictionary = {}


static func cell_id(c: Vector2i) -> int:
	return ((c.x + 32768) << 16) | (c.y + 32768)


static func cell_center(c: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(c.x * CELL_SIZE + CELL_SIZE * 0.5, y, c.y * CELL_SIZE + CELL_SIZE * 0.5)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL_SIZE), floori(p.z / CELL_SIZE))


func add_cell(c: Vector2i) -> void:
	var id := cell_id(c)
	if _astar.has_point(id):
		return
	_astar.add_point(id, cell_center(c), true)
	_cells[id] = c


func has_cell(c: Vector2i) -> bool:
	return _astar.has_point(cell_id(c))


func set_open(c: Vector2i, dir: int, is_open: bool) -> void:
	var nb: Vector2i = c + DIRS[dir]
	var a := cell_id(c)
	var b := cell_id(nb)
	if not _astar.has_point(a) or not _astar.has_point(b):
		return
	if is_open:
		if not _astar.are_points_connected(a, b):
			_astar.connect_points(a, b, true)
	elif _astar.are_points_connected(a, b):
		_astar.disconnect_points(a, b, true)


func nearest_cell(p: Vector3) -> Vector2i:
	var guess := world_to_cell(p)
	if has_cell(guess):
		return guess
	for radius in range(1, 12):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var c: Vector2i = guess + Vector2i(x, y)
				if has_cell(c):
					return c
	return guess


## Возвращает список мировых точек (центры клеток) от nearest(from) до nearest(to).
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	var a := nearest_cell(from)
	var b := nearest_cell(to)
	var ia := cell_id(a)
	var ib := cell_id(b)
	if not _astar.has_point(ia) or not _astar.has_point(ib) or ia == ib:
		return result
	var ids = _astar.get_id_path(ia, ib)
	for id in ids:
		result.append(_astar.get_point_position(id))
	return result


func cell_count() -> int:
	return _astar.get_point_count()
