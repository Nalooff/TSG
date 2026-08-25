extends TileHandler
class_name PiecePlacer

# ==========================================
# OVERRIDDEN ACTION HANDLERS
# ==========================================

## Evaluates whether handler handles ADD mode.
func _can_handle_mode() -> bool:
	if Global.current_mode != GData.GameMode.BUILD:
		return false
	if Global.current_build_mode == GData.BuildMode.ADD:
		return true
	return super._can_handle_mode()

## Dispatches grid placement request.
func _execute_action(request_coord: Vector2i, _height = null) -> void:
	EventBus.placement_requested.emit(request_coord, current_size)

## Specific failure logic for placing (projects height upward).
func _handle_action_failure() -> void:
	var projected_height = current_grid_pos.y + current_size.y
	var fail_coords = Vector3i(current_grid_pos.x, projected_height, current_grid_pos.z)
	EventBus.block_placed.emit(fail_coords, current_size, false)
