extends PieceHandler
class_name PieceRemover

#func _unhandled_input(event: InputEvent) -> void:
#	if event.is_action_pressed("remove_piece"):
#		_try_remove_piece_at_cursor()

func _try_remove_piece_at_cursor() -> void:
	if not _is_cursor_valid(): return
		
	var request_coord = Vector2i(current_grid_pos.x, current_grid_pos.z)
	#_execute_decoupled_removal(request_coord, current_size)


## Specific failure logic for removing (keeps current layer height)
func _handle_action_failure() -> void:
	var fail_coords = Vector3i(current_grid_pos.x, current_grid_pos.y, current_grid_pos.z)
	EventBus.block_placed.emit(fail_coords, current_size, false)
