extends Node3D
class_name Grid

enum BuildMode { ADD, REMOVE }

# Grid Configuration
const GRID_WIDTH: int = GData.GRID_WIDTH
const GRID_DEPTH: int = GData.GRID_DEPTH
const GRID_CENTER : Vector3 = GData.GRID_CENTER
const CELL_SIZE: float = GData.CELL_SIZE


const GRID_LAYER_COLORS = GData.GRID_LAYER_COLORS

const TILES_NODE_NAME : String = "Tiles"

# Core Data Matrices
var grid_matrix: Array = []
var visual_matrix: Array = [] # Tracks arrays of Tile nodes per cell

# Dynamic Sub-Container for Scene Tree Tidiness
var tiles_container: Node3D

var shared_box_mesh: BoxMesh
var shared_box_shape: BoxShape3D
var layer_materials: Array[StandardMaterial3D] = []
var _outline_mat: StandardMaterial3D

var _grid_overlay_instance: MeshInstance3D
var _thick_line_material: StandardMaterial3D
var _thin_dotted_material: StandardMaterial3D

enum LineType { THICK, THIN_DASHED }

func _ready() -> void:
	_initialize_containers()
	_initialize_matrix_database()
	_precalculate_resources()
	
	# Connect to the global event bus to listen for placement requests
	EventBus.placement_requested.connect(_on_placement_requested)

## Creates a clean dedicated node in the scene tree to keep meshes clustered away from logic nodes
func _initialize_containers() -> void:
	if has_node(TILES_NODE_NAME):
		var old_container = get_node(TILES_NODE_NAME)
		remove_child(old_container)
		old_container.queue_free()
	
	tiles_container = Node3D.new()
	tiles_container.name = TILES_NODE_NAME
	add_child(tiles_container)

## Allocates memory for both tracking databases matched to the grid dimensions
func _initialize_matrix_database() -> void:
	grid_matrix.clear()
	visual_matrix.clear()
	for x in range(GRID_WIDTH):
		var row: Array[int] = []
		var vis_row: Array = []
		row.resize(GRID_DEPTH)
		row.fill(0)
		vis_row.resize(GRID_DEPTH)
		for z in range(GRID_DEPTH):
			vis_row[z] = [] # Allocates an array pointer inside each coordinate cell
		grid_matrix.append(row)
		visual_matrix.append(vis_row)

## Creates reusable mesh shapes, collision shapes, and material variations
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

## Returns the current layer height stored at the specified coordinates
func get_height_at(x: int, z: int) -> int:
	if x >= 0 and x < GRID_WIDTH and z >= 0 and z < GRID_DEPTH:
		return grid_matrix[x][z]
	return -1

## Assigns a new layer height integer to the specified coordinates
func set_height_at(x: int, z: int, new_height: int) -> void:
	if x >= 0 and x < GRID_WIDTH and z >= 0 and z < GRID_DEPTH:
		grid_matrix[x][z] = new_height

## Cleans up all visual elements located inside a single cell database coordinate
func clear_visual_tile_at(x: int, z: int) -> void:
	if x >= 0 and x < GRID_WIDTH and z >= 0 and z < GRID_DEPTH:
		for tile_node in visual_matrix[x][z]:
			if is_instance_valid(tile_node):
				tile_node.queue_free()
		visual_matrix[x][z] = []

## Spawns physical Tile instances and nests them directly inside the clean container node
func spawn_visual_tile(x: int, target_height: int, z: int) -> void:
	# Purge old instances at this spot first to prevent double-stacking bugs
	clear_visual_tile_at(x, z)
	
	var offset = CELL_SIZE / 2.0
	var world_x = (x * CELL_SIZE) + offset
	var world_z = (z * CELL_SIZE) + offset
	
	for h in range(target_height + 1):
		var world_y = (h * CELL_SIZE) + offset
		var spawn_position = Vector3(world_x, world_y, world_z)
		
		# 1. Instantiate dedicated Tile node (StaticBody3D)
		var tile = Tile.new()
		tile.grid_pos = Vector2i(x, z)
		tile.height_level = h
		tile.collision_layer = GData.TILE.COLLISION_LAYER_BITMASK
		tile.collision_mask = GData.TILE.COLLISION_MASK_BITMASK
		
		# 2. Attach MeshInstance3D
		var tile_mesh = MeshInstance3D.new()
		tile_mesh.mesh = shared_box_mesh
		var mat_idx = clampi(h, 0, layer_materials.size() - 1)
		tile_mesh.material_override = layer_materials[mat_idx]
		tile.add_child(tile_mesh)

		# 3. Attach CollisionShape3D
		var collision_shape = CollisionShape3D.new()
		collision_shape.shape = shared_box_shape
		tile.add_child(collision_shape)
		
		# 4. Add to scene tree & position
		tiles_container.add_child(tile)
		tile.global_position = spawn_position
		
		# Cache the Tile instance reference inside our visual database row
		visual_matrix[x][z].append(tile)

## Intercepts placement request signals from anywhere in the game world
func _on_placement_requested(map_pos: Vector2i, size: Vector3i) -> void:
	var start_height = get_height_at(map_pos.x, map_pos.y)
	if start_height == -1: return # Out of bounds safety escape
	
	# Update the structural heights over the requested footprint dimensions
	for x in range(map_pos.x, map_pos.x + size.x):
		for z in range(map_pos.y, map_pos.y + size.z):
			var current_h = get_height_at(x, z)
			set_height_at(x, z, current_h + size.y)
			
	# Process and reconstruct visual columns cleanly
	for x in range(map_pos.x, map_pos.x + size.x):
		for z in range(map_pos.y, map_pos.y + size.z):
			var new_height = get_height_at(x, z)
			spawn_visual_tile(x, new_height, z)
			
	update_grid_line_network()
	
	var final_coords = Vector3i(map_pos.x, start_height + size.y, map_pos.y)
	EventBus.block_placed.emit(final_coords, size, true)

## Clears previous instances and builds a fresh, composite line map overlay
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

## Evaluates the map dimensions to draw vertical or horizontal cell separators
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

## Filters matching boundaries to determine if they receive a solid or dash styling
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

## Appends primitive vector points directly into the active drawing surface buffer
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
