@tool
class_name ChunkValidationReport
extends RefCounted
## Validates every chunk scene on disk. Shared by the editor plugin, the
## File > Run script (tools/validate_chunks.gd) and the test suite.


static func run() -> Dictionary:
	var errors := PackedStringArray()
	var count := 0
	for f in DirAccess.get_files_at(ChunkCatalogue.DIR):
		var clean := f.trim_suffix(".remap")
		if not clean.ends_with(".tscn"):
			continue
		count += 1
		var scene := ResourceLoader.load(ChunkCatalogue.DIR + clean, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if scene == null:
			errors.append("%s: failed to load" % clean)
			continue
		var state := scene.get_state()
		var info: ChunkInfo = null
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"info":
				info = state.get_node_property_value(0, i) as ChunkInfo
		errors.append_array(ChunkValidator.validate(info, clean.get_basename()))
	return {"count": count, "errors": errors}
