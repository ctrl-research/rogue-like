extends Node2D
## Repair-quest objective. The server accrues repair progress while a diver
## holds position nearby (see game._tick_quest); every peer just renders the
## mirrored progress, so no extra sync is needed.

var game  # the Game node


func _ready() -> void:
	$Bar.max_value = GameRules.REPAIR_TIME


func _process(_delta: float) -> void:
	if game != null:
		$Bar.value = game.quest_progress
