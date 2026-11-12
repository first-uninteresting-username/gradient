@tool
class_name ChunkInfo
extends Resource
## Metadata and authored layout for one hand-built track chunk.
##
## The layout is a list of sections. Each section is a Dictionary:
##   len      (float, required) arc length in metres
##   yaw      (deg)  heading change over the section, positive = right turn
##   pitch    (deg)  extra pitch relative to the base -18 deg at the END of the section
##   bank     (deg)  roll at the end of the section, positive = right side up
##   profile  (name) cross-section at the end of the section (morphs from the previous one)
##   drop     (m)    extra vertical drop spread over the section
##   floor    (bool) false = gap, no geometry
##   hole     [min_x, max_x] lateral range with no floor (tube holes)
##   launch   (bool) the section is a launch ramp volume
##
## Hazard slots are resolved into concrete layouts by TrackPlan using the run RNG:
##   {"type": "scatter", "from": m, "to": m}   rows of blocks in lanes
##   {"type": "slalom", "from": m, "to": m}    alternating half-width walls
##   {"type": "picket", "at": [m, ...]}
##   {"type": "slider", "at": [m, ...]}
##   {"type": "riser", "at": [m, ...]}

@export var id: StringName
@export var display_name: String = ""
@export var tags: PackedStringArray = PackedStringArray()
@export_range(1, 10) var difficulty: int = 1
@export var weight: float = 1.0
@export var min_speed: float = 0.0
@export var max_speed: float = 1000.0
@export var length: float = 0.0
@export var entry_profile: StringName = &"flat_wide"
@export var exit_profile: StringName = &"flat_wide"
## Adapters only change the cross-section between profiles.
@export var adapter: bool = false
@export var sections: Array = []
@export var hazard_slots: Array = []
## Distance between score gates on plain chunks (0 = none).
@export var gate_spacing: float = 25.0


func has_tag(tag: StringName) -> bool:
	return tags.has(String(tag))


func is_breather() -> bool:
	return has_tag(&"breather") and hazard_slots.is_empty()
