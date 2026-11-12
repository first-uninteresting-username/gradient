extends Node
## Palette, shared materials and environment settings (glow, fog, tonemap).

signal changed

const BACKGROUND := Color("#05070F")
const PALETTES := {
	"default": {
		"line": Color("#2CF6FF"), "far": Color("#8A5CFF"),
		"hazard": Color("#FF5A1F"), "stripes": false,
		"rim": Color("#2CF6FF"),
	},
	"colorblind": {
		"line": Color("#FFD60A"), "far": Color("#B8A040"),
		"hazard": Color("#FFFFFF"), "stripes": true,
		"rim": Color("#FFD60A"),
	},
}

var track_material: ShaderMaterial
var hazard_material: ShaderMaterial
var ball_material: ShaderMaterial
var gate_material: StandardMaterial3D
var shard_material: StandardMaterial3D
var shard_rim_material: StandardMaterial3D
var unit_box: BoxMesh
var pillar_mesh: BoxMesh
var _decor: Array[StandardMaterial3D] = []
var _env: Environment


func _ready() -> void:
	unit_box = BoxMesh.new()
	unit_box.size = Vector3.ONE
	pillar_mesh = BoxMesh.new()
	pillar_mesh.size = Vector3(0.12, 1.0, 0.12)
	track_material = ShaderMaterial.new()
	track_material.shader = preload("res://shaders/grid.gdshader")
	hazard_material = ShaderMaterial.new()
	hazard_material.shader = preload("res://shaders/hazard.gdshader")
	ball_material = ShaderMaterial.new()
	ball_material.shader = preload("res://shaders/ball.gdshader")
	gate_material = _emissive(Color.WHITE, 2.0)
	shard_material = _emissive(Color.WHITE, 2.5)
	shard_rim_material = _emissive(Color.WHITE, 3.0)
	for i in 8:
		_decor.append(_emissive(Color.WHITE, 1.6))
	Save.setting_changed.connect(func(_k: String, _v: Variant) -> void: apply())
	apply()


func palette() -> Dictionary:
	return PALETTES.get(String(Save.get_setting("palette")), PALETTES["default"])


func decor_material(tint: int) -> StandardMaterial3D:
	return _decor[clampi(tint, 0, _decor.size() - 1)]


func make_hazard_instance_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = hazard_material.shader
	apply_hazard_params(m)
	return m


func apply_hazard_params(m: ShaderMaterial) -> void:
	var p := palette()
	var hc := bool(Save.get_setting("high_contrast"))
	m.set_shader_parameter(&"color", p["hazard"])
	m.set_shader_parameter(&"stripes", p["stripes"])
	m.set_shader_parameter(&"energy", 4.5 if hc else 3.0)
	m.set_shader_parameter(&"fill", 0.6 if hc else 0.35)


## Registers the run's Environment so settings can update glow and fog.
func configure_environment(env: Environment) -> void:
	_env = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.3)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = BACKGROUND
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_sky_affect = 0.0
	apply()


func apply() -> void:
	if track_material == null:
		return
	var p := palette()
	var hc := bool(Save.get_setting("high_contrast"))
	var low_glow := bool(Save.get_setting("reduced_glow"))
	track_material.set_shader_parameter(&"line_color", p["line"])
	track_material.set_shader_parameter(&"far_color", p["far"].lerp(p["line"], 0.5) if hc else p["far"])
	track_material.set_shader_parameter(&"line_width", 0.06 if hc else 0.035)
	track_material.set_shader_parameter(&"energy", 3.2 if hc else 2.2)
	track_material.set_shader_parameter(&"fill_color", Color(0, 0, 0) if hc else Color(0.012, 0.02, 0.05))
	apply_hazard_params(hazard_material)
	ball_material.set_shader_parameter(&"rim_color", p["rim"])
	gate_material.emission = p["line"]
	shard_rim_material.emission = p["rim"]
	for i in _decor.size():
		var c: Color = p["line"].lerp(p["far"], float(i) / (_decor.size() - 1))
		_decor[i].emission = c
		_decor[i].emission_energy_multiplier = 0.9 if hc else 1.6
	if _env != null:
		_env.glow_intensity = 0.25 if low_glow else 0.9
		_env.glow_bloom = 0.0 if low_glow else 0.05
		_env.fog_density = 0.006 if hc else 0.011
	changed.emit()


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m
