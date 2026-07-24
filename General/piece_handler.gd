extends Node
class_name PieceHandler

# ==========================================
# STATE & DATA CONTAINERS
# ==========================================

## Grid target coordinate tracking cached from cursor system updates.
var current_grid_pos: Vector3i = Vector3i(-1, -1, -1)
## Size footprint dimensions of the active piece preview.
var current_size: Vector3i = Vector3i(0, 0, 0)
## Indicates whether the cursor footprint is on a valid location.
var current_placement_valid: bool = false


# ==========================================
# LIFECYCLE & INITIALIZATION
# ==========================================

func _ready() -> void:
	_connect_signals()

## Hook to connect standard signals. Extended by child scripts if needed.
func _connect_signals() -> void:
	EventBus.preview_updated.connect(_on_preview_updated)


# ==========================================
# INPUT & MODE SWITCHING
# ==========================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_build_mode"):
		# Mark event as handled so sister nodes don't toggle it a second time in the same frame!
		get_viewport().set_input_as_handled()
		Global.switch_build_mode()
		return
	
	if event.is_action_pressed("interact"):
		# Only process interaction if this handler instance matches the active build mode
		if _can_handle_mode():
			get_viewport().set_input_as_handled()
			_try_interact_at_cursor()

## Validates targeting and routes execution if the active handler matches the current mode.
func _try_interact_at_cursor() -> void:
	if not _is_cursor_valid():
		return
		
	var request_coord := Vector2i(current_grid_pos.x, current_grid_pos.z)
	_execute_action(request_coord)


# ==========================================
# EVENT BUS LISTENERS
# ==========================================

## Keeps state updated with positioning variables received from cursor tracking systems.
func _on_preview_updated(grid_pos: Vector3i, size: Vector3i, is_valid: bool) -> void:
	current_grid_pos = grid_pos
	current_size = size
	current_placement_valid = is_valid


# ==========================================
# VALIDATION & VIRTUAL METHODS
# ==========================================

## Shared validation wrapper. Returns true if cursor position is valid.
func _is_cursor_valid() -> bool:
	if current_grid_pos.x == -1:
		return false
	if not current_placement_valid:
		_handle_action_failure()
		return false
	return true

## Virtual method: Children override this to decide what mode they can handle.
func _can_handle_mode() -> bool:
	return false
	
## Virtual method: Children override this to handle their specific action broadcasts.
func _execute_action(_map_pos: Vector2i, _height = null) -> void:
	pass

## Virtual method: Children override this to handle their specific failure broadcasts.
func _handle_action_failure() -> void:
	pass
