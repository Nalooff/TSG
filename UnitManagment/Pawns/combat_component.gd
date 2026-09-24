extends PawnComponent
class_name CombatComponent

@export_group("Combat Stats")
@export var attack_range: int = 1

## Validates if this pawn can initiate an engagement with a target pawn on the board.
func can_attack(board_state: BoardState, target_pawn: BasePawn) -> bool:
	if target_pawn == null or target_pawn.team_id == pawn.team_id:
		return false

	var dist = max(abs(target_pawn.grid_pos.x - pawn.grid_pos.x), abs(target_pawn.grid_pos.y - pawn.grid_pos.y))
	if dist > attack_range:
		return false

	# Requires clear LOS via movement component check
	if pawn.movement and not pawn.movement.has_line_of_sight(board_state, pawn.grid_pos, target_pawn.grid_pos):
		return false

	return true

## Executed when moving onto/selecting an enemy unit to trigger engagement resolution.
func execute_attack(_board_state: BoardState, target_pawn: BasePawn) -> void:
	# Add damage resolution / turn combat mechanics here
	print("[%s] Attacks [%s]" % [pawn.name, target_pawn.name])
