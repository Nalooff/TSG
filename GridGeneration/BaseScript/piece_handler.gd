extends Node
class_name PieceHandler

var current_grid_pos: Vector3i = Vector3i(-1, -1, -1)
var current_size: Vector3i = Vector3i(0, 0, 0)
var current_placement_valid: bool = false

func _ready() -> void:
	_connect_signals()

## Hook to connect standard signals. Can be extended by children using super()
func _connect_signals() -> void:
	EventBus.preview_updated.connect(_on_preview_updated)

## Keeps state updated with positioning variables received from the cursor tracking systems
func _on_preview_updated(grid_pos: Vector3i, size: Vector3i, is_valid: bool) -> void:
	current_grid_pos = grid_pos
	current_size = size
	current_placement_valid = is_valid

## Shared validation wrapper. Returns true if cursor position is valid.
func _is_cursor_valid() -> bool:
	if current_grid_pos.x == -1:
		return false
	if not current_placement_valid:
		_handle_action_failure()
		return false
	return true

## Virtual method: Children must override this to handle their specific failures
func _handle_action_failure() -> void:
	pass
