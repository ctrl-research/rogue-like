extends Node
## Entry scene for the e2e host instance. Hands off to a monitor parented to
## /root so the logic survives scene changes.


func _ready() -> void:
	var monitor: Node = preload("res://tests/e2e_monitor.gd").new()
	monitor.role = "host"
	get_tree().root.add_child.call_deferred(monitor)
