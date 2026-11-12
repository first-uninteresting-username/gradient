@tool
extends EditorScript
## File > Run in the script editor: validates every chunk's entry/exit profiles.


func _run() -> void:
	var report := ChunkValidationReport.run()
	for e in report["errors"]:
		push_error(e)
	print("Validated %d chunks: %d problem(s)." % [report["count"], report["errors"].size()])
