class_name ChunkCatalogue
extends RefCounted
## Loads every chunk scene in res://track/chunks and exposes its ChunkInfo.

const DIR := "res://track/chunks/"

var infos: Array[ChunkInfo] = []
var by_id: Dictionary = {}
var scenes: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()


static func get_default() -> ChunkCatalogue:
	if not Engine.has_meta(&"gradient_catalogue"):
		Engine.set_meta(&"gradient_catalogue", ChunkCatalogue.new())
	return Engine.get_meta(&"gradient_catalogue")


## Drops the shared catalogue (and its scenes) so nothing is held at exit.
static func release_default() -> void:
	if Engine.has_meta(&"gradient_catalogue"):
		Engine.remove_meta(&"gradient_catalogue")


func _init() -> void:
	var files := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		# Exported builds list remapped resources as "*.tscn.remap".
		var clean := f.trim_suffix(".remap")
		if clean.ends_with(".tscn") and not files.has(clean):
			files.append(clean)
	files.sort()
	for f in files:
		var scene := load(DIR + f) as PackedScene
		if scene == null:
			errors.append("%s: failed to load" % f)
			continue
		var node := scene.instantiate()
		var info: ChunkInfo = node.get("info") if node != null else null
		if node != null:
			node.free()
		var problems := ChunkValidator.validate(info, f.get_basename())
		if not problems.is_empty():
			errors.append_array(problems)
			continue
		infos.append(info)
		by_id[info.id] = info
		scenes[info.id] = scene
	for e in errors:
		push_error("Chunk catalogue: " + e)


func get_info(id: StringName) -> ChunkInfo:
	return by_id.get(id)


func get_scene(id: StringName) -> PackedScene:
	return scenes.get(id)


func has(id: StringName) -> bool:
	return by_id.has(id)


func with_tag(tag: StringName) -> Array[ChunkInfo]:
	var out: Array[ChunkInfo] = []
	for info in infos:
		if info.has_tag(tag):
			out.append(info)
	return out


func all_tags() -> PackedStringArray:
	var out := PackedStringArray()
	for info in infos:
		for t in info.tags:
			if not out.has(t):
				out.append(t)
	out.sort()
	return out


## Shortest chain of adapter ids that turns profile `from` into `to` (empty if equal).
func adapter_path(from: StringName, to: StringName) -> Array[StringName]:
	var none: Array[StringName] = []
	if from == to:
		return none
	var queue: Array = [[from, none]]
	var seen := {from: true}
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var prof: StringName = item[0]
		var path: Array[StringName] = item[1]
		for info in infos:
			if info.adapter and info.entry_profile == prof and not seen.has(info.exit_profile):
				var next: Array[StringName] = path.duplicate()
				next.append(info.id)
				if info.exit_profile == to:
					return next
				seen[info.exit_profile] = true
				queue.append([info.exit_profile, next])
	return none
