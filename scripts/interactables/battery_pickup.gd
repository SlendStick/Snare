class_name BatteryPickup
extends Area3D
## Батарейка со случайным (взвешенным) остатком заряда.

var charge: float = 0.6
var visual: Node3D = null
var _t: float = 0.0
var _base_height: float = 0.24


func setup(cell: Vector2i, rng: RandomNumberGenerator, in_niche: bool) -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var center := Vector3((float(cell.x) + 0.5) * 4.0, 0.0, (float(cell.y) + 0.5) * 4.0)
	var jitter := Vector3(rng.randf_range(-1.3, 1.3), 0.0, rng.randf_range(-1.3, 1.3))
	if in_niche:
		jitter += Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
	global_position = center + jitter
	global_position.y = _base_height

	charge = BatteryItem.weighted_charge(rng)

	var shape := SphereShape3D.new()
	shape.radius = 0.32
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	visual = Node3D.new()
	visual.rotation = Vector3(
		rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, TAU), rng.randf_range(-0.4, 0.4)
	)
	add_child(visual)

	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.085
	body_mesh.bottom_radius = 0.085
	body_mesh.height = 0.28
	body_mesh.radial_segments = 12
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = ProcMaterials.rust()
	visual.add_child(body)

	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.089
	band_mesh.bottom_radius = 0.089
	band_mesh.height = 0.07
	var band := MeshInstance3D.new()
	band.mesh = band_mesh
	band.material_override = ProcMaterials.metal()
	band.position.y = 0.06
	visual.add_child(band)

	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.045
	tip_mesh.bottom_radius = 0.045
	tip_mesh.height = 0.025
	var tip := MeshInstance3D.new()
	tip.mesh = tip_mesh
	tip.material_override = ProcMaterials.emissive(Color(0.9, 0.75, 0.35), 0.9)
	tip.position.y = 0.15
	visual.add_child(tip)


func _process(delta: float) -> void:
	_t += delta
	if visual:
		visual.rotation.y += delta * 0.9
		visual.position.y = sin(_t * 2.0) * 0.035


func interact_text(_player: Node) -> String:
	return "Подобрать батарейку [%d%%] [E]" % int(charge * 100.0)


func interact(player) -> void:
	if player.add_battery(charge):
		GameManager.batteries_found += 1
		AudioSynth.play_3d("battery_in", global_position, -2.0)
		queue_free()
