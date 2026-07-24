extends PieceHandler
class_name PieceRemover

# ==========================================
# OVERRIDDEN ACTION HANDLERS
# ==========================================

## Evaluates whether handler handles REMOVE mode.
func _can_handle_mode() -> bool:
	if Global.current_mode != GData.GameMode.BUILD:
		return false
	if Global.current_build_mode == GData.BuildMode.REMOVE:
		return true
	return super._can_handle_mode()

## Dispatches grid removal request.
func _execute_action(request_coord: Vector2i, _height = null) -> void:
	EventBus.removal_requested.emit(request_coord, current_size)

## Specific failure logic for removing (retains target height).
func _handle_action_failure() -> void:
	var fail_coords = Vector3i(current_grid_pos.x, current_grid_pos.y, current_grid_pos.z)
	EventBus.block_removed.emit(fail_coords, current_size, false)
