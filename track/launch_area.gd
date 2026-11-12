class_name LaunchArea
extends Area3D
## Ramp volume: the only place the ball may keep upward velocity from the floor.


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.BALL
	monitorable = false
	body_entered.connect(_on_body)


func _on_body(body: Node3D) -> void:
	if body is Ball:
		(body as Ball).arm_launch()
