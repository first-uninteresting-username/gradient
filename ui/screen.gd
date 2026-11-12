class_name Screen
extends Control
## Base for full-screen UI pages. `navigate` asks main.gd to switch pages.

signal navigate(to: String)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


## Called when the page becomes visible.
func opened() -> void:
	pass


func focus_first(node: Control) -> void:
	if is_inside_tree() and node.is_visible_in_tree():
		node.grab_focus.call_deferred()
