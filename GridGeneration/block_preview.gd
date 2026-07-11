extends Node3D
class_name BlockPreview

@export var preview_size: Vector3i = Vector3i(1, 1, 1):
	set(value):
		preview_size = value
		_update_preview_mesh_dimensions()
		_force_validation_update() # Re-runs structural checks through the central pipeline

@onready var grid: Grid = get_parent()

var current_cam: Camera3D
var preview_instance: MeshInstance3D
var valid_mat: StandardMaterial3D
var invalid_mat: StandardMaterial3D

# Expose validation status so other systems can read it safely if needed
var is_placement_valid: bool = false

# Performance Optimization Cache Tracking
var _last_gx: int = -1
var _last_gz: int = -1

func _ready() -> void:
	EventBus.connect("camera_changed", func(cam): current_cam = cam)
	_setup_materials()
	_build_preview_node()


func _setup_materials() -> void:
	valid_mat = StandardMaterial3D.new()
	valid_mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)
	valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	invalid_mat = StandardMaterial3D.new()
	invalid_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.4)
	invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _build_preview_node() -> void:
	preview_instance = MeshInstance3D.new()
	preview_instance.mesh = BoxMesh.new()
	_update_preview_mesh_dimensions()
	add_child(preview_instance)


func _update_preview_mesh_dimensions() -> void:
	if not preview_instance: return
	(preview_instance.mesh as BoxMesh).size = Vector3(preview_size) * grid.CELL_SIZE


func _process(_delta: float) -> void:
	if not current_cam or not preview_instance: return
	
	var ray_result = _perform_mouse_raycast()
	if ray_result.is_empty(): return
	
	var grid_coords = _convert_hit_to_grid(ray_result.position, ray_result.normal)
	
	# Only execute logic if the cursor actually transitions to an entirely new cell
	if grid_coords.x != _last_gx or grid_coords.y != _last_gz:
		_last_gx = grid_coords.x
		_last_gz = grid_coords.y
		_process_placement_update(_last_gx, _last_gz)


## Centralized execution pipeline to eliminate duplicate calculation passes
func _process_placement_update(gx: int, gz: int) -> void:
	# 1. Update structural rules, states and flags
	_update_placement_logic(gx, gz)
	
	# 2. Package current coordinate state for transmission 
	var terrain_height = grid.get_height_at(gx, gz)
	var operational_grid_pos = Vector3i(gx, terrain_height, gz)
	
	# 3. Notify the system instantly with position, block dimensions, and safety rule states
	EventBus.preview_updated.emit(operational_grid_pos, preview_size, is_placement_valid)


## Casts a 3D physical vector down into the viewport scene state
func _perform_mouse_raycast() -> Dictionary:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = current_cam.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + current_cam.project_ray_normal(mouse_pos) * 2000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	return space_state.intersect_ray(query)


# =============================================================================
# HIT RESOLUTION & SIDE-SNAPPING LOGIC
# =============================================================================
## Extracts local Vector2i grid coordinates from raw 3D physics collision bounds
func _convert_hit_to_grid(hit_position: Vector3, hit_normal: Vector3) -> Vector2i:
	var sample_position: Vector3
	
	# Check if the normal is mostly pointing upwards (Top face of a block)
	if hit_normal.y > 0.5:
		sample_position = hit_position - (hit_normal * 0.1)
	else:
		sample_position = hit_position + (hit_normal * 0.1)
	
	var gx = clampi(int(floor(sample_position.x / grid.CELL_SIZE)), 0, grid.GRID_WIDTH - 1)
	var gz = clampi(int(floor(sample_position.z / grid.CELL_SIZE)), 0, grid.GRID_DEPTH - 1)
	return Vector2i(gx, gz)


# =============================================================================
# CONDITIONAL VALIDATION PLACEMENT
# =============================================================================
## Orchestrates layout updates, checks guidelines, and updates visuals
func _update_placement_logic(gx: int, gz: int) -> void:
	var within_boundaries = (gx + preview_size.x <= grid.GRID_WIDTH) and (gz + preview_size.z <= grid.GRID_DEPTH)
	
	# Collect terrain profiling data parameters
	var structural_data = _scan_footprint_terrain(gx, gz, within_boundaries)
	
	# Execute rule validation
	var perfect_flat_foundation = structural_data["is_flat"]
	var height_limit_exceeded = (structural_data["highest_tier"] + preview_size.y) > 3
	
	# Consolidated master state definition
	is_placement_valid = within_boundaries and perfect_flat_foundation and not height_limit_exceeded
	
	# Reposition and re-theme assets
	_update_preview_transform(gx, gz, structural_data["highest_tier"])


## Iterates across footprint matrices to identify flat spaces or height issues
func _scan_footprint_terrain(gx: int, gz: int, within_boundaries: bool) -> Dictionary:
	var result = {
		"highest_tier": 0,
		"is_flat": true
	}
	
	if not within_boundaries:
		result["highest_tier"] = grid.get_height_at(gx, gz)
		result["is_flat"] = false
		return result
		
	var baseline_height = grid.get_height_at(gx, gz)
	result["highest_tier"] = baseline_height
	
	for x_offset in range(preview_size.x):
		for z_offset in range(preview_size.z):
			var local_height = grid.get_height_at(gx + x_offset, gz + z_offset)
			
			if local_height != baseline_height:
				result["is_flat"] = false
				
			if local_height > result["highest_tier"]:
				result["highest_tier"] = local_height
				
	return result


## Repositions preview visual meshes in 3D scene space and updates colors
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
	
	preview_instance.material_override = valid_mat if is_placement_valid else invalid_mat


## Forces the central update routine to process immediate changes safely
func _force_validation_update() -> void:
	if _last_gx != -1 and _last_gz != -1:
		_process_placement_update(_last_gx, _last_gz)
