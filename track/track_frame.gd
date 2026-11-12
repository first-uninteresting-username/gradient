class_name TrackFrame
extends RefCounted
## Result of a track query at a world position.

var chunk_index: int = 0
var offset: float = 0.0
## Length of the chunk the frame lies in.
var chunk_length: float = 0.0
## Run distance along the centreline.
var progress: float = 0.0
## Global frame on the centreline floor: basis.x = right, basis.y = up, -basis.z = forward.
var transform := Transform3D.IDENTITY
var curvature: float = 0.0
var kill_y: float = 0.0
var target_speed: float = 14.0
## True while over a launch-ramp section.
var launch := false
