class_name ScoreGate
extends Area3D
## +1 when the ball passes through the volume. The volume hugs the floor, so flying
## over the gate does not count.

signal passed

const HEIGHT := 2.0
const DEPTH := 1.0

var counted := false
var _bar: MeshInstance3D


func setup(width: float) -> void:
	collision_layer = 0
	collision_mask = Layers.BALL
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, HEIGHT, DEPTH)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(col)
	_bar = MeshInstance3D.new()
	_bar.mesh = Look.unit_box
	_bar.scale = Vector3(width, 0.04, 0.12)
	_bar.position = Vector3(0.0, 0.03, 0.0)
	_bar.material_override = Look.gate_material
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if counted or not (body is Ball) or not (body as Ball).alive:
		return
	counted = true
	_bar.visible = false
	passed.emit()
