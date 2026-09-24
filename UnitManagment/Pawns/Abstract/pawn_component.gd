extends Node
class_name PawnComponent

## Back-reference to the parent pawn
var pawn: BasePawn

func _ready() -> void:
	if pawn == null:
		pawn = get_owner() as BasePawn
		print(pawn)
		if pawn == null:
			push_error("pawn")
