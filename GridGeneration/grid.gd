extends Node3D
class_name Grid

# Grid Setup
const GRID_WIDTH = 15
const GRID_DEPTH = 15
const MAX_ELEVATION = 4
const CELL_SIZE = 2
# Layer Colors for Placed Blocks (0 = Dark, 3 = White)
const LAYER_COLORS = [
	Color8(64, 64, 64), # Layer 0: Dark Grey
	Color8(127, 127, 127), # Layer 1: Grey
	Color8(192, 192, 192), # Layer 2: Light Grey
	Color8(255, 255, 255)  # Layer 3: White
]

# Core Data
var grid_matrix: Array = []
var current_block_size: int = 2 
var center = Vector3(GRID_WIDTH, 0, GRID_DEPTH)*CELL_SIZE/2

var current_cam : Camera3D

# Materials for the Preview Cursor
var valid_preview_mat: StandardMaterial3D
var invalid_preview_mat: StandardMaterial3D

# Runtime tracking for the preview block
var preview_block: MeshInstance3D

func _ready() -> void:
	EventBus.connect("camera_changed", _on_cam_changed)
	_init_materials()
	_generate_base_grid_board() # Creates the board lines/squares automatically
	_create_preview_block()    # Sets up the 1x1x1 cube cursor

func _on_cam_changed(cam : Camera3D):
	current_cam = cam

func _init_materials() -> void:
	valid_preview_mat = StandardMaterial3D.new()
	valid_preview_mat.albedo_color = Color(0.0, 1.0, 0.0, 0.5)
	valid_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	invalid_preview_mat = StandardMaterial3D.new()
	invalid_preview_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.5)
	invalid_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

# ==============================================================================
# BASE GRID GENERATION
# ==============================================================================
func _generate_base_grid_board() -> void:
	# 1. Create the two materials using color offsets
	var checkered_materials = _create_grid_materials()
	
	# 2. Run the loop to spawn each individual grid square tile
	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			# Determine which of the two checkered materials to use
			var active_material = checkered_materials.mat_a if (x + z) % 2 == 0 else checkered_materials.mat_b
			
			_spawn_grid_tile(x, z, active_material)


func _create_grid_materials() -> Dictionary:
	var base_color = LAYER_COLORS[0]
	
	# mat_a = albedo - 20
	var mat_a = StandardMaterial3D.new()
	mat_a.albedo_color = base_color - Color8(20, 20, 20)
	
	# mat_b = albedo
	var mat_b = StandardMaterial3D.new()
	mat_b.albedo_color = base_color
	
	return {"mat_a": mat_a, "mat_b": mat_b}


func _spawn_grid_tile(grid_x: int, grid_z: int, tile_material: StandardMaterial3D) -> void:
	# Create the visual plane mesh instance
	var tile_mesh = MeshInstance3D.new()
	tile_mesh.mesh = PlaneMesh.new()
	(tile_mesh.mesh as PlaneMesh).size = Vector2(CELL_SIZE, CELL_SIZE)
	
	# Apply the passed-in material
	tile_mesh.material_override = tile_material
	add_child(tile_mesh)
	
	# Position the tile perfectly at its slot coordinates
	var offset = CELL_SIZE / 2.0
	var physical_x = (grid_x * CELL_SIZE) + offset
	var physical_z = (grid_z * CELL_SIZE) + offset
	
	tile_mesh.global_position = Vector3(physical_x, 0.0, physical_z)

# ==============================================================================
# MOUSE TRACKING & SNAPPING
# ==============================================================================
func _create_preview_block() -> void:
	preview_block = MeshInstance3D.new()
	preview_block.mesh = BoxMesh.new()
	
	# Setting the box mesh dimensions to a strict 1x1x1 grid unit block size
	(preview_block.mesh as BoxMesh).size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	preview_block.material_override = invalid_preview_mat
	add_child(preview_block)


func _process(_delta: float) -> void:
	if not current_cam:
		return

	var ray_target = _get_current_ray_intersection()
	
	var grid_coord = _get_clamped_grid_coordinates(ray_target)
	
	_update_preview_block_position(grid_coord)


func _get_current_ray_intersection() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	return _get_raycast_ground_intersection(mouse_pos)


func _get_clamped_grid_coordinates(hit_position: Vector3) -> Vector2i:
	# Calculate raw tile indices based on the cell sizing unit
	var raw_grid_x = int(floor(hit_position.x / CELL_SIZE))
	var raw_grid_z = int(floor(hit_position.z / CELL_SIZE))
	
	# Constrain coordinates strictly within your defined board boundaries
	var clamped_x = clampi(raw_grid_x, 0, GRID_WIDTH - 1)
	var clamped_z = clampi(raw_grid_z, 0, GRID_DEPTH - 1)
	
	return Vector2i(clamped_x, clamped_z)


func _update_preview_block_position(grid_coord: Vector2i) -> void:
	var offset = CELL_SIZE / 2.0
	
	# Use grid_coord.y for the 3D world's Z axis calculation
	var physical_x = (grid_coord.x * CELL_SIZE) + offset
	var physical_y = offset # Rests perfectly flush on top of the base board
	var physical_z = (grid_coord.y * CELL_SIZE) + offset
	
	preview_block.global_position = Vector3(physical_x, physical_y, physical_z)
	
	# Always sets to valid (green) material since clamping guarantees a legal spot
	preview_block.material_override = valid_preview_mat

func _get_raycast_ground_intersection(mouse_pos: Vector2) -> Vector3:
	var drop_plane = Plane(Vector3.UP, 0.0) 
	var ray_origin = current_cam.project_ray_origin(mouse_pos)
	var ray_direction = current_cam.project_ray_normal(mouse_pos)
	var intersection = drop_plane.intersects_ray(ray_origin, ray_direction)
	
	return intersection if intersection != null else Vector3.ZERO
