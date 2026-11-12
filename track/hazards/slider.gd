class_name SliderHazard
extends MovingHazard
## Slides side to side across the track.


func _pose(t: float) -> Transform3D:
	var amp := float(params.get("amp", 2.4))
	var period := float(params.get("period", 2.0))
	var phase := float(params.get("phase", 0.0))
	var x := amp * sin(TAU * t / period + phase)
	return Transform3D(base_transform.basis, base_transform.origin + base_transform.basis.x * x)
