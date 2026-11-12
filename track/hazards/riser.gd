class_name RiserHazard
extends MovingHazard
## Rises out of the floor and sinks back. While "down" its top sits below the floor.

const DOWN_OFFSET := -2.5


func _pose(t: float) -> Transform3D:
	var period := float(params.get("period", 2.2))
	var phase := float(params.get("phase", 0.0))
	var s := 0.5 - 0.5 * cos(TAU * t / period + phase)
	var y := lerpf(DOWN_OFFSET, 0.0, s)
	return Transform3D(base_transform.basis, base_transform.origin + base_transform.basis.y * y)
