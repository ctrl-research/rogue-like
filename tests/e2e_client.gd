extends Node
## Entry scene for the e2e client instance (expects E2E_ROOM in the env).


func _ready() -> void:
	var monitor: Node = preload("res://tests/e2e_monitor.gd").new()
	monitor.role = "client"
	get_tree().root.add_child.call_deferred(monitor)
