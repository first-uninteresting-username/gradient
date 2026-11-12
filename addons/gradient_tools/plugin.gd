@tool
extends EditorPlugin
## Validates every chunk scene when the editor (re)imports files, so a chunk whose
## entry/exit profile does not match its geometry is reported immediately.

var _fs: EditorFileSystem


func _enter_tree() -> void:
	_fs = EditorInterface.get_resource_filesystem()
	_fs.filesystem_changed.connect(_validate)
	add_tool_menu_item("Validate GRADIENT chunks", _validate.bind(true))


func _exit_tree() -> void:
	if _fs != null and _fs.filesystem_changed.is_connected(_validate):
		_fs.filesystem_changed.disconnect(_validate)
	remove_tool_menu_item("Validate GRADIENT chunks")


func _validate(verbose: bool = false) -> void:
	var report := ChunkValidationReport.run()
	for e in report["errors"]:
		push_error("GRADIENT chunk: " + e)
	if verbose or not report["errors"].is_empty():
		print("GRADIENT: validated %d chunks, %d problem(s)." % [report["count"], report["errors"].size()])
