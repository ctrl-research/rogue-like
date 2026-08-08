extends Node
## Entry scene for every dedicated-server e2e role. Hands off to a monitor parented
## to /root, exactly as tests/e2e_host.gd does.
##
## This indirection is the whole point: the monitor changes scenes (menu -> sub ->
## game), and a node that IS the current scene gets freed the moment it does. My
## first attempt made the monitor the scene root, and all three processes went
## silent the instant they entered the sub — connected, alive, and unable to report
## anything.


func _ready() -> void:
	var monitor: Node = preload("res://tests/e2e_dedicated.gd").new()
	monitor.role = OS.get_environment("E2E_ROLE") if not OS.get_environment("E2E_ROLE").is_empty() else "server"
	get_tree().root.add_child.call_deferred(monitor)
