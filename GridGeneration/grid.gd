extends Node3D
class_name Grid

# ==========================================
# CONSTANTS & CONFIGURATION
# ==========================================

## Width of the grid along the X-axis (in cells).
const GRID_WIDTH: int = GData.GRID_WIDTH
## Depth of the grid along the Z-axis (in cells).
const GRID_DEPTH: int = GData.GRID_DEPTH
## World-space center point of the entire grid.
const GRID_CENTER: Vector3 = GData.GRID_CENTER
## World-space length/width of an individual cubic cell.
const CELL_SIZE: float = GData.CELL_SIZE
## Color definitions corresponding to vertical stack tiers.
const GRID_LAYER_COLORS = GData.GRID_LAYER_COLORS
## Scene tree child node name used for clustering tile instances.
const TILES_NODE_NAME: String = "Tiles"

enum LineType { THICK, THIN_DASHED }

# ==========================================
# STATE & DATA CONTAINERS
# ==========================================

## 2D Matrix storing arrays of instantiated Tile nodes per (X, Z) cell stack.
var visual_matrix: Array = []
## Container node holding all instantiated physical tile nodes in the Scene Tree.
var tiles_container: Node3D

# ==========================================
# RESOURCE CACHE & MATERIALS
# ==========================================

## Cached shared box mesh geometry applied to all tile instances.
var shared_box_mesh: BoxMesh
## Cached shared collision shape applied to all tile instances.
var shared_box_shape: BoxShape3D
## Materials array corresponding to layer colors.
var layer_materials: Array[StandardMaterial3D] = []

var _outline_mat: StandardMaterial3D
var _grid_overlay_instance: MeshInstance3D
var _thick_line_material: StandardMaterial3D
var _thin_dotted_material: StandardMaterial3D


# ==========================================
# LIFECYCLE INITIALIZATION
# ==========================================

func _ready() -> void:
	_initialize_containers()
	_initialize_matrix_database()
	_precalculate_resources()
	
	EventBus.placement_requested.connect(_on_placement_requested)
	EventBus.removal_requested.connect(_on_removal_requested)

## Prepares a dedicated scene node for child tiles to prevent hierarchy clutter.
func _initialize_containers() -> void:
	if has_node(TILES_NODE_NAME):
		var old_container = get_node(TILES_NODE_NAME)
		remove_child(old_container)
		old_container.queue_free()
	
	tiles_container = Node3D.new()
	tiles_container.name = TILES_NODE_NAME
	add_child(tiles_container)

## Allocates visual 2D matrix sized to match grid dimensions.
func _initialize_matrix_database() -> void:
	visual_matrix.clear()
	for x in range(GRID_WIDTH):
		var vis_row: Array = []
		vis_row.resize(GRID_DEPTH)
		for z in range(GRID_DEPTH):
			vis_row[z] = []
		visual_matrix.append(vis_row)

## Creates and caches reusable meshes, collisions, and materials.
func _precalculate_resources() -> void:
	shared_box_mesh = BoxMesh.new()
	shared_box_mesh.size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)

	shared_box_shape = BoxShape3D.new()
	shared_box_shape.size = shared_box_mesh.size
	
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.albedo_color = Color.BLACK
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.grow = true
	_outline_mat.grow_amount = 0.1
	
	for color in GRID_LAYER_COLORS:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.next_pass = _outline_mat
		layer_materials.append(mat)

	_thick_line_material = StandardMaterial3D.new()
	_thick_line_material.albedo_color = Color.BLACK
	_thick_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	_thin_dotted_material = StandardMaterial3D.new()
	_thin_dotted_material.albedo_color = Color(0.1, 0.1, 0.1, 0.4)
	_thin_dotted_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


# ==========================================
# GRID DATA ACCESSORS (DELEGATED TO GRIDSERVICE)
# ==========================================

## Returns the top layer level index stored at coordinates, or -1 if empty/out of bounds.
func get_height_at(x: int, z: int) -> int:
	return Global.board.get_height_at(Vector2i(x, z))

## Directly sets the data matrix layer height value for given coordinates.
func set_height_at(x: int, z: int, height: int) -> void:
	Global.board.set_height_at(Vector2i(x, z), height)


# ==========================================
# INCREMENTAL TILE MUTATIONS
# ==========================================

## Instantiates a single Tile (Mesh + Collider) at a specific coordinate and vertical layer level.
func add_tile_at(x: int, level: int, z: int) -> void:
	if x < 0 or x >= GRID_WIDTH or z < 0 or z >= GRID_DEPTH:
		return
		
	var world_pos = Global.board.grid_to_world(x, level, z)
	
	var tile = Tile.new()
	tile.grid_pos = Vector2i(x, z)
	tile.height_level = level
	tile.collision_layer = GData.TILE.COLLISION_LAYER_BITMASK
	tile.collision_mask = GData.TILE.COLLISION_MASK_BITMASK
	
	var tile_mesh = MeshInstance3D.new()
	tile_mesh.mesh = shared_box_mesh
	var mat_idx = clampi(level, 0, layer_materials.size() - 1)
	tile_mesh.material_override = layer_materials[mat_idx]
	tile.add_child(tile_mesh)

	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = shared_box_shape
	tile.add_child(collision_shape)
	
	tiles_container.add_child(tile)
	tile.global_position = world_pos
	
	visual_matrix[x][z].append(tile)
	set_height_at(x, z, max(get_height_at(x, z), level))

## Removes and frees only the topmost Tile node from a cell stack.
func remove_top_tile_at(x: int, z: int) -> void:
	if x < 0 or x >= GRID_WIDTH or z < 0 or z >= GRID_DEPTH:
		return
		
	var stack: Array = visual_matrix[x][z]
	if stack.is_empty():
		return

	var top_tile = stack.pop_back()
	if is_instance_valid(top_tile):
		top_tile.queue_free()

	set_height_at(x, z, stack.size() - 1)

## Frees all instantiated Tile nodes inside a single column and resets its data.
func clear_column_at(x: int, z: int) -> void:
	if x >= 0 and x < GRID_WIDTH and z >= 0 and z < GRID_DEPTH:
		for tile_node in visual_matrix[x][z]:
			if is_instance_valid(tile_node):
				tile_node.queue_free()
		visual_matrix[x][z].clear()
		set_height_at(x, z, -1)


# ==========================================
# EVENT BUS HANDLERS
# ==========================================

## Event handler to incrementally add layers over a requested footprint with dynamic terrain conforming.
func _on_placement_requested(map_pos: Vector2i, size: Vector3i) -> void:
	var max_x := map_pos.x + size.x
	var max_z := map_pos.y + size.z

	for x in range(map_pos.x, max_x):
		for z in range(map_pos.y, max_z):
			var current_top := get_height_at(x, z)
			for dy in range(size.y):
				add_tile_at(x, current_top + 1 + dy, z)
			
	update_grid_line_network()
	EventBus.board_changed.emit()
	
	var final_coords = Vector3i(map_pos.x, get_height_at(map_pos.x, map_pos.y), map_pos.y)
	EventBus.block_placed.emit(final_coords, size, true)

## Event handler to incrementally remove layers down over a requested footprint.
func _on_removal_requested(map_pos: Vector2i, size: Vector3i) -> void:
	var max_x := map_pos.x + size.x
	var max_z := map_pos.y + size.z

	var highest_tier := 0
	
	for x in range(map_pos.x, max_x):
		for z in range(map_pos.y, max_z):
			var h := get_height_at(x, z)
			if h > highest_tier:
				highest_tier = h

	if highest_tier <= 0:
		return

	var bottom_tier: int = max(1, highest_tier - size.y + 1)
	
	for x in range(map_pos.x, max_x):
		for z in range(map_pos.y, max_z):
			var col_height := get_height_at(x, z)
			if col_height < bottom_tier:
				continue
				
			var remove_count: int = col_height - bottom_tier + 1
			for i in range(remove_count):
				remove_top_tile_at(x, z)

	update_grid_line_network()
	EventBus.board_changed.emit()

	var final_coords := Vector3i(map_pos.x, highest_tier, map_pos.y)
	EventBus.block_removed.emit(final_coords, size, true)


# ==========================================
# OVERLAY & RENDERING OPERATIONS
# ==========================================

## Re-builds composite line overlay showing structural elevation steps.
func update_grid_line_network() -> void:
	if is_instance_valid(_grid_overlay_instance):
		_grid_overlay_instance.queue_free()

	var total_mesh = ImmediateMesh.new()
	
	total_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _thick_line_material)
	_scan_grid_and_draw(total_mesh, LineType.THICK)
	total_mesh.surface_end()
	
	total_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _thin_dotted_material)
	_scan_grid_and_draw(total_mesh, LineType.THIN_DASHED)
	total_mesh.surface_end()
	
	_grid_overlay_instance = MeshInstance3D.new()
	_grid_overlay_instance.mesh = total_mesh
	_grid_overlay_instance.layers = GData.CAMERA_2D_LAYER_BITMASK
	add_child(_grid_overlay_instance)

## Traverses cell edges to plot grid boundaries.
func _scan_grid_and_draw(mesh: ImmediateMesh, line_filter: LineType) -> void:
	for x in range(GRID_WIDTH + 1):
		for z in range(GRID_DEPTH + 1):
			var v_start_x = x * CELL_SIZE
			var v_start_z = z * CELL_SIZE
			var v_next_x = (x + 1) * CELL_SIZE
			var v_next_z = (z + 1) * CELL_SIZE
			
			if z < GRID_DEPTH:
				var left_h = get_height_at(x - 1, z) if x > 0 else -1
				var right_h = get_height_at(x, z) if x < GRID_WIDTH else -1
				_process_edge_drawing(mesh, line_filter, left_h, right_h, Vector3(v_start_x, 0, v_start_z), Vector3(v_start_x, 0, v_next_z), x == 0 or x == GRID_WIDTH)

			if x < GRID_WIDTH:
				var top_h = get_height_at(x, z - 1) if z > 0 else -1
				var bot_h = get_height_at(x, z) if z < GRID_DEPTH else -1
				_process_edge_drawing(mesh, line_filter, top_h, bot_h, Vector3(v_start_x, 0, v_start_z), Vector3(v_next_x, 0, v_start_z), z == 0 or z == GRID_DEPTH)

## Evaluates line dynamic positioning and height offsets for vertex rendering.
func _process_edge_drawing(mesh: ImmediateMesh, line_filter: LineType, h1: int, h2: int, start_pos: Vector3, end_pos: Vector3, is_outer_map_edge: bool) -> void:
	var heights_differ = (h1 != h2)
	var highest_tier = max(h1, h2)
	
	var py = ((highest_tier + 1) * CELL_SIZE) + 0.01
	start_pos.y = py
	end_pos.y = py
	
	match line_filter:
		LineType.THICK:
			if heights_differ:
				_draw_line_style(mesh, LineType.THICK, start_pos, end_pos)
		LineType.THIN_DASHED:
			if not heights_differ and not is_outer_map_edge:
				_draw_line_style(mesh, LineType.THIN_DASHED, start_pos, end_pos)

## Appends primitive lines to target dynamic mesh.
func _draw_line_style(mesh: ImmediateMesh, type: LineType, start: Vector3, end: Vector3) -> void:
	match type:
		LineType.THICK:
			mesh.surface_add_vertex(start)
			mesh.surface_add_vertex(end)
		LineType.THIN_DASHED:
			var segments = 4 
			var delta_step = (end - start) / segments
			for i in range(segments):
				if i % 2 == 0:
					mesh.surface_add_vertex(start + (delta_step * i))
					mesh.surface_add_vertex(start + (delta_step * (i + 1)))
