extends Node3D
class_name RuntimeMazeGenerator

signal chunk_generated(chunk_coord: Vector2i)

@export var cell_size: float = 4.0
@export var wall_height: float = 3.6
@export var chunk_nodes: int = 4 # maze nodes per chunk side; grid becomes chunk_nodes*2+1
@export var active_radius_chunks: int = 2
@export var unload_radius_chunks: int = 999 # keep chunks to avoid falling through unloaded floors
@export var max_chunks_per_frame: int = 1

var grid: Dictionary = {} # Vector2i -> bool (true = floor/open)
var generated_chunks: Dictionary = {} # Vector2i -> Node3D
var chunk_locks: Dictionary = {} # Vector2i -> true while generating
var astar: AStar2D = AStar2D.new()
var astar_ids: Dictionary = {} # Vector2i -> int
var _next_astar_id: int = 1

var player: Node3D = null
var _pending_chunks: Array[Vector2i] = []

# Materials (procedural)
var wall_mat: StandardMaterial3D
var floor_mat: StandardMaterial3D
var ceiling_mat: StandardMaterial3D
var pillar_mat: StandardMaterial3D

# Interactable scenes
var locker_scene: PackedScene
var battery_scene: PackedScene

# Decoration rng
var decor_rng: RandomNumberGenerator = RandomNumberGenerator.new()

const DIRS_4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

func _ready() -> void:
	add_to_group("maze_generator")
	GameManager.register_maze(self)
	_build_materials()
	_load_scenes()
	decor_rng.seed = GameManager.run_seed
	# Generate initial area around origin
	_update_chunks(Vector2i.ZERO, true)

func set_player(p: Node3D) -> void:
	player = p

func _load_scenes() -> void:
	if ResourceLoader.exists("res://scenes/world/locker.tscn"):
		locker_scene = load("res://scenes/world/locker.tscn")
	if ResourceLoader.exists("res://scenes/world/battery_pickup.tscn"):
		battery_scene = load("res://scenes/world/battery_pickup.tscn")

func _build_materials() -> void:
	wall_mat = _make_material(Color(0.11, 0.12, 0.11), 0.95, 0.0, 0.8)
	floor_mat = _make_material(Color(0.07, 0.075, 0.07), 1.0, 0.0, 1.0)
	ceiling_mat = _make_material(Color(0.05, 0.055, 0.06), 0.98, 0.0, 0.9)
	pillar_mat = _make_material(Color(0.09, 0.095, 0.09), 0.9, 0.0, 0.7)

func _make_material(albedo: Color, roughness: float, metallic: float, noise_strength: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	var noise := FastNoiseLite.new()
	noise.seed = GameManager.run_seed + int(roughness * 1000)
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(2, 2, 2)
	# Normal map for grime/roughness feel
	var ntex := NoiseTexture2D.new()
	ntex.width = 256
	ntex.height = 256
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 4.0 * noise_strength
	var nnoise := FastNoiseLite.new()
	nnoise.seed = noise.seed + 17
	nnoise.frequency = 0.12
	nnoise.fractal_octaves = 5
	ntex.noise = nnoise
	mat.normal_enabled = true
	mat.normal_texture = ntex
	mat.normal_scale = 0.8 * noise_strength
	return mat

func chunk_grid_size() -> int:
	return chunk_nodes * 2 + 1

func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / cell_size), roundi(pos.z / cell_size))

func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * cell_size, 0.0, cell.y * cell_size)

func world_to_chunk(pos: Vector3) -> Vector2i:
	var cgs := chunk_grid_size()
	var cell := world_to_cell(pos)
	return Vector2i(floori(float(cell.x) / cgs), floori(float(cell.y) / cgs))

func chunk_origin_cell(chunk: Vector2i) -> Vector2i:
	var cgs := chunk_grid_size()
	return Vector2i(chunk.x * cgs, chunk.y * cgs)

func is_floor(cell: Vector2i) -> bool:
	return grid.get(cell, false)

func _process(_delta: float) -> void:
	if player == null:
		var p := get_tree().get_first_node_in_group("player")
		if p is Node3D:
			player = p
	if player == null:
		return
	var pc := world_to_chunk(player.global_position)
	_update_chunks(pc, false)
	_process_pending_chunks()
	_unload_far_chunks(pc)

func _update_chunks(player_chunk: Vector2i, immediate: bool) -> void:
	for dz in range(-active_radius_chunks, active_radius_chunks + 1):
		for dx in range(-active_radius_chunks, active_radius_chunks + 1):
			var cc := Vector2i(player_chunk.x + dx, player_chunk.y + dz)
			if generated_chunks.has(cc) or chunk_locks.has(cc):
				continue
			if immediate:
				_generate_chunk(cc)
			else:
				if not _pending_chunks.has(cc):
					_pending_chunks.append(cc)
	# Sort pending by distance to player chunk
	_pending_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(player_chunk) < b.distance_squared_to(player_chunk)
	)

func _process_pending_chunks() -> void:
	var budget := max_chunks_per_frame
	while budget > 0 and not _pending_chunks.is_empty():
		var cc: Vector2i = _pending_chunks.pop_front()
		if generated_chunks.has(cc) or chunk_locks.has(cc):
			continue
		_generate_chunk(cc)
		budget -= 1

func _unload_far_chunks(player_chunk: Vector2i) -> void:
	var to_remove: Array[Vector2i] = []
	for cc: Vector2i in generated_chunks.keys():
		var dist: int = max(abs(cc.x - player_chunk.x), abs(cc.y - player_chunk.y))
		if dist > unload_radius_chunks:
			to_remove.append(cc)
	for cc in to_remove:
		var node: Node3D = generated_chunks[cc]
		if is_instance_valid(node):
			node.queue_free()
		generated_chunks.erase(cc)
		# Keep grid/astar data so returning is consistent; optional: could clear, but easier to keep.

func _generate_chunk(chunk: Vector2i) -> void:
	if generated_chunks.has(chunk) or chunk_locks.has(chunk):
		return
	chunk_locks[chunk] = true

	var cgs := chunk_grid_size()
	var origin := chunk_origin_cell(chunk)
	var local: Dictionary = {} # Vector2i local -> bool floor

	# Initialize all walls
	for z in range(cgs):
		for x in range(cgs):
			local[Vector2i(x, z)] = false

	# Recursive backtracker on odd nodes
	var visited: Dictionary = {}
	var stack: Array[Vector2i] = []
	var start := Vector2i(1, 1)
	local[start] = true
	visited[start] = true
	stack.append(start)

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(chunk)

	var dirs: Array[Vector2i] = [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var neighbors: Array[Vector2i] = []
		for d in dirs:
			var nx: int = cur.x + d.x
			var nz: int = cur.y + d.y
			if nx > 0 and nx < cgs - 1 and nz > 0 and nz < cgs - 1 and not visited.has(Vector2i(nx, nz)):
				neighbors.append(Vector2i(nx, nz))
		if neighbors.is_empty():
			stack.pop_back()
		else:
			var nxt: Vector2i = neighbors[rng.randi_range(0, neighbors.size() - 1)]
			var between := Vector2i((cur.x + nxt.x) / 2, (cur.y + nxt.y) / 2)
			local[between] = true
			local[nxt] = true
			visited[nxt] = true
			stack.append(nxt)

	# Ensure connectivity to existing neighboring chunks by carving border doors
	_ensure_border_connections(chunk, origin, cgs, local, rng)

	# Also add a few loops for less linearity
	for _i in range(rng.randi_range(2, 5)):
		var rx := rng.randi_range(1, cgs - 2)
		var rz := rng.randi_range(1, cgs - 2)
		var lc := Vector2i(rx, rz)
		if not local.get(lc, false):
			var open_neighbors := 0
			for d4 in DIRS_4:
				if local.get(lc + d4, false):
					open_neighbors += 1
			if open_neighbors == 2:
				local[lc] = true

	# Write to global grid and astar
	for z in range(cgs):
		for x in range(cgs):
			var gc := origin + Vector2i(x, z)
			var is_f: bool = local.get(Vector2i(x, z), false)
			# Don't overwrite existing floor with wall at borders (keep connections)
			if grid.has(gc) and grid[gc]:
				is_f = true
			grid[gc] = is_f
			_update_astar_cell(gc, is_f)

	# Instantiate 3D
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	add_child(root)
	generated_chunks[chunk] = root
	chunk_locks.erase(chunk)

	_build_chunk_mesh(chunk, origin, cgs, root)
	_spawn_interactables(chunk, origin, cgs, local, rng, root)

	chunk_generated.emit(chunk)

func _chunk_seed(chunk: Vector2i) -> int:
	return int(GameManager.run_seed) ^ (chunk.x * 73856093) ^ (chunk.y * 19349663)

func _ensure_border_connections(chunk: Vector2i, origin: Vector2i, cgs: int, local: Dictionary, rng: RandomNumberGenerator) -> void:
	# For each direction, if neighbor chunk exists, align doors; if not, still carve a potential door
	# so future chunks can connect. We carve at an odd coordinate on the border.
	var borders := [
		{"dir": Vector2i(0, -1), "check": func(i: int) -> Vector2i: return Vector2i(i, 0), "inner": Vector2i(0, 1)},
		{"dir": Vector2i(0, 1), "check": func(i: int) -> Vector2i: return Vector2i(i, cgs - 1), "inner": Vector2i(0, -1)},
		{"dir": Vector2i(-1, 0), "check": func(i: int) -> Vector2i: return Vector2i(0, i), "inner": Vector2i(1, 0)},
		{"dir": Vector2i(1, 0), "check": func(i: int) -> Vector2i: return Vector2i(cgs - 1, i), "inner": Vector2i(-1, 0)},
	]
	for b in borders:
		var dir: Vector2i = b["dir"]
		var neighbor_chunk := chunk + dir
		var inner: Vector2i = b["inner"]
		var candidates: Array[int] = []
		for i in range(1, cgs - 1, 2):
			candidates.append(i)
		if candidates.is_empty():
			continue
		# Prefer a candidate that connects to an existing floor in neighbor
		var chosen: int = candidates[rng.randi_range(0, candidates.size() - 1)]
		if generated_chunks.has(neighbor_chunk):
			var valid: Array[int] = []
			for i in candidates:
				var border_local: Vector2i = b["check"].call(i)
				var gc := origin + border_local
				var neighbor_gc := gc + dir
				if grid.get(neighbor_gc, false):
					valid.append(i)
			if valid.is_empty():
				# Force carve into neighbor's border cell
				chosen = candidates[rng.randi_range(0, candidates.size() - 1)]
				var border_local2: Vector2i = b["check"].call(chosen)
				var gc2 := origin + border_local2
				var neighbor_gc2 := gc2 + dir
				grid[neighbor_gc2] = true
				_update_astar_cell(neighbor_gc2, true)
				# Also ensure the cell inside neighbor is open
				var neighbor_inner_gc := neighbor_gc2 + dir
				if grid.has(neighbor_inner_gc):
					grid[neighbor_inner_gc] = true
					_update_astar_cell(neighbor_inner_gc, true)
			else:
				chosen = valid[rng.randi_range(0, valid.size() - 1)]
		var border_cell: Vector2i = b["check"].call(chosen)
		local[border_cell] = true
		local[border_cell + inner] = true

func _update_astar_cell(cell: Vector2i, is_f: bool) -> void:
	if is_f:
		if not astar_ids.has(cell):
			var id := _next_astar_id
			_next_astar_id += 1
			astar_ids[cell] = id
			astar.add_point(id, Vector2(cell.x, cell.y))
		var id: int = astar_ids[cell]
		# Connect to 4-neighbors
		for d4 in DIRS_4:
			var nc := cell + d4
			if astar_ids.has(nc) and grid.get(nc, false):
				var nid: int = astar_ids[nc]
				if not astar.are_points_connected(id, nid):
					astar.connect_points(id, nid)
	else:
		if astar_ids.has(cell):
			var id: int = astar_ids[cell]
			astar.remove_point(id)
			astar_ids.erase(cell)

func get_astar_path(from_world: Vector3, to_world: Vector3) -> PackedVector3Array:
	var from_cell := world_to_cell(from_world)
	var to_cell := world_to_cell(to_world)
	from_cell = _nearest_floor_cell(from_cell)
	to_cell = _nearest_floor_cell(to_cell)
	if not astar_ids.has(from_cell) or not astar_ids.has(to_cell):
		return PackedVector3Array()
	var path2: PackedVector2Array = astar.get_point_path(astar_ids[from_cell], astar_ids[to_cell])
	var out := PackedVector3Array()
	for p in path2:
		out.append(Vector3(p.x * cell_size, 0.0, p.y * cell_size))
	return out

func _nearest_floor_cell(cell: Vector2i) -> Vector2i:
	if grid.get(cell, false):
		return cell
	for r in range(1, 6):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dz) != r:
					continue
				var c := cell + Vector2i(dx, dz)
				if grid.get(c, false):
					return c
	return cell

func random_floor_cell_near(world_pos: Vector3, min_dist: float, max_dist: float, attempts: int = 30) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var center := world_to_cell(world_pos)
	var min_c := int(min_dist / cell_size)
	var max_c := int(max_dist / cell_size)
	for _i in range(attempts):
		var c := center + Vector2i(rng.randi_range(-max_c, max_c), rng.randi_range(-max_c, max_c))
		if grid.get(c, false):
			var d := center.distance_to(Vector2(c.x, c.y))
			if d >= min_c and d <= max_c:
				return cell_to_world(c)
	# fallback: any floor
	for _i in range(attempts):
		var c := center + Vector2i(rng.randi_range(-max_c, max_c), rng.randi_range(-max_c, max_c))
		if grid.get(c, false):
			return cell_to_world(c)
	return world_pos

func _build_chunk_mesh(chunk: Vector2i, origin: Vector2i, cgs: int, root: Node3D) -> void:
	# Build floor and ceiling as combined boxes per chunk for simplicity, and walls per wall-cell
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	root.add_child(floor_body)

	var ceil_body := StaticBody3D.new()
	ceil_body.name = "Ceiling"
	ceil_body.collision_layer = 1
	ceil_body.collision_mask = 0
	root.add_child(ceil_body)

	# We'll create individual floor/ceiling tiles for open cells and wall boxes for wall cells.
	# For performance in a simple project this is acceptable; merging would be better but more code.
	for z in range(cgs):
		for x in range(cgs):
			var gc := origin + Vector2i(x, z)
			var is_f: bool = grid.get(gc, false)
			var pos := cell_to_world(gc)
			if is_f:
				_add_floor_tile(floor_body, pos)
				_add_ceiling_tile(ceil_body, pos)
				_maybe_add_decor(root, gc, pos)
			else:
				# Only add wall if adjacent to any floor (visible wall)
				var adjacent_floor := false
				for d4 in DIRS_4:
					if grid.get(gc + d4, false):
						adjacent_floor = true
						break
				if adjacent_floor:
					_add_wall(root, pos)

func _add_floor_tile(parent: StaticBody3D, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(cell_size, 0.3, cell_size)
	mesh.mesh = box
	mesh.material_override = floor_mat
	mesh.position = Vector3(pos.x, -0.15, pos.z)
	parent.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = mesh.position
	parent.add_child(col)

func _add_ceiling_tile(parent: StaticBody3D, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(cell_size, 0.3, cell_size)
	mesh.mesh = box
	mesh.material_override = ceiling_mat
	mesh.position = Vector3(pos.x, wall_height + 0.15, pos.z)
	parent.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = mesh.position
	parent.add_child(col)

	# Occasional dim ceiling light
	var h := _hash_cell(Vector2i(int(pos.x / cell_size), int(pos.z / cell_size)))
	if h % 17 == 0:
		var light := OmniLight3D.new()
		light.position = Vector3(pos.x, wall_height - 0.2, pos.z)
		light.light_color = Color(0.55, 0.58, 0.5)
		light.light_energy = 0.18
		light.omni_range = 7.0
		light.shadow_enabled = false
		parent.add_child(light)

func _add_wall(parent: Node3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(pos.x, wall_height / 2.0, pos.z)
	parent.add_child(body)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(cell_size, wall_height, cell_size)
	mesh.mesh = box
	mesh.material_override = wall_mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)

	# Add occasional pipe/decor on wall face
	var h := _hash_cell(Vector2i(int(pos.x / cell_size), int(pos.z / cell_size)))
	if h % 11 == 0:
		var pipe := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = wall_height
		pipe.mesh = cyl
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.18, 0.19, 0.2)
		pmat.metallic = 0.7
		pmat.roughness = 0.5
		pipe.material_override = pmat
		pipe.position = Vector3(cell_size * 0.35, 0.0, cell_size * 0.35)
		body.add_child(pipe)

func _maybe_add_decor(root: Node3D, gc: Vector2i, pos: Vector3) -> void:
	var h := _hash_cell(gc)
	# Small floor debris
	if h % 13 == 0:
		var debris := MeshInstance3D.new()
		var box := BoxMesh.new()
		var s := 0.2 + float(h % 10) * 0.03
		box.size = Vector3(s, s * 0.4, s * 0.8)
		debris.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.1, 0.09)
		m.roughness = 1.0
		debris.material_override = m
		debris.position = Vector3(pos.x + float(h % 7) * 0.1 - 0.3, 0.03, pos.z + float(h % 5) * 0.1 - 0.2)
		debris.rotation.y = float(h % 360) * 0.01745
		root.add_child(debris)

func _spawn_interactables(chunk: Vector2i, origin: Vector2i, cgs: int, local: Dictionary, rng: RandomNumberGenerator, root: Node3D) -> void:
	var floor_cells: Array[Vector2i] = []
	for z in range(1, cgs - 1):
		for x in range(1, cgs - 1):
			if local.get(Vector2i(x, z), false):
				floor_cells.append(Vector2i(x, z))
	floor_cells.shuffle()
	var placed_lockers := 0
	var placed_batteries := 0
	var max_lockers := 2
	var max_batteries := rng.randi_range(1, 3)

	for lc in floor_cells:
		var gc := origin + lc
		var world_pos := cell_to_world(gc)
		# Don't spawn too close to origin spawn area
		if gc.length() < 3:
			continue

		# Locker placement: adjacent to a wall, facing into corridor
		if placed_lockers < max_lockers and locker_scene != null:
			var wall_dir := _find_wall_dir(local, lc)
			if wall_dir != Vector2i.ZERO:
				var locker = locker_scene.instantiate()
				root.add_child(locker)
				locker.global_position = world_pos + Vector3(wall_dir.x, 0, wall_dir.y) * (cell_size * 0.35)
				# Face into the room (opposite of wall)
				var face_dir := Vector2(-wall_dir.x, -wall_dir.y)
				if face_dir.length() > 0.01:
					locker.rotation.y = atan2(face_dir.x, face_dir.y)
				placed_lockers += 1
				continue

		if placed_batteries < max_batteries and battery_scene != null:
			if rng.randf() < 0.15:
				var bat = battery_scene.instantiate()
				root.add_child(bat)
				bat.global_position = world_pos + Vector3(rng.randf_range(-0.6, 0.6), 0.05, rng.randf_range(-0.6, 0.6))
				if bat.has_method("set_random_charge"):
					bat.set_random_charge(rng)
				placed_batteries += 1

func _find_wall_dir(local: Dictionary, lc: Vector2i) -> Vector2i:
	for d in DIRS_4:
		if not local.get(lc + d, false):
			# also ensure opposite side is open so it faces corridor
			if local.get(lc - d, false):
				return d
	return Vector2i.ZERO

func _hash_cell(c: Vector2i) -> int:
	var h: int = int(GameManager.run_seed) ^ (c.x * 374761393) ^ (c.y * 668265263)
	h = (h ^ (h >> 13)) * 1274126177
	return abs(h ^ (h >> 16))

func get_spawn_position() -> Vector3:
	# Ensure origin area is generated
	_update_chunks(Vector2i.ZERO, true)
	_process_pending_chunks()
	# Find nearest floor to origin
	var c := _nearest_floor_cell(Vector2i.ZERO)
	return cell_to_world(c) + Vector3(0, 0.1, 0)
