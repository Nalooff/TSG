extends Node

var current_build_mode: GData.BuildMode = GData.BuildMode.ADD
var current_mode: GData.GameMode = GData.GameMode.BUILD


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
