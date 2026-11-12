class_name Shatter
extends Node3D
## Replaces the ball on death with ~30 glowing shards that inherit its velocity.

const COUNT := 30
const LIFETIME := 3.0

var _age: float = 0.0


static func spawn(parent: Node, at: Vector3, velocity: Vector3, seed_value: int) -> Shatter:
	var s := Shatter.new()
	s.name = "Shatter"
	parent.add_child(s)
	s.global_position = at
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in COUNT:
		var body := RigidBody3D.new()
		body.collision_layer = Layers.SHARD
		body.collision_mask = Layers.TRACK
		body.mass = 0.05
		body.continuous_cd = true
		var size := Vector3(rng.randf_range(0.08, 0.22), rng.randf_range(0.08, 0.22), rng.randf_range(0.08, 0.22))
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		var mesh := MeshInstance3D.new()
		mesh.mesh = Look.unit_box
		mesh.scale = size
		mesh.material_override = Look.shard_material if i % 3 else Look.shard_rim_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mesh)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
		body.position = dir * rng.randf_range(0.0, 0.35)
		s.add_child(body)
		body.linear_velocity = velocity * rng.randf_range(0.6, 1.0) + dir * rng.randf_range(2.0, 7.0)
		body.angular_velocity = Vector3(rng.randf_range(-20, 20), rng.randf_range(-20, 20), rng.randf_range(-20, 20))
	return s


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
