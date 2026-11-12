class_name BallTuning
extends Resource
## Ball feel. Starting values come from the spec (section 3.1).

@export var radius: float = 0.5
@export var mass: float = 1.0
@export var lateral_accel: float = 38.0
@export var lateral_damping: float = 6.0
@export var max_lateral_speed: float = 12.0
@export_range(0.0, 1.0) var air_control: float = 0.35
@export var air_gravity_multiplier: float = 1.6
@export var linear_damp: float = 0.0
@export var angular_damp: float = 0.5
## Forward speed may exceed the target by this factor before being clamped.
@export var governor_headroom: float = 1.15
## Upward speed (along the floor normal) below this is treated as a seam bump and removed.
@export var snap_max_up_speed: float = 1.5
## Remove all upward velocity off the floor (not only kicks below snap_max_up_speed)
## while the floor is within snap reach and no launch is armed. Edge kicks at joins grow
## with speed (measured ~4-6 m/s at 100-150 m/s), so the 1.5 m/s threshold alone is not
## enough at high speed.
@export var strict_snap: bool = true
## A physics step that starts this close before a chunk join gets a speculative contact
## against the next chunk's boundary edge, whose tilted normal kicks the ball upward
## (kick ~ speed x 0.1). Above join_guard_min_speed the step that would end inside this
## zone is shortened to end before it, so the following step crosses the join cleanly.
@export var join_guard_zone: float = 0.2
@export var join_guard_min_speed: float = 30.0
## Fastest the snap pulls the ball back onto the floor.
@export var snap_pull_speed: float = 12.0
## Down-ray reach below the ball's surface for snap-to-floor.
@export var snap_distance: float = 0.25
## Share of the path's turning that is felt as sideways drift (0 = on rails).
@export_range(0.0, 1.0) var centrifugal: float = 0.35
## Seconds the ramp keeps the launch flag after the ball leaves the volume.
@export var launch_grace: float = 0.4
## Time for keyboard steering to ramp from 0 to full.
@export var key_ramp_time: float = 0.06
@export var stick_deadzone: float = 0.15
