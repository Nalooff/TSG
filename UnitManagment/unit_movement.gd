extends TileHandler
class_name UnitMovement

@export var unit_manager: UnitManager

func _ready() -> void:
	# Do not call super._ready() to avoid binding to block preview updates
	EventBus.tile_hovered.connect(_on_tile_hovered)
	
	if not unit_manager:
		unit_manager = get_parent() as UnitManager
	if not unit_manager:
		push_error("UnitMovement: Missing 'unit_manager' assignment and parent '%s' is not a UnitManager." % get_parent().name)

## Updates position directly from mouse tile hovers
func _on_tile_hovered(data: Dictionary) -> void:
	var pos_2d: Vector2i = data.grid_pos
	current_grid_pos = Vector3i(pos_2d.x, 0, pos_2d.y)

func _can_handle_mode() -> bool:
	if not unit_manager or not unit_manager.selected_pawn:
		return false
	return Global.current_mode == GData.GameMode.PLAY

func _is_cursor_valid() -> bool:
	return current_grid_pos.x != -1

func _execute_action(request_coord: Vector2i, _height = null) -> void:
	EventBus.pawn_move_requested.emit(unit_manager.selected_pawn, request_coord)

func _handle_action_failure() -> void:
	var fail_coords = Vector2i(current_grid_pos.x, current_grid_pos.z)
	EventBus.pawn_moved.emit(unit_manager.selected_pawn, fail_coords, false)
