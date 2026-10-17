extends PawnComponent
class_name CombatComponent

@export_group("Combat Stats")
## Array of valid attack distance intervals as Vector2i(min, max). Use -1 for max to represent Infinity.
@export var attack_ranges: Array[Vector2i] = [Vector2i(1, 1)]:
	set(value):
		attack_ranges = _validate_and_sort_ranges(value)

## Validates and formats ranges according to your rules
func _validate_and_sort_ranges(ranges: Array[Vector2i]) -> Array[Vector2i]:
	var cleaned: Array[Vector2i] = []
	
	# 1. Sort ranges by their start value (x)
	var sorted_ranges = ranges.duplicate()
	sorted_ranges.sort_custom(func(a, b): return a.x < b.x)
	
	for r in sorted_ranges:
		var min_v = r.x
		var max_v = r.y
		
		# Rule: x can never be -1 (infinity)
		if min_v == -1:
			min_v = 1 # Fallback to a safe minimum

		# Rule: current vector.x must be smaller than current vector.y (unless y is -1 for infinity)
		if max_v != -1 and min_v >= max_v:
			max_v = min_v + 1
			
		if cleaned.is_empty():
			cleaned.append(Vector2i(min_v, max_v))
		else:
			var prev = cleaned.back()
			# Rule: next vector.x must be bigger or equal than previous vector.y
			if min_v < prev.y:
				min_v = prev.y
				# Re-validate min < max after shifting (unless max is -1)
				if max_v != -1 and min_v >= max_v:
					max_v = min_v + 1
					
			cleaned.append(Vector2i(min_v, max_v))
			
		# If this current range hits infinity, stop adding further elements
		if max_v == -1:
			break
	if cleaned != ranges:
		push_warning("The array of attack_ranges is not set correctly; it has automatically been cleaned and sorted.")
	
	return cleaned

## Returns an array of all enemy pawns within valid attack ranges and line of sight.
func get_attackable_enemies(board_state: BoardState) -> Array[BasePawn]:
	var attackable: Array[BasePawn] = []
	
	var max_query_range = 0
	for r in attack_ranges:
		var upper = r.y if r.y != -1 else max(board_state.width, board_state.depth)
		if upper > max_query_range:
			max_query_range = upper
			
	var nearby_enemies = board_state.get_adjacent_pawns(pawn.grid_pos, max_query_range, pawn.team_id, true)
	
	for target in nearby_enemies:
		if can_attack(board_state, target):
			attackable.append(target)
			
	return attackable

func can_attack(board_state: BoardState, target_pawn: BasePawn) -> bool:
	if target_pawn == null or target_pawn.team_id == pawn.team_id:
		return false

	var dist = max(abs(target_pawn.grid_pos.x - pawn.grid_pos.x), abs(target_pawn.grid_pos.y - pawn.grid_pos.y))
	
	var is_in_valid_range = false
	for r in attack_ranges:
		var min_d = r.x
		var max_d = r.y if r.y != -1 else 999999
		
		if dist >= min_d and dist <= max_d:
			is_in_valid_range = true
			break
			
	if not is_in_valid_range:
		return false

	if pawn.movement and not pawn.movement.has_line_of_sight(board_state, pawn.grid_pos, target_pawn.grid_pos):
		return false

	return true

func execute_attack(_board_state: BoardState, target_pawn: BasePawn) -> void:
	print("[%s] fires at [%s]!" % [pawn.name, target_pawn.name])
