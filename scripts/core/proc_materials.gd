class_name ProcMaterials
extends RefCounted
## Процедурные материалы: без единого внешнего ресурса.

static var _cache: Dictionary = {}


static func noise_texture(
	seed_value: int, frequency: float = 0.08, seamless: bool = true
) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = seamless
	tex.noise = noise
	return tex


static func _material(
	id: String,
	seed_value: int,
	tint: Color,
	roughness: float,
	metallic: float = 0.0,
	bump: float = 0.35,
	frequency: float = 0.08
) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id] as StandardMaterial3D
	var tex := noise_texture(seed_value, frequency)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.roughness = roughness
	mat.roughness_texture = tex
	mat.metallic = metallic
	mat.bump_enabled = true
	mat.bump_texture = tex
	mat.bump_strength = bump
	_cache[id] = mat
	return mat


static func wall() -> StandardMaterial3D:
	return _material("wall", 1337, Color(0.32, 0.34, 0.33), 0.96, 0.0, 0.38)


static func floor() -> StandardMaterial3D:
	return _material("floor", 7331, Color(0.20, 0.21, 0.22), 0.88, 0.05, 0.28, 0.11)


static func ceiling() -> StandardMaterial3D:
	return _material("ceiling", 4211, Color(0.15, 0.16, 0.17), 0.98, 0.0, 0.2)


static func rust() -> StandardMaterial3D:
	return _material("rust", 90210, Color(0.36, 0.22, 0.14), 0.78, 0.55, 0.55, 0.16)


static func metal() -> StandardMaterial3D:
	return _material("metal", 177, Color(0.28, 0.30, 0.32), 0.52, 0.75, 0.22)


static func wood() -> StandardMaterial3D:
	return _material("wood", 555, Color(0.30, 0.23, 0.17), 0.92, 0.0, 0.4, 0.05)


static func flesh() -> StandardMaterial3D:
	return _material("flesh", 66613, Color(0.13, 0.09, 0.10), 0.64, 0.08, 0.9, 0.14)


static func dark() -> StandardMaterial3D:
	if _cache.has("dark"):
		return _cache["dark"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.018, 0.019, 0.022)
	mat.roughness = 0.85
	_cache["dark"] = mat
	return mat


static func emissive(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var id := "emissive_%s_%d" % [color.to_html(false), int(energy * 100.0)]
	if _cache.has(id):
		return _cache[id] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emissive_enabled = true
	mat.emissive_color = color
	mat.emissive_energy = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[id] = mat
	return mat


static func glass() -> StandardMaterial3D:
	if _cache.has("glass"):
		return _cache["glass"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.20)
	mat.metallic = 0.25
	mat.roughness = 0.15
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_cache["glass"] = mat
	return mat


static func light_cone() -> StandardMaterial3D:
	if _cache.has("cone"):
		return _cache["cone"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.88, 0.70, 0.035)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_MODE_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache["cone"] = mat
	return mat


static func dust() -> StandardMaterial3D:
	if _cache.has("dust"):
		return _cache["dust"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.94, 0.78, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache["dust"] = mat
	return mat
