extends Node3D
class_name BlockPreview

@export var preview_size: Vector3i = Vector3i(1, 1, 1):
	set(value):
		preview_size = value
		_update_preview_mesh_dimensions()
		_force_validation_update()

@onready var grid: Grid = get_parent()

var current_cam: Camera3D
var preview_instance: MeshInstance3D
var valid_mat: StandardMaterial3D
var invalid_mat: StandardMaterial3D
var is_placement_valid: bool = false

var _last_gx: int = -1
var _last_gz: int = -1

func _ready() -> void:
	EventBus.connect("camera_changed", func(cam): current_cam = cam)
	EventBus.connect("block_placed", func(_pos, _size, is_successful): if is_successful : _force_validation_update())
	_setup_materials()
	_build_preview_node()

## Configures the transparency and color states for validation materials
func _setup_materials() -> void:
	valid_mat = StandardMaterial3D.new()
	valid_mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)
	valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	invalid_mat = StandardMaterial3D.new()
	invalid_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.4)
	invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

## Instantiates the mesh instance node used for visual placement previews
func _build_preview_node() -> void:
	preview_instance = MeshInstance3D.new()
	preview_instance.mesh = BoxMesh.new()
	_update_preview_mesh_dimensions()
	add_child(preview_instance)

## Adjusts the scale properties of the preview mesh to match active block dimensions
func _update_preview_mesh_dimensions() -> void:
	if not preview_instance: return
	(preview_instance.mesh as BoxMesh).size = Vector3(preview_size) * grid.CELL_SIZE

## Monitors camera inputs and mouse movements to trigger position recalculations
func _process(_delta: float) -> void:
	if not current_cam or not preview_instance: return
	
	var ray_result = _perform_mouse_raycast()
	if ray_result.is_empty(): return
	
	var grid_coords = _convert_hit_to_grid(ray_result.position, ray_result.normal)
	_handle_grid_cell_transition(grid_coords.x, grid_coords.y)

## Checks if the cursor has moved to a new cell before executing validation updates
func _handle_grid_cell_transition(gx: int, gz: int) -> void:
	if gx != _last_gx or gz != _last_gz:
		_last_gx = gx
		_last_gz = gz
		_process_placement_update(_last_gx, _last_gz)

## Runs the complete validation pipeline and announces changes to the system
func _process_placement_update(gx: int, gz: int) -> void:
	var structural_data = _scan_footprint_terrain(gx, gz)
	
	is_placement_valid = _evaluate_placement_rules(structural_data)
	
	_update_preview_transform(gx, gz, structural_data["highest_tier"])
	_update_preview_material()
	_broadcast_preview_state(gx, structural_data["highest_tier"], gz)

## Evaluates foundation flatness and global height limitations within safe bounds
func _evaluate_placement_rules(structural_data: Dictionary) -> bool:
	var perfect_flat_foundation = structural_data["is_flat"]
	var height_limit_exceeded = (structural_data["highest_tier"] + preview_size.y) > 3
	return perfect_flat_foundation and not height_limit_exceeded

## Dispatches updated placement data parameters to the global event system
func _broadcast_preview_state(gx: int, gy: int, gz: int) -> void:
	var operational_grid_pos = Vector3i(gx, gy, gz)
	EventBus.preview_updated.emit(operational_grid_pos, preview_size, is_placement_valid)

## Projects a ray from the viewport camera to detect mouse collisions with the 3D environment
func _perform_mouse_raycast() -> Dictionary:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = current_cam.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + current_cam.project_ray_normal(mouse_pos) * 2000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	return space_state.intersect_ray(query)

## Converts raw hit vectors to centered grid positions while safely locking them inside map bounds
func _convert_hit_to_grid(hit_position: Vector3, hit_normal: Vector3) -> Vector2i:
	var sample_position = hit_position + (hit_normal * (0.1 if hit_normal.y <= 0.5 else -0.1))
	
	# Determine target origin based on footprint parity (Odd vs Even sizing)
	var gx = _calculate_axis_start_index(sample_position.x, preview_size.x, grid.GRID_WIDTH)
	var gz = _calculate_axis_start_index(sample_position.z, preview_size.z, grid.GRID_DEPTH)
	
	return Vector2i(gx, gz)

## Calculates the clamped starting grid index for an axis based on mouse position and size
func _calculate_axis_start_index(spatial_pos: float, block_dim: int, grid_limit: int) -> int:
	var precise_cell = spatial_pos / grid.CELL_SIZE
	var exact_hover_idx = int(floor(precise_cell))
	var start_idx: int
	
	if block_dim % 2 == 1:
		# Odd sizes (1x1, 3x3): Center cleanly on the hovered tile
		start_idx = exact_hover_idx - (block_dim - 1) / 2
	else:
		# Even sizes (2x2): Check sub-tile position to pick the closest 4 tiles
		var fractional_offset = precise_cell - exact_hover_idx
		if fractional_offset > 0.5:
			start_idx = exact_hover_idx - (block_dim / 2) + 1
		else:
			start_idx = exact_hover_idx - (block_dim / 2)
			
	# Enforce hard boundaries so the block footprint never escapes the map grid boundaries
	return clampi(start_idx, 0, grid_limit - block_dim)

## Reads the matrix values across a block footprint to check flatness and peak bounds
func _scan_footprint_terrain(gx: int, gz: int) -> Dictionary:
	var baseline_height = grid.get_height_at(gx, gz)
	var result = {"highest_tier": baseline_height, "is_flat": true}
	
	for x_offset in range(preview_size.x):
		for z_offset in range(preview_size.z):
			var local_height = grid.get_height_at(gx + x_offset, gz + z_offset)
			
			if local_height != baseline_height:
				result["is_flat"] = false
			if local_height > result["highest_tier"]:
				result["highest_tier"] = local_height
				
	return result

## Adjusts the global translation vectors of the preview node in 3D space
func _update_preview_transform(gx: int, gz: int, target_tier: int) -> void:
	var offset_x = (preview_size.x * grid.CELL_SIZE) / 2.0
	var offset_z = (preview_size.z * grid.CELL_SIZE) / 2.0
	
	var terrain_surface_y = (target_tier + 1) * grid.CELL_SIZE
	var py = terrain_surface_y + ((preview_size.y * grid.CELL_SIZE) / 2.0)
	
	preview_instance.global_position = Vector3(
		(gx * grid.CELL_SIZE) + offset_x,
		py,
		(gz * grid.CELL_SIZE) + offset_z
	)

## Switches the material overlay based on the current validation state status
func _update_preview_material() -> void:
	preview_instance.material_override = valid_mat if is_placement_valid else invalid_mat

## Forces the calculation pipeline to re-evaluate properties using current positional caches
func _force_validation_update() -> void:
	if _last_gx != -1 and _last_gz != -1:
		_process_placement_update(_last_gx, _last_gz)
