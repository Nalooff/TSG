extends Node
class_name PiecePlacer

@onready var grid: Grid = get_parent()

# Track data state entirely delivered through the EventBus signal
var current_grid_pos: Vector3i = Vector3i(-1, -1, -1)
var current_size: Vector3i = Vector3i(0, 0, 0)
var current_placement_valid: bool = false

func _ready() -> void:
	EventBus.preview_updated.connect(_on_preview_updated)


func _on_preview_updated(grid_pos: Vector3i, size: Vector3i, is_valid: bool) -> void:
	current_grid_pos = grid_pos
	current_size = size
	current_placement_valid = is_valid


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_piece"):
		_try_place_piece_at_cursor()


## Central orchestrator function
func _try_place_piece_at_cursor() -> void:
	# 1. State Guard Check
	if current_grid_pos.x == -1: return
	
	# 2. Safety Rule Validation
	if not current_placement_valid:
		_handle_placement_failure()
		return
		
	# 3. Process Valid Placement Actions
	_update_grid_matrix_database()
	_spawn_physical_block()
	_handle_placement_success()


## Handles notification routing and logs when placement rules are broken
func _handle_placement_failure() -> void:
	
	# Project the height where the top of the block would have landed
	var projected_height = current_grid_pos.y + current_size.y
	var fail_coords = Vector3i(current_grid_pos.x, projected_height, current_grid_pos.z)
	
	EventBus.block_placed.emit(fail_coords, current_size, false)


## Modifies the backend structural data layer array grid values
func _update_grid_matrix_database() -> void:
	for x in range(current_grid_pos.x, current_grid_pos.x + current_size.x):
		for z in range(current_grid_pos.z, current_grid_pos.z + current_size.z):
			var original_height = grid.get_height_at(x, z)
			grid.set_height_at(x, z, original_height + current_size.y)


## Handles full mesh generation, dimension layout setups, and scene placement
func _spawn_physical_block() -> void:
	var physical_block = MeshInstance3D.new()
	physical_block.mesh = BoxMesh.new()
	(physical_block.mesh as BoxMesh).size = Vector3(current_size) * grid.CELL_SIZE
	
	# Theme block based on new height profile
	var mat = StandardMaterial3D.new()
	var current_layer = clampi(grid.get_height_at(current_grid_pos.x, current_grid_pos.z), 0, 3)
	mat.albedo_color = grid.LAYER_COLORS[current_layer]
	physical_block.material_override = mat
	
	add_child(physical_block)
	physical_block.global_position = _calculate_world_position()


## Computes the geometric world position offset entirely using layout rules
func _calculate_world_position() -> Vector3:
	var offset_x = (current_size.x * grid.CELL_SIZE) / 2.0
	var offset_z = (current_size.z * grid.CELL_SIZE) / 2.0
	var terrain_surface_y = (current_grid_pos.y + 1) * grid.CELL_SIZE
	var py = terrain_surface_y + ((current_size.y * grid.CELL_SIZE) / 2.0)
	
	return Vector3(
		(current_grid_pos.x * grid.CELL_SIZE) + offset_x,
		py,
		(current_grid_pos.z * grid.CELL_SIZE) + offset_z
	)


## Emits completion signals to log progress out across telemetry channels
func _handle_placement_success() -> void:
	var final_height = grid.get_height_at(current_grid_pos.x, current_grid_pos.z)
	var final_coords = Vector3i(current_grid_pos.x, final_height, current_grid_pos.z)
	
	EventBus.block_placed.emit(final_coords, current_size, true)
