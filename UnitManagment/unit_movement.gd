extends TileHandler
class_name UnitMovement

@export var unit_manager: UnitManager

func _ready():
	super._ready()
	
	# Fallback: check if parent can be used
	if not unit_manager:
		unit_manager = get_parent() as UnitManager
	# Failure state: neither inspector nor parent provided a UnitManager
	if not unit_manager:
		push_error("UnitMovement: Missing 'unit_manager' assignment and parent '%s' is not a UnitManager." % get_parent().name)
		return

func _can_handle_mode() -> bool:
	if not unit_manager.selected_pawn:
		return false
	if Global.current_mode == GData.GameMode.PLAY:
		return true
	return super._can_handle_mode()
	

func _execute_action(request_coord: Vector2i, _height = null) -> void:
	EventBus.pawn_move_requested.emit(unit_manager.selected_pawn, request_coord)


func _handle_action_failure() -> void:
	var fail_coords = Vector2i(current_grid_pos.x, current_grid_pos.z)
	EventBus.pawn_moved.emit(unit_manager.selected_pawn, fail_coords, false)
