extends Node3D
class_name BlockPreview

# ==========================================
# VISUAL CONFIGURATION SETTINGS
# ==========================================
const COLOR_BUILD_VALID = Color(0.0, 1.0, 0.0, 0.25)
const COLOR_BUILD_INVALID = Color(1.0, 0.0, 0.0, 0.25)

const COLOR_OUTLINE_BUILD_VALID = Color(0.0, 1.0, 0.0, 0.8)
const COLOR_OUTLINE_BUILD_INVALID = Color(1.0, 0.0, 0.0, 0.8)
const COLOR_OUTLINE_REMOVE_VALID = Color(0.0, 1.0, 0.0, 0.9)
const COLOR_OUTLINE_REMOVE_INVALID = Color(1.0, 0.2, 0.2, 0.9)

# ==========================================
# EXPORTS & PROPERTIES
# ==========================================
@export var mode: Grid.BuildMode = Grid.BuildMode.ADD:
	set(value):
		mode = value
		EventBus.build_mode_changed.emit(value)
		_update_preview_mesh_dimensions()
		_force_validation_update()

@export var preview_size: Vector3i = Vector3i(1, 1, 1):
	set(value):
		preview_size = value
		_update_preview_mesh_dimensions()
		_force_validation_update()

@onready var grid: Grid = get_parent()

var current_cam: Camera3D
var preview_instance: MeshInstance3D
var outline_instance: MeshInstance3D 

var valid_mat: StandardMaterial3D
var invalid_mat: StandardMaterial3D
var outline_mat: StandardMaterial3D

var is_placement_valid: bool = false

var _last_gx: int = -1
var _last_gz: int = -1
var _hidden_meshes: Array[MeshInstance3D] = []


# ==========================================
# LIFECYCLE & INITIALIZATION
# ==========================================

func _ready() -> void:
	_connect_event_signals()
	_setup_materials()
	_build_preview_nodes()

## Binds listener logic to global event systems.
func _connect_event_signals() -> void:
	EventBus.camera_changed.connect(func(cam): current_cam = cam)
	EventBus.build_mode_changed.connect(func(new_mode): mode = new_mode)
	EventBus.block_placed.connect(is_block_placed)

func is_block_placed(_pos, _size, is_successful): 
		if is_successful: 
			_restore_hidden_blocks()
			_force_validation_update()

## Allocates structural materials and enforces unshaded transparency rules.
func _setup_materials() -> void:
	valid_mat = StandardMaterial3D.new()
	valid_mat.albedo_color = COLOR_BUILD_VALID
	valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	invalid_mat = StandardMaterial3D.new()
	invalid_mat.albedo_color = COLOR_BUILD_INVALID
	invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	outline_mat = StandardMaterial3D.new()
	outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.no_depth_test = true

## Instantiates scene hierarchy nodes required for drawing previews.
func _build_preview_nodes() -> void:
	preview_instance = MeshInstance3D.new()
	add_child(preview_instance)
	
	outline_instance = MeshInstance3D.new()
	outline_instance.mesh = ImmediateMesh.new()
	outline_instance.material_override = outline_mat
	add_child(outline_instance)
	
	_update_preview_mesh_dimensions()


# ==========================================
# CORE PROCESSING PIPELINE
# ==========================================

func _process(_delta: float) -> void:
	if not current_cam or not preview_instance: return
	
	var ray_result = _perform_mouse_raycast()
	if ray_result.is_empty(): return
	
	var grid_coords = _convert_hit_to_grid(ray_result.position, ray_result.normal)
	_handle_grid_cell_transition(grid_coords.x, grid_coords.y)

## Prevents layout calculations from running unless the target grid address changes.
func _handle_grid_cell_transition(gx: int, gz: int) -> void:
	if gx != _last_gx or gz != _last_gz:
		_last_gx = gx
		_last_gz = gz
		_process_placement_update(_last_gx, _last_gz)

## Updates geometry, rules, transforms, states, and pipeline caches for a specific coordinate.
func _process_placement_update(gx: int, gz: int) -> void:
	var structural_data = _scan_footprint_terrain(gx, gz)
	
	is_placement_valid = _evaluate_placement_rules(structural_data)
	
	_update_preview_transform(gx, gz, structural_data["highest_tier"])
	_update_preview_material()
	_manage_block_hiding_pipeline(gx, gz, structural_data["highest_tier"])
	
	_broadcast_preview_state(gx, structural_data["highest_tier"], gz)


# ==========================================
# RAYCASTING & GRID CALCULATIONS
# ==========================================

## Shoots a physical collision test line out from the active camera perspective viewport.
func _perform_mouse_raycast() -> Dictionary:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = current_cam.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + current_cam.project_ray_normal(mouse_pos) * 2000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	return space_state.intersect_ray(query)

## Translates 3D coordinates into relative layout matrix coordinates.
func _convert_hit_to_grid(hit_position: Vector3, hit_normal: Vector3) -> Vector2i:
	var sample_position = hit_position + (hit_normal * (0.1 if hit_normal.y <= 0.5 else -0.1))
	
	var gx = _calculate_axis_start_index(sample_position.x, preview_size.x, grid.GRID_WIDTH)
	var gz = _calculate_axis_start_index(sample_position.z, preview_size.z, grid.GRID_DEPTH)
	
	return Vector2i(gx, gz)

## Solves bounding alignments for centered placement coordinates on an axis.
func _calculate_axis_start_index(spatial_pos: float, block_dim: int, grid_limit: int) -> int:
	var precise_cell = spatial_pos / grid.CELL_SIZE
	var exact_hover_idx = int(floor(precise_cell))
	var start_idx: int
	
	if block_dim % 2 == 1:
		start_idx = exact_hover_idx - (block_dim - 1) / 2
	else:
		var fractional_offset = precise_cell - exact_hover_idx
		start_idx = exact_hover_idx - (block_dim / 2) + (1 if fractional_offset > 0.5 else 0)
			
	return clampi(start_idx, 0, grid_limit - block_dim)


# ==========================================
# TERRAIN & VALIDATION LOGIC
# ==========================================

## Scans the targeted grid zone layout area to identify maximum elevation and flat conditions.
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

## Processes structural context data to decide whether execution layout is legal.
func _evaluate_placement_rules(structural_data: Dictionary) -> bool:
	if mode == Grid.BuildMode.REMOVE:
		return structural_data["highest_tier"] > 0
		
	var perfect_flat_foundation = structural_data["is_flat"]
	var height_limit_exceeded = (structural_data["highest_tier"] + preview_size.y) > 3
	return perfect_flat_foundation and not height_limit_exceeded

## Computes vertical slice layer boundaries within grid constraint rules.
func _calculate_removal_tier_bounds(highest_tier: int) -> Vector2i:
	var top_tier = highest_tier
	var bottom_tier = top_tier - preview_size.y + 1
	if bottom_tier < 1:
		bottom_tier = 1
		top_tier = bottom_tier + preview_size.y - 1
	return Vector2i(bottom_tier, top_tier)


# ==========================================
# TRANSFORMS & VISUAL GENERATION
# ==========================================

## Triggers dynamic recreation workflows to shape mesh assets based on dimensional parameters.
func _update_preview_mesh_dimensions() -> void:
	if not preview_instance or not outline_instance: return
	
	var target_size = Vector3(preview_size) * grid.CELL_SIZE
	_configure_solid_mesh_visibility(target_size)
	_generate_wireframe_box(outline_instance.mesh as ImmediateMesh, target_size)

## Toggles visibility properties and properties of the solid shape model volume.
func _configure_solid_mesh_visibility(target_size: Vector3) -> void:
	if mode == Grid.BuildMode.ADD:
		preview_instance.visible = true
		if not preview_instance.mesh is BoxMesh:
			preview_instance.mesh = BoxMesh.new()
		(preview_instance.mesh as BoxMesh).size = target_size
	else:
		preview_instance.visible = false

## Coordinates translation math structures for spatial placement components.
func _update_preview_transform(gx: int, gz: int, target_tier: int) -> void:
	var offset_x = (preview_size.x * grid.CELL_SIZE) / 2.0
	var offset_z = (preview_size.z * grid.CELL_SIZE) / 2.0
	var py: float
	
	if mode == Grid.BuildMode.ADD:
		py = ((target_tier + 1) * grid.CELL_SIZE) + ((preview_size.y * grid.CELL_SIZE) / 2.0)
	else:
		var bounds = _calculate_removal_tier_bounds(target_tier)
		py = (bounds.x * grid.CELL_SIZE) + ((preview_size.y * grid.CELL_SIZE) / 2.0)
	
	_apply_preview_positioning(Vector3((gx * grid.CELL_SIZE) + offset_x, py, (gz * grid.CELL_SIZE) + offset_z))

## Shifts world coordination arrays for active runtime visual entities simultaneously.
func _apply_preview_positioning(final_position: Vector3) -> void:
	preview_instance.global_position = final_position
	outline_instance.global_position = final_position

## Evaluates conditions to map designated hex colors onto asset properties.
func _update_preview_material() -> void:
	if mode == Grid.BuildMode.ADD:
		preview_instance.material_override = valid_mat if is_placement_valid else invalid_mat
		outline_mat.albedo_color = COLOR_OUTLINE_BUILD_VALID if is_placement_valid else COLOR_OUTLINE_BUILD_INVALID
	else:
		outline_mat.albedo_color = COLOR_OUTLINE_REMOVE_VALID if is_placement_valid else COLOR_OUTLINE_REMOVE_INVALID


# ==========================================
# WIREFRAME DRAWING ENGINE
# ==========================================

## Draws base line vertex structures and conditional removal patterns into raw display memory.
func _generate_wireframe_box(imm_mesh: ImmediateMesh, size: Vector3) -> void:
	imm_mesh.clear_surfaces()
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var ext = size / 2.0
	_draw_cage_skeleton_lines(imm_mesh, ext)
	
	if mode == Grid.BuildMode.REMOVE:
		_draw_tactical_hash_lines(imm_mesh, ext)
	
	imm_mesh.surface_end()

## Assembles standard outline edges for a regular cube configuration.
func _draw_cage_skeleton_lines(imm_mesh: ImmediateMesh, ext: Vector3) -> void:
	# Top Plane
	imm_mesh.surface_add_vertex(Vector3(-ext.x,  ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3( ext.x,  ext.y, -ext.z))
	imm_mesh.surface_add_vertex(Vector3( ext.x,  ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3( ext.x,  ext.y,  ext.z))
	imm_mesh.surface_add_vertex(Vector3( ext.x,  ext.y,  ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x,  ext.y,  ext.z))
	imm_mesh.surface_add_vertex(Vector3(-ext.x,  ext.y,  ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x,  ext.y, -ext.z))
	# Bottom Plane
	imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3( ext.x, -ext.y, -ext.z))
	imm_mesh.surface_add_vertex(Vector3( ext.x, -ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3( ext.x, -ext.y,  ext.z))
	imm_mesh.surface_add_vertex(Vector3( ext.x, -ext.y,  ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y,  ext.z))
	imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y,  ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y, -ext.z))
	# Vertical Connectors
	imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x,  ext.y, -ext.z))
	imm_mesh.surface_add_vertex(Vector3( ext.x, -ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3( ext.x,  ext.y, -ext.z))
	imm_mesh.surface_add_vertex(Vector3( ext.x, -ext.y,  ext.z)); imm_mesh.surface_add_vertex(Vector3( ext.x,  ext.y,  ext.z))
	imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y,  ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x,  ext.y,  ext.z))

## Generates cross-hashed lines tracking outer bounding planes for distinct selection tracking.
func _draw_tactical_hash_lines(imm_mesh: ImmediateMesh, ext: Vector3) -> void:
	# Top Face
	imm_mesh.surface_add_vertex(Vector3(-ext.x, ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3(ext.x, ext.y, ext.z))
	imm_mesh.surface_add_vertex(Vector3(ext.x, ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x, ext.y, ext.z))
	# Front Face
	imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y, ext.z)); imm_mesh.surface_add_vertex(Vector3(ext.x, ext.y, ext.z))
	imm_mesh.surface_add_vertex(Vector3(ext.x, -ext.y, ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x, ext.y, ext.z))
	# Back Face
	imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3(ext.x, ext.y, -ext.z))
	imm_mesh.surface_add_vertex(Vector3(ext.x, -ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x, ext.y, -ext.z))
	# Left Face
	imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x, ext.y, ext.z))
	imm_mesh.surface_add_vertex(Vector3(-ext.x, -ext.y, ext.z)); imm_mesh.surface_add_vertex(Vector3(-ext.x, ext.y, -ext.z))
	# Right Face
	imm_mesh.surface_add_vertex(Vector3(ext.x, -ext.y, -ext.z)); imm_mesh.surface_add_vertex(Vector3(ext.x, ext.y, ext.z))
	imm_mesh.surface_add_vertex(Vector3(ext.x, -ext.y, ext.z)); imm_mesh.surface_add_vertex(Vector3(ext.x, ext.y, -ext.z))


# ==========================================
# OBJECT VISIBILITY ARCHIVE OPERATIONS
# ==========================================

## Re-activates display properties for standard items previously cached in storage buffers.
func _restore_hidden_blocks() -> void:
	for mesh in _hidden_meshes:
		if is_instance_valid(mesh):
			mesh.visible = true
	_hidden_meshes.clear()

## Collects and screens grid objects falling inside active bounding areas to mask out their display.
func _manage_block_hiding_pipeline(gx: int, gz: int, target_tier: int) -> void:
	_restore_hidden_blocks()
	if mode != Grid.BuildMode.REMOVE or not is_placement_valid: return
		
	var bounds = _calculate_removal_tier_bounds(target_tier)
	_hide_blocks_within_volume(gx, gz, bounds.x, bounds.y)

## Scans structured cell nodes to hide visual representations matching index layers.
func _hide_blocks_within_volume(gx: int, gz: int, bottom_tier: int, top_tier: int) -> void:
	for x_offset in range(preview_size.x):
		for z_offset in range(preview_size.z):
			var lx = gx + x_offset
			var lz = gz + z_offset
			_hide_cell_column_segments(lx, lz, bottom_tier, top_tier)

## Iterates over targeted vertical stack columns to toggle matching visible meshes.
func _hide_cell_column_segments(lx: int, lz: int, bottom: int, top: int) -> void:
	if lx < 0 or lx >= grid.GRID_WIDTH or lz < 0 or lz >= grid.GRID_DEPTH: return
	
	var cell_meshes = grid.visual_matrix[lx][lz]
	for h in range(cell_meshes.size()):
		if h >= bottom and h <= top:
			var mesh = cell_meshes[h]
			if is_instance_valid(mesh) and mesh.visible:
				mesh.visible = false
				_hidden_meshes.append(mesh)


# ==========================================
# STATE SYNCHRONIZATION
# ==========================================

## Triggers an explicit evaluation of current target positioning constraints.
func _force_validation_update() -> void:
	if _last_gx != -1 and _last_gz != -1:
		_process_placement_update(_last_gx, _last_gz)

## Dispatches system events containing modified properties across structural channels.
func _broadcast_preview_state(gx: int, gy: int, gz: int) -> void:
	var operational_grid_pos = Vector3i(gx, gy, gz)
	EventBus.preview_updated.emit(operational_grid_pos, preview_size, is_placement_valid)
