extends RefCounted
class_name MazeGridAStar

# Lightweight pathfinding helper over the runtime maze grid.
# RuntimeMazeGenerator owns the canonical AStar2D; this class provides
# convenience queries and can also be used standalone if needed.

var generator: RuntimeMazeGenerator

func _init(gen: RuntimeMazeGenerator = null) -> void:
	generator = gen

func set_generator(gen: RuntimeMazeGenerator) -> void:
	generator = gen

func get_path(from_world: Vector3, to_world: Vector3) -> PackedVector3Array:
	if generator == null:
		return PackedVector3Array()
	return generator.get_astar_path(from_world, to_world)

func get_random_reachable_point(from_world: Vector3, min_dist: float, max_dist: float) -> Vector3:
	if generator == null:
		return from_world
	return generator.random_floor_cell_near(from_world, min_dist, max_dist)

func is_walkable(world_pos: Vector3) -> bool:
	if generator == null:
		return false
	var cell := generator.world_to_cell(world_pos)
	return generator.is_floor(cell)
