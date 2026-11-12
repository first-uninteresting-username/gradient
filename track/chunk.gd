class_name Chunk
extends Node3D
## Base class for every chunk scene. The scene carries its ChunkInfo; geometry, the
## Entry/Exit markers, the centreline Path3D, hazards and score gates are built from it.

signal gate_passed

const HazardBlock := preload("res://track/hazards/static_block.tscn")
const HazardSlider := preload("res://track/hazards/slider.tscn")
const HazardRiser := preload("res://track/hazards/riser.tscn")
const ScoreGateScene := preload("res://track/hazards/score_gate.tscn")

@export var info: ChunkInfo

var spec: ChunkSpec
var data: Dictionary
var length: float = 0.0
var start_distance: float = 0.0
var exit_transform := Transform3D.IDENTITY
var entry: Marker3D
var exit: Marker3D
var path: Path3D
## Floor + wall collision; parented to the generator's floor body, not to the chunk.
var floor_shape: CollisionShape3D
var moving_hazards: Array[MovingHazard] = []
var hazard_bodies: Array[CollisionObject3D] = []
var _hint: int = 0


func build(p_spec: ChunkSpec) -> void:
	spec = p_spec
	data = TrackGeometry.get_samples(info)
	length = float(data["length"])
	start_distance = spec.start_distance
	exit_transform = data["exit"]

	entry = Marker3D.new()
	entry.name = "Entry"
	add_child(entry)
	exit = Marker3D.new()
	exit.name = "Exit"
	exit.transform = exit_transform
	add_child(exit)

	path = Path3D.new()
	path.name = "Path"
	var curve := Curve3D.new()
	var pos: PackedVector3Array = data["pos"]
	for i in range(0, pos.size(), 4):
		curve.add_point(pos[i])
	if (pos.size() - 1) % 4 != 0:
		curve.add_point(pos[pos.size() - 1])
	path.curve = curve
	add_child(path)

	var built := TrackGeometry.get_mesh(info)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Track"
	mesh_instance.mesh = built["mesh"]
	mesh_instance.material_override = Look.track_material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

	# One merged concave shape per chunk. The generator hosts every chunk's shape on a
	# single streamed floor body so Jolt's internal-edge removal also covers the joins.
	floor_shape = CollisionShape3D.new()
	floor_shape.name = "Floor%d_%s" % [spec.index, info.id]
	floor_shape.shape = built["shape"]

	_build_launch_volumes()
	_build_hazards()
	_build_gates()
	_build_decor()


func frame_at(offset: float) -> Transform3D:
	return TrackGeometry.frame_at(data, offset)


func global_frame_at(offset: float) -> Transform3D:
	return global_transform * TrackGeometry.frame_at(data, offset)


func curvature_at(offset: float) -> float:
	return TrackGeometry.curvature_at(data, offset)


## Offset of a world point along this chunk (may be < 0 or > length when outside).
func locate(world_pos: Vector3) -> float:
	var local := global_transform.affine_inverse() * world_pos
	var r := TrackGeometry.locate(data, local, _hint)
	_hint = int(r.y)
	return r.x


func kill_plane_y_at(offset: float) -> float:
	var o := clampf(offset, 0.0, length)
	var local_min := TrackGeometry.floor_min_y(data, o)
	var frame := TrackGeometry.frame_at(data, o)
	# floor_min_y is local; convert by the chunk transform's vertical offset.
	return (global_transform * Vector3(frame.origin.x, local_min, frame.origin.z)).y


func is_launch_at(offset: float) -> bool:
	var i := TrackGeometry.sample_index(data, offset) + 1
	var launch: PackedByteArray = data["launch"]
	return i < launch.size() and launch[i] == 1


func update_hazards(progress: float, speed: float, delta: float) -> void:
	for h in moving_hazards:
		h.advance(progress, speed, delta)


func _place(along: float, x: float, y: float) -> Transform3D:
	var f := frame_at(along)
	return Transform3D(f.basis, f.origin + f.basis.x * x + f.basis.y * y)


func _build_launch_volumes() -> void:
	var launch: PackedByteArray = data["launch"]
	var dist: PackedFloat32Array = data["dist"]
	var i := 1
	while i < launch.size():
		if launch[i] == 0:
			i += 1
			continue
		var start := dist[i - 1]
		while i < launch.size() and launch[i] == 1:
			i += 1
		var end := dist[i - 1]
		var area := LaunchArea.new()
		area.name = "Launch"
		var shape := BoxShape3D.new()
		shape.size = Vector3(10.0, 3.0, end - start + 1.0)
		var col := CollisionShape3D.new()
		col.shape = shape
		area.add_child(col)
		area.transform = _place((start + end) * 0.5, 0.0, 1.0)
		add_child(area)


func _build_hazards() -> void:
	for h in spec.hazards:
		var kind := String(h["kind"])
		var node: Node3D
		match kind:
			"block":
				node = HazardBlock.instantiate()
			"slider":
				node = HazardSlider.instantiate()
			"riser":
				node = HazardRiser.instantiate()
			_:
				continue
		var size := Vector3(float(h["w"]), float(h["h"]), float(h["d"]))
		node.transform = _place(float(h["along"]), float(h["x"]), size.y * 0.5)
		add_child(node)
		node.call(&"setup", size, h, start_distance + float(h["along"]))
		if node is MovingHazard:
			moving_hazards.append(node)
		hazard_bodies.append(node as CollisionObject3D)


func _build_gates() -> void:
	for along in spec.gates:
		var i := TrackGeometry.sample_index(data, along)
		var width := TrackGeometry.floor_width(data["cross"][i])
		var gate := ScoreGateScene.instantiate() as ScoreGate
		gate.transform = _place(along, 0.0, 0.0)
		add_child(gate)
		gate.setup(width)
		gate.passed.connect(func() -> void: gate_passed.emit())


func _build_decor() -> void:
	for dec in spec.decor:
		var along := float(dec["along"])
		var f := frame_at(along)
		var h := float(dec["height"])
		var pillar := MeshInstance3D.new()
		pillar.mesh = Look.pillar_mesh
		pillar.material_override = Look.decor_material(int(dec["tint"]))
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var right := f.basis.x
		right.y = 0.0
		right = right.normalized()
		var base := f.origin + right * float(dec["side"]) + Vector3.DOWN * 6.0
		pillar.transform = Transform3D(Basis().scaled(Vector3(1.0, h + 6.0, 1.0)),
			base + Vector3.UP * (h + 6.0) * 0.5)
		add_child(pillar)
