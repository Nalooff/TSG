extends Node3D

@export var rotation_speed : float = 0.01

@export_group("Nodes")
@export var cam3D_view2D : Camera3D
@export var cam3D_view3D : Camera3D

@export_group("Orthogonal Settings")
## Base uniform space around the grid edges so it's not crammed against the screen boundaries.
@export var grid_padding : float = 2.0

@export_subgroup("Extra 2D Grid Padding", "padding")
## Additional padding added on top of the base grid_padding.
@export var padding_up : float 
@export var padding_down : float 
@export var padding_left : float 
@export var padding_right : float 

var _cam3D_offset = Vector3(0.0, 20.0, 27.0)
var _cam2D_offset = Vector3(0, 30, 0)

var _current_cam : Camera3D:
	set(value):
		_current_cam = value
		EventBus.camera_changed.emit(value)

# Called when the node enters the scene tree for the first time.
func _ready():
	_setup_cams(GlobalData.GRID_CENTER)
	swap_cameras(cam3D_view3D)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	_handle_keyboard_rotation(_delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("change_view"):
		swap_cameras()
		
	_handle_mouse_rotation(event)


func swap_cameras(cam : Camera3D = null) -> void:
	if cam:
		cam.make_current()
		_current_cam = cam
		return
	
	if cam3D_view3D.current:
		cam3D_view2D.make_current()
		_current_cam = cam3D_view2D
		print("Swapped to Flat 2D View!")
	else:
		cam3D_view3D.make_current()
		_current_cam = cam3D_view3D
		print("Swapped to Perspective 3D View!")


# ==============================================================================
# CAMERA ROTATION DETECTORS
# ==============================================================================

func _handle_mouse_rotation(event: InputEvent) -> void:
	if not cam3D_view3D.current:
		return

	# Drag-rotate: Mouse moves while the action button is held down
	if event is InputEventMouseMotion and Input.is_action_pressed("rotate_cam"):
		# Directly rotate the offset vector on the Y-axis
		var y_rotation_angle = -event.relative.x * rotation_speed
		_cam3D_offset = _cam3D_offset.rotated(Vector3.UP, y_rotation_angle)
		
		_update_perspective_position(GlobalData.GRID_CENTER)


func _handle_keyboard_rotation(delta: float) -> void:
	if not cam3D_view3D.current or Input.is_action_pressed("rotate_cam"):
		return

	# Rebindable keyboard fallback (e.g. Left/Right Arrow keys or A/D)
	var rotation_input = Input.get_axis("rotate_left", "rotate_right")
	if rotation_input != 0.0:
		# Use a standard multiplier scale (e.g. 2.0 radians) for smooth key transitions
		var keyboard_speed_multiplier = 2.0
		var y_rotation_angle = rotation_input * keyboard_speed_multiplier * delta
		_cam3D_offset = _cam3D_offset.rotated(Vector3.UP, y_rotation_angle)
		
		_update_perspective_position(GlobalData.GRID_CENTER)


func _update_perspective_position(target_center: Vector3) -> void:
	cam3D_view3D.global_position = target_center + _cam3D_offset
	cam3D_view3D.look_at(target_center, Vector3.UP)


# ==============================================================================
# CAMERA INITIAL SETUP
# ==============================================================================

func _setup_topdown_camera(target_center: Vector3) -> void:
	# 1. Force the camera to Orthogonal projection mode via code
	cam3D_view2D.projection = Camera3D.PROJECTION_ORTHOGONAL
	
	# Position the camera directly above the center point
	cam3D_view2D.global_position = target_center + _cam2D_offset
	
	# Force the camera to point straight down at the center point
	cam3D_view2D.look_at(target_center, Vector3.FORWARD)
	
	# 2. Automatically adjust the camera size to fit the grid bounding box
	_fit_orthogonal_camera_to_grid()

func _fit_orthogonal_camera_to_grid() -> void:
		
	# Calculate the base absolute world size of your grid using your constants
	var base_width : float = GlobalData.GRID_WIDTH * GlobalData.CELL_SIZE
	var base_depth : float = GlobalData.GRID_DEPTH * GlobalData.CELL_SIZE
	
	# Combine the uniform base grid_padding with your extra edge paddings
	var total_left_padding : float = grid_padding + padding_left
	var total_right_padding : float = grid_padding + padding_right
	var total_up_padding : float = grid_padding + padding_up
	var total_down_padding : float = grid_padding + padding_down
	
	# Calculate total sizes incorporating all padding factors
	var total_padded_width : float = base_width + total_left_padding + total_right_padding
	var total_padded_depth : float = base_depth + total_up_padding + total_down_padding
	
	# Get the aspect ratio of the player's screen viewport (width / height)
	var aspect_ratio = get_viewport().get_visible_rect().size.aspect()
	
	# Determine vertical screen sizing metrics based on dimension restrictions
	var size_based_on_width = total_padded_width / aspect_ratio
	var size_based_on_depth = total_padded_depth
	
	# Set the orthogonal camera size to the larger requirement
	cam3D_view2D.size = max(size_based_on_width, size_based_on_depth)
	
	# Calculate centering offset adjustments (only shifts if left/right or up/down are uneven)
	var horizontal_offset = (total_right_padding - total_left_padding) * 0.5
	var vertical_offset = (total_down_padding - total_up_padding) * 0.5
	cam3D_view2D.global_position += Vector3(horizontal_offset, 0, vertical_offset)

func _setup_perspective_camera(target_center: Vector3) -> void:
	cam3D_view3D.set_cull_mask_value(GlobalData.CAMERA_2D_LAYER, false)
	_update_perspective_position(target_center)


func _setup_cams(target_center : Vector3) -> void:
	_setup_perspective_camera(target_center)
	_setup_topdown_camera(target_center)
