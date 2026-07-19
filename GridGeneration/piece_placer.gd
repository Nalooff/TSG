extends PieceHandler
class_name PiecePlacer

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_piece"):
		_try_place_piece_at_cursor()

func _try_place_piece_at_cursor() -> void:
	# Calls the parent method to check if the cursor state is valid
	if not _is_cursor_valid(): return
		
	# Decoupled emission! Grid hears this and builds everything.
	var request_coord = Vector2i(current_grid_pos.x, current_grid_pos.z)
	EventBus.placement_requested.emit(request_coord, current_size)

## Specific failure logic for placing (projects height upward)
func _handle_action_failure() -> void:
	var projected_height = current_grid_pos.y + current_size.y
	var fail_coords = Vector3i(current_grid_pos.x, projected_height, current_grid_pos.z)
	EventBus.block_placed.emit(fail_coords, current_size, false)
