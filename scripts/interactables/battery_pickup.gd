extends Node3D

@export var charge: float = 100.0
var _collected: bool = false
var _bob_t: float = 0.0
var _base_y: float = 0.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var area: Area3D = $Area3D

func _ready() -> void:
	add_to_group("interactable")
	_base_y = mesh.position.y if mesh else 0.05
	_bob_t = randf() * TAU
	_setup_mesh()

func _setup_mesh() -> void:
	if mesh == null:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = 0.12
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	# Color hint by charge
	var t := clampf(charge / 100.0, 0.0, 1.0)
	mat.albedo_color = Color(0.15, 0.2, 0.12).lerp(Color(0.2, 0.6, 0.25), t)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.4, 0.15) * (0.2 + 0.3 * t)
	mat.metallic = 0.3
	mat.roughness = 0.5
	mesh.material_override = mat

func set_random_charge(rng: RandomNumberGenerator) -> void:
	var roll := rng.randf()
	if roll < 0.2:
		charge = rng.randf_range(15.0, 35.0)
	elif roll < 0.5:
		charge = rng.randf_range(35.0, 65.0)
	elif roll < 0.8:
		charge = rng.randf_range(65.0, 90.0)
	else:
		charge = rng.randf_range(90.0, 100.0)
	if is_node_ready():
		_setup_mesh()

func _process(delta: float) -> void:
	if _collected:
		return
	_bob_t += delta * 2.0
	if mesh:
		mesh.position.y = _base_y + sin(_bob_t) * 0.03
		mesh.rotation.y += delta * 1.2

func get_interact_prompt() -> String:
	if _collected:
		return ""
	return "Подобрать батарейку [E]"

func interact(player: Node) -> void:
	if _collected:
		return
	_collected = true
	GameManager.add_battery(charge)
	AudioSynth.play_3d("battery_pickup", global_position, -8.0, 1.0, get_parent())
	GameManager.set_prompt("Батарейка подобрана (%d%%)" % int(charge))
	# brief hide
	visible = false
	if area:
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
	await get_tree().create_timer(1.0).timeout
	queue_free()
