extends Node
class_name PiecePlacer

@onready var grid: Grid = get_parent()

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

## Verifies active safety variables before committing structures to the master coordinate index
func _try_place_piece_at_cursor() -> void:
	if current_grid_pos.x == -1: return
	if not current_placement_valid:
		_handle_placement_failure()
		return
		
	_update_grid_matrix_database()
	_spawn_physical_blocks()
	_handle_placement_success()
	grid.update_grid_line_network(self)

## Emits notification detailing a rejected action state back to core buses
func _handle_placement_failure() -> void:
	var projected_height = current_grid_pos.y + current_size.y
	var fail_coords = Vector3i(current_grid_pos.x, projected_height, current_grid_pos.z)
	EventBus.block_placed.emit(fail_coords, current_size, false)

## Accesses the primary grid data fields to modify heights over target coordinate zones
func _update_grid_matrix_database() -> void:
	for x in range(current_grid_pos.x, current_grid_pos.x + current_size.x):
		for z in range(current_grid_pos.z, current_grid_pos.z + current_size.z):
			var original_height = grid.get_height_at(x, z)
			grid.set_height_at(x, z, original_height + current_size.y)

## Commands the grid module to instantiate meshes over altered locations
func _spawn_physical_blocks() -> void:
	for x in range(current_grid_pos.x, current_grid_pos.x + current_size.x):
		for z in range(current_grid_pos.z, current_grid_pos.z + current_size.z):
			var target_height = grid.get_height_at(x, z)
			grid.spawn_visual_tile(x, target_height, z, self)

## Dispatches confirmations alerting listeners to successful element instantiation tasks
func _handle_placement_success() -> void:
	var final_height = grid.get_height_at(current_grid_pos.x, current_grid_pos.z)
	var final_coords = Vector3i(current_grid_pos.x, final_height, current_grid_pos.z)
	EventBus.block_placed.emit(final_coords, current_size, true)
