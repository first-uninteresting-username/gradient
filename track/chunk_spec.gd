class_name ChunkSpec
extends RefCounted
## One generated chunk: which chunk, where it sits in the run and its resolved
## hazard layout. Produced by TrackPlan without touching the scene tree.

var index: int = 0
var id: StringName
var start_distance: float = 0.0
var length: float = 0.0
var difficulty: float = 1.0
var target_speed: float = 0.0
## True when this chunk was inserted by the breather rule.
var forced_breather: bool = false
## 0 = normal pick; >0 = which relaxation was needed to find a candidate.
var fallback: int = 0
## Marks the run-out after the last chunk of a non-looping custom track.
var finish: bool = false
## Resolved hazards: {"kind": "block"/"slider"/"riser", "along", "x", "w", "h", "d", ...}
var hazards: Array[Dictionary] = []
## Score gate positions (metres along the chunk).
var gates: PackedFloat32Array = PackedFloat32Array()
## Decorative pillars: {"along", "side", "height", "tint"}
var decor: Array[Dictionary] = []


func to_dict() -> Dictionary:
	return {
		"index": index,
		"id": String(id),
		"start_distance": start_distance,
		"length": length,
		"difficulty": difficulty,
		"target_speed": target_speed,
		"forced_breather": forced_breather,
		"fallback": fallback,
		"finish": finish,
		"hazards": hazards.duplicate(true),
		"gates": Array(gates),
		"decor": decor.duplicate(true),
	}


func equals(other: ChunkSpec) -> bool:
	return other != null and var_to_str(to_dict()) == var_to_str(other.to_dict())
