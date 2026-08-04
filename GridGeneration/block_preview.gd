extends Node3D
class_name BlockPreview

# ==========================================
# VISUAL CONFIGURATION SETTINGS
# ==========================================
const COLOR_BUILD_VALID = Color(0.0, 1.0, 0.0, 0.25)
const COLOR_BUILD_INVALID = Color(1.0, 0.0, 0.0, 0.25)

const COLOR_OUTLINE_BUILD_VALID = Color(0.0, 1.0, 0.0, 0.95)
const COLOR_OUTLINE_BUILD_INVALID = Color(1.0, 0.0, 0.0, 0.95)
const COLOR_OUTLINE_REMOVE_VALID = Color(0.0, 1.0, 0.0, 0.95)
const COLOR_OUTLINE_REMOVE_INVALID = Color(1.0, 0.2, 0.2, 0.95)

# ==========================================
# EXPORTS & PROPERTIES
# ==========================================
@export var conform_to_terrain: bool = false:
	set(value):
		conform_to_terrain = value
		_reprocess_last_tile()

@export var preview_enabled: bool = false:
	set(value):
		preview_enabled = value
		_update_visibility_state()
		if preview_enabled:
			_reprocess_last_tile()

@export var mode: GData.BuildMode = GData.BuildMode.ADD:
	set(value):
		mode = value
		_update_preview_mesh_dimensions()
		_reprocess_last_tile()

@export var preview_size: Vector3i = Vector3i(1, 1, 1):
	set(value):
		preview_size = value
		_update_preview_mesh_dimensions()
		_reprocess_last_tile()

@onready var grid: Grid = get_parent()

var preview_instance: MeshInstance3D
var outline_instance: MeshInstance3D 

var valid_mat: StandardMaterial3D
var invalid_mat: StandardMaterial3D
var outline_mat: StandardMaterial3D

var is_placement_valid: bool = false

# Cache the last received tile info so size/mode changes can re-evaluate instantly
var _last_tile_info: Dictionary = {}
var _hidden_meshes: Array[Tile] = []


# ==========================================
# LIFECYCLE & INITIALIZATION
# ==========================================

func _ready() -> void:
	_connect_event_signals()
	_setup_materials()
	_build_preview_nodes()
	Global.current_build_mode = mode



func _connect_event_signals() -> void:
	EventBus.build_mode_changed.connect(_on_build_mode_changed)
	EventBus.block_placed.connect(_on_block_info)
	EventBus.block_removed.connect(_on_block_info)
	EventBus.tile_hovered.connect(_on_tile_hovered)


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


func _build_preview_nodes() -> void:
	preview_instance = MeshInstance3D.new()
	preview_instance.visible = false
	add_child(preview_instance)
	
	outline_instance = MeshInstance3D.new()
	outline_instance.mesh = ImmediateMesh.new()
	outline_instance.material_override = outline_mat
	outline_instance.visible = false
	add_child(outline_instance)
	
	_update_preview_mesh_dimensions()


# ==========================================
# SIGNAL & TILE PROCESSING
# ==========================================

func _on_build_mode_changed(new_mode: GData.BuildMode) -> void:
	mode = new_mode


func _on_block_info(_pos, _size, is_successful: bool) -> void: 
	if is_successful: 
		_restore_hidden_blocks()
		_reprocess_last_tile()


func _on_tile_hovered(tile_info: Dictionary) -> void:
	if tile_info.is_empty(): return
	_last_tile_info = tile_info
	_process_tile_change(tile_info)


func _process_tile_change(tile_info: Dictionary) -> void:
	if not preview_instance or not preview_enabled: return

	var grid_coords = _calculate_footprint_start(tile_info.position, tile_info.normal)
	var gx = grid_coords.x
	var gz = grid_coords.y
	
	var structural_data = _scan_footprint_terrain(gx, gz)
	is_placement_valid = _evaluate_placement_rules(structural_data)
	
	_update_preview_geometry(gx, gz, structural_data)
	_update_preview_material()
	_update_visibility_state()
	_manage_block_hiding_pipeline(gx, gz, structural_data["highest_tier"])
	
	_broadcast_preview_state(gx, structural_data["highest_tier"], gz)


# ==========================================
# FOOTPRINT & TERRAIN EVALUATION
# ==========================================

func _calculate_footprint_start(hit_pos: Vector3, hit_norm: Vector3) -> Vector2i:
	var sample_pos = hit_pos + (hit_norm * (0.1 if hit_norm.y <= 0.5 else -0.1))
	var gx = _calculate_axis_start_index(sample_pos.x, preview_size.x, GData.GRID_WIDTH)
	var gz = _calculate_axis_start_index(sample_pos.z, preview_size.z, GData.GRID_DEPTH)
	return Vector2i(gx, gz)


func _calculate_axis_start_index(spatial_pos: float, block_dim: int, grid_limit: int) -> int:
	var precise_cell = spatial_pos / GData.CELL_SIZE
	var exact_hover_idx = int(floor(precise_cell))
	var start_idx: int
	
	if block_dim % 2 == 1:
		start_idx = exact_hover_idx - (block_dim - 1) / 2
	else:
		var fractional_offset = precise_cell - exact_hover_idx
		start_idx = exact_hover_idx - (block_dim / 2) + (1 if fractional_offset > 0.5 else 0)
			
	return clampi(start_idx, 0, grid_limit - block_dim)


func _scan_footprint_terrain(gx: int, gz: int) -> Dictionary:
	var baseline_height = grid.get_height_at(gx, gz)
	var result = {
		"highest_tier": baseline_height,
		"is_flat": true,
		"column_heights": {}
	}
	
	for x_offset in range(preview_size.x):
		for z_offset in range(preview_size.z):
			var lx = gx + x_offset
			var lz = gz + z_offset
			var local_height = grid.get_height_at(lx, lz)
			
			result["column_heights"][Vector2i(x_offset, z_offset)] = local_height
			if local_height != baseline_height:
				result["is_flat"] = false
			if local_height > result["highest_tier"]:
				result["highest_tier"] = local_height
				
	return result


func _evaluate_placement_rules(structural_data: Dictionary) -> bool:
	if mode == GData.BuildMode.REMOVE:
		return structural_data["highest_tier"] > 0
		
	var height_limit_exceeded = (structural_data["highest_tier"] + preview_size.y) > GData.GRID_HEIGHT - 1
	if height_limit_exceeded:
		return false
		
	if conform_to_terrain:
		return true
		
	return structural_data["is_flat"]


func _calculate_removal_tier_bounds(highest_tier: int) -> Vector2i:
	var top_tier = highest_tier
	var bottom_tier = top_tier - preview_size.y + 1
	if bottom_tier < 1:
		bottom_tier = 1
		top_tier = bottom_tier + preview_size.y - 1
	return Vector2i(bottom_tier, top_tier)


# ==========================================
# GEOMETRY & TRANSFORM UPDATES
# ==========================================

func _update_preview_mesh_dimensions() -> void:
	if not preview_instance or not outline_instance: return
	
	var target_size = Vector3(preview_size) * GData.CELL_SIZE
	_configure_solid_box_mesh(target_size)
	
	var imm_mesh = outline_instance.mesh as ImmediateMesh
	PreviewMeshBuilder.build_standard_box_wireframe(imm_mesh, target_size, mode == GData.BuildMode.REMOVE)


func _configure_solid_box_mesh(target_size: Vector3) -> void:
	if not preview_instance.mesh is BoxMesh:
		preview_instance.mesh = BoxMesh.new()
	(preview_instance.mesh as BoxMesh).size = target_size
	_update_visibility_state()


func _update_preview_geometry(gx: int, gz: int, structural_data: Dictionary) -> void:
	if mode == GData.BuildMode.ADD and conform_to_terrain and not structural_data["is_flat"]:
		_build_conforming_mesh_and_outline(gx, gz, structural_data)
	else:
		_apply_standard_box_transform(gx, gz, structural_data["highest_tier"])


func _build_conforming_mesh_and_outline(gx: int, gz: int, structural_data: Dictionary) -> void:
	var heights = structural_data["column_heights"]
	
	preview_instance.mesh = PreviewMeshBuilder.create_conforming_mesh(preview_size, gx, gz, heights)
	PreviewMeshBuilder.build_conforming_wireframe(outline_instance.mesh as ImmediateMesh, preview_size, gx, gz, heights)
	
	preview_instance.global_position = Vector3.ZERO
	outline_instance.global_position = Vector3.ZERO


func _apply_standard_box_transform(gx: int, gz: int, target_tier: int) -> void:
	_update_preview_mesh_dimensions()
	
	var offset_x = (preview_size.x * GData.CELL_SIZE) / 2.0
	var offset_z = (preview_size.z * GData.CELL_SIZE) / 2.0
	var py: float
	
	if mode == GData.BuildMode.ADD:
		py = ((target_tier + 1) * GData.CELL_SIZE) + ((preview_size.y * GData.CELL_SIZE) / 2.0)
	else:
		var bounds = _calculate_removal_tier_bounds(target_tier)
		py = (bounds.x * GData.CELL_SIZE) + ((preview_size.y * GData.CELL_SIZE) / 2.0)
	
	var target_pos = Vector3((gx * GData.CELL_SIZE) + offset_x, py, (gz * GData.CELL_SIZE) + offset_z)
	preview_instance.global_position = target_pos
	outline_instance.global_position = target_pos


func _update_visibility_state() -> void:
	if not preview_instance or not outline_instance: return
	
	if not preview_enabled or _last_tile_info.is_empty():
		preview_instance.visible = false
		outline_instance.visible = false
	else:
		preview_instance.visible = (mode == GData.BuildMode.ADD)
		outline_instance.visible = true


func _update_preview_material() -> void:
	if mode == GData.BuildMode.ADD:
		preview_instance.material_override = valid_mat if is_placement_valid else invalid_mat
		outline_mat.albedo_color = COLOR_OUTLINE_BUILD_VALID if is_placement_valid else COLOR_OUTLINE_BUILD_INVALID
	else:
		outline_mat.albedo_color = COLOR_OUTLINE_REMOVE_VALID if is_placement_valid else COLOR_OUTLINE_REMOVE_INVALID


# ==========================================
# OBJECT VISIBILITY ARCHIVE OPERATIONS
# ==========================================

func _restore_hidden_blocks() -> void:
	for tile in _hidden_meshes:
		if is_instance_valid(tile):
			tile.visible = true
	_hidden_meshes.clear()


func _manage_block_hiding_pipeline(gx: int, gz: int, target_tier: int) -> void:
	_restore_hidden_blocks()
	if mode != GData.BuildMode.REMOVE or not is_placement_valid or not preview_enabled: return
		
	var bounds = _calculate_removal_tier_bounds(target_tier)
	_hide_blocks_within_volume(gx, gz, bounds.x, bounds.y)


func _hide_blocks_within_volume(gx: int, gz: int, bottom_tier: int, top_tier: int) -> void:
	for x_offset in range(preview_size.x):
		for z_offset in range(preview_size.z):
			var lx = gx + x_offset
			var lz = gz + z_offset
			_hide_cell_column_segments(lx, lz, bottom_tier, top_tier)


func _hide_cell_column_segments(lx: int, lz: int, bottom: int, top: int) -> void:
	if lx < 0 or lx >= GData.GRID_WIDTH or lz < 0 or lz >= GData.GRID_DEPTH: return

	var cell_tiles = grid.visual_matrix[lx][lz]
	for h in range(cell_tiles.size()):
		if h >= bottom and h <= top:
			var tile_node = cell_tiles[h]
			if tile_node is Tile and is_instance_valid(tile_node) and tile_node.visible:
				tile_node.visible = false
				_hidden_meshes.append(tile_node)


# ==========================================
# STATE SYNCHRONIZATION
# ==========================================

func _reprocess_last_tile() -> void:
	if not _last_tile_info.is_empty():
		_process_tile_change(_last_tile_info)


func _broadcast_preview_state(gx: int, gy: int, gz: int) -> void:
	var operational_grid_pos = Vector3i(gx, gy, gz)
	EventBus.preview_updated.emit(operational_grid_pos, preview_size, is_placement_valid)
