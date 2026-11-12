class_name HazardBlock
extends StaticBody3D
## A static lethal block. Size comes from the generated layout.

var size := Vector3.ONE
var along_distance: float = 0.0


func setup(p_size: Vector3, _params: Dictionary, p_along: float) -> void:
	size = p_size
	along_distance = p_along
	collision_layer = Layers.HAZARD
	collision_mask = 0
	add_to_group(&"hazard")
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = Look.unit_box
	mesh.scale = size
	mesh.material_override = _material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _material() -> Material:
	return Look.hazard_material
