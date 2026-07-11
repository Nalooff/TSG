extends Node3D
class_name Grid

# Grid Configuration
const GRID_WIDTH: int = 15
const GRID_DEPTH: int = 15
const CELL_SIZE: float = 2.0

# Layer Colors for Placed Blocks (0 = Dark, 3 = White)
const LAYER_COLORS = [
	Color8(64, 64, 64),     # Layer 0: Dark Grey
	Color8(127, 127, 127),   # Layer 1: Grey
	Color8(192, 192, 192),   # Layer 2: Light Grey
	Color8(255, 255, 255)    # Layer 3: White
]

# Shared center point for cameras to focus on
var center: Vector3 = Vector3(GRID_WIDTH, 0, GRID_DEPTH) * CELL_SIZE / 2.0
var grid_matrix: Array = []

var shared_box_mesh: BoxMesh
var layer_materials: Array[StandardMaterial3D] = []
var _outline_mat: StandardMaterial3D

var _grid_overlay_instance: MeshInstance3D
var _thick_line_material: StandardMaterial3D
var _thin_dotted_material: StandardMaterial3D

enum LineType { THICK, THIN_DASHED }

func _ready() -> void:
	_initialize_matrix_database()
	_precalculate_resources()

## Allocates memory for a 2D array matched to the grid dimensions
func _initialize_matrix_database() -> void:
	grid_matrix.clear()
	for x in range(GRID_WIDTH):
		var row: Array[int] = []
		row.resize(GRID_DEPTH)
		row.fill(0)
		grid_matrix.append(row)

## Creates reusable mesh shapes and material variations for runtime drawing
func _precalculate_resources() -> void:
	shared_box_mesh = BoxMesh.new()
	shared_box_mesh.size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.albedo_color = Color.BLACK
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.grow = true
	_outline_mat.grow_amount = 0.1
	
	for color in LAYER_COLORS:
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

## Spawns physical blocks and adds collision instances to the scene tree
func spawn_visual_tile(x: int, target_height: int, z: int, host_node: Node) -> void:
	var offset = CELL_SIZE / 2.0
	var world_x = (x * CELL_SIZE) + offset
	var world_z = (z * CELL_SIZE) + offset
	
	for h in range(target_height + 1):
		var world_y = (h * CELL_SIZE) + offset
		var spawn_position = Vector3(world_x, world_y, world_z)
		
		var tile_mesh = MeshInstance3D.new()
		tile_mesh.mesh = shared_box_mesh
		
		var mat_idx = clampi(h, 0, layer_materials.size() - 1)
		tile_mesh.material_override = layer_materials[mat_idx]
		host_node.add_child(tile_mesh)
		tile_mesh.global_position = spawn_position
		
		_attach_physics_collision(tile_mesh)

## Generates and links structural collision boxes to a mesh instance
func _attach_physics_collision(parent_mesh: MeshInstance3D) -> void:
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	
	box_shape.size = shared_box_mesh.size
	collision_shape.shape = box_shape
	
	static_body.add_child(collision_shape)
	parent_mesh.add_child(static_body)

## Clears previous instances and builds a fresh, composite line map overlay
func update_grid_line_network(host_node: Node) -> void:
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
	_grid_overlay_instance.layers = 1 << 19 
	host_node.add_child(_grid_overlay_instance)

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
