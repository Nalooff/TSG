extends Node
class_name PiecePlacer

var current_grid_pos: Vector3i = Vector3i(-1, -1, -1)
var current_size: Vector3i = Vector3i(0, 0, 0)
var current_placement_valid: bool = false

func _ready() -> void:
	EventBus.preview_updated.connect(_on_preview_updated)

## Keeps state updated with positioning variables received from the cursor tracking systems
func _on_preview_updated(grid_pos: Vector3i, size: Vector3i, is_valid: bool) -> void:
	current_grid_pos = grid_pos
	current_size = size
	current_placement_valid = is_valid

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_piece"):
		_try_place_piece_at_cursor()

## Verifies active safety variables before committing structures via the global EventBus
func _try_place_piece_at_cursor() -> void:
	if current_grid_pos.x == -1: return
	if not current_placement_valid:
		_handle_placement_failure()
		return
		
	# Decoupled emission! Grid hears this and builds everything.
	var request_coord = Vector2i(current_grid_pos.x, current_grid_pos.z)
	EventBus.placement_requested.emit(request_coord, current_size)

## Emits notification detailing a rejected action state back to core buses
func _handle_placement_failure() -> void:
	var projected_height = current_grid_pos.y + current_size.y
	var fail_coords = Vector3i(current_grid_pos.x, projected_height, current_grid_pos.z)
	EventBus.block_placed.emit(fail_coords, current_size, false)
