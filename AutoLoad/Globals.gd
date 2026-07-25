extends Node

var current_mode: GData.GameMode = GData.GameMode.BUILD
var current_play_mode: GData.PlayMode = GData.PlayMode.SELECT
var current_build_mode: GData.BuildMode = GData.BuildMode.ADD



## Switches active mode between ADD and REMOVE, broadcasting the result globally.
func switch_build_mode(mode = null) -> void:
	if mode != null:
		current_build_mode = mode
	else:
		if current_build_mode == GData.BuildMode.ADD:
			current_build_mode = GData.BuildMode.REMOVE
		else:
			current_build_mode = GData.BuildMode.ADD
		
	EventBus.build_mode_changed.emit(current_build_mode)

## Switches active mode between PLAY, BUILD, MENU and NONE, broadcasting the result globally.
func switch_game_mode(mode = null) -> void:
	if mode != null:
		current_mode = mode
	else:
		# Cycle sequentially through all available enum values
		var all_modes: Array = GData.GameMode.values()
		var current_index: int = all_modes.find(current_mode)
		var next_index: int = (current_index + 1) % all_modes.size()
		
		current_mode = all_modes[next_index]


func grid_to_world(grid_pos: Vector2i, height: int = 0) -> Vector3:
	var world_x = grid_pos.x * GData.CELL_SIZE + (GData.CELL_SIZE / 2.0)
	var world_y = height * GData.CELL_SIZE
	var world_z = grid_pos.y * GData.CELL_SIZE + (GData.CELL_SIZE / 2.0)
	return Vector3(world_x, world_y, world_z)

func pos_to_grid(world_pos: Vector3) -> Vector2i:
	var grid_x = int(floor(world_pos.x / GData.CELL_SIZE))
	var grid_z = int(floor(world_pos.y / GData.CELL_SIZE)) # Or world_pos.z depending on your 3D plane layout
	return Vector2i(grid_x, grid_z)
