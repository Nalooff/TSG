extends Node
class_name MapGenerator

enum Mode { AUTO, TOPOLOGY, PLAYER }
enum LineType { THICK, THIN_DASHED }

@export var generation_mode: Mode = Mode.AUTO
@export var topology_map: Texture2D

@onready var grid: Grid = get_parent()

# Shared 3D rendering cache resources
var _shared_box_mesh: BoxMesh
var _outline_mat: StandardMaterial3D
var _layer_materials: Array[StandardMaterial3D] = []

# Refactored Line Overlay Architecture
var _grid_overlay_instance: MeshInstance3D
var _thick_line_material: StandardMaterial3D
var _thin_dotted_material: StandardMaterial3D

func _ready() -> void:
	await grid.ready
	_precalculate_resources()
	
	match generation_mode:
		Mode.AUTO:
			_generate_noise_terrain()
		Mode.TOPOLOGY:
			_generate_from_topology_colors()
		Mode.PLAYER:
			_generate_flat_ground()
			
	_generate_topdown_grid_network()


# =============================================================================
# 1. VISUAL STYLES & MATERIAL DEFINITIONS
# =============================================================================
## Change colors, thickness elements, or material properties right here.
func _precalculate_resources() -> void:
	_shared_box_mesh = BoxMesh.new()
	_shared_box_mesh.size = Vector3(grid.CELL_SIZE, grid.CELL_SIZE, grid.CELL_SIZE)
	
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.albedo_color = Color.BLACK
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.grow = true
	_outline_mat.grow_amount = 0.1
	
	for color in grid.LAYER_COLORS:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.next_pass = _outline_mat
		_layer_materials.append(mat)

	# --- CHANGE THE LOOK OF THE GRID LINES HERE ---
	_thick_line_material = StandardMaterial3D.new()
	_thick_line_material.albedo_color = Color.BLACK
	_thick_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	_thin_dotted_material = StandardMaterial3D.new()
	_thin_dotted_material.albedo_color = Color(0.1, 0.1, 0.1, 0.4) 
	_thin_dotted_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


# =============================================================================
# 2. CORE MAP GENERATION MATH LOOPS
# =============================================================================
func _generate_flat_ground() -> void:
	for x in range(grid.GRID_WIDTH):
		for z in range(grid.GRID_DEPTH):
			grid.grid_matrix.append(Vector3i(x, 0, z))
			_spawn_visual_tile(x, 0, z)


func _generate_noise_terrain() -> void:
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.15 
	
	for x in range(grid.GRID_WIDTH):
		for z in range(grid.GRID_DEPTH):
			var raw_noise = noise.get_noise_2d(float(x), float(z))
			var normalized_noise = (raw_noise + 1.0) / 2.0
			var height = clampi(int(floor(normalized_noise * 4.0)), 0, 3)
			
			grid.grid_matrix.append(Vector3i(x, height, z))
			_spawn_visual_tile(x, height, z)


func _generate_from_topology_colors() -> void:
	if not topology_map:
		_generate_flat_ground()
		return
		
	var img: Image = topology_map.get_image()
	var chunk_w = float(img.get_width()) / grid.GRID_WIDTH
	var chunk_h = float(img.get_height()) / grid.GRID_DEPTH
	
	for gx in range(grid.GRID_WIDTH):
		for gz in range(grid.GRID_DEPTH):
			var start_x = int(gx * chunk_w)
			var start_y = int(gz * chunk_h)
			var c = img.get_pixel(start_x, start_y)
			var height = 0
			
			if c.g > c.r and c.g > 0.4: height = 0
			elif c.g > 0.5 and c.r > 0.5: height = 1
			elif c.r > c.g and c.g > 0.3: height = 2
			else: height = 3
			
			grid.grid_matrix.append(Vector3i(gx, height, gz))
			_spawn_visual_tile(gx, height, gz)


func _spawn_visual_tile(x: int, target_height: int, z: int) -> void:
	var offset = grid.CELL_SIZE / 2.0
	var world_x = (x * grid.CELL_SIZE) + offset
	var world_z = (z * grid.CELL_SIZE) + offset
	
	for h in range(target_height + 1):
		var world_y = (h * grid.CELL_SIZE) + offset
		var spawn_position = Vector3(world_x, world_y, world_z)
		
		var tile_mesh = MeshInstance3D.new()
		tile_mesh.mesh = _shared_box_mesh
		
		var mat_idx = clampi(h, 0, _layer_materials.size() - 1)
		tile_mesh.material_override = _layer_materials[mat_idx]
		add_child(tile_mesh)
		tile_mesh.global_position = spawn_position
		
		_attach_physics_collision(tile_mesh)


# =============================================================================
# 3. GRID LINE SCANNERS & PIPELINE
# =============================================================================
## Handles the low-level multi-pass mesh compiling setup. 
func _generate_topdown_grid_network() -> void:
	var total_mesh = ImmediateMesh.new()
	
	# Pass 1: Solid heavy borders
	total_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _thick_line_material)
	_scan_grid_and_draw(total_mesh, LineType.THICK)
	total_mesh.surface_end()
	
	# Pass 2: Subtle helper divisions
	total_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _thin_dotted_material)
	_scan_grid_and_draw(total_mesh, LineType.THIN_DASHED)
	total_mesh.surface_end()
	
	_grid_overlay_instance = MeshInstance3D.new()
	_grid_overlay_instance.mesh = total_mesh
	_grid_overlay_instance.layers = 1 << 19 
	add_child(_grid_overlay_instance)


## Iterates grid coordinates to identify spatial vertex positions.
func _scan_grid_and_draw(mesh: ImmediateMesh, line_filter: LineType) -> void:
	for x in range(grid.GRID_WIDTH + 1):
		for z in range(grid.GRID_DEPTH + 1):
			
			var v_start_x = x * grid.CELL_SIZE
			var v_start_z = z * grid.CELL_SIZE
			var v_next_x = (x + 1) * grid.CELL_SIZE
			var v_next_z = (z + 1) * grid.CELL_SIZE
			
			if z < grid.GRID_DEPTH:
				var left_h = grid.get_height_at(x - 1, z) if x > 0 else -1
				var right_h = grid.get_height_at(x, z) if x < grid.GRID_WIDTH else -1
				_process_edge_drawing(mesh, line_filter, left_h, right_h, Vector3(v_start_x, 0, v_start_z), Vector3(v_start_x, 0, v_next_z), x == 0 or x == grid.GRID_WIDTH)

			if x < grid.GRID_WIDTH:
				var top_h = grid.get_height_at(x, z - 1) if z > 0 else -1
				var bot_h = grid.get_height_at(x, z) if z < grid.GRID_DEPTH else -1
				_process_edge_drawing(mesh, line_filter, top_h, bot_h, Vector3(v_start_x, 0, v_start_z), Vector3(v_next_x, 0, v_start_z), z == 0 or z == grid.GRID_DEPTH)


# =============================================================================
# 4. CONDITIONAL OUTLINE RULES
# =============================================================================


func _process_edge_drawing(mesh: ImmediateMesh, line_filter: LineType, h1: int, h2: int, start_pos: Vector3, end_pos: Vector3, is_outer_map_edge: bool) -> void:
	var heights_differ = (h1 != h2)
	var highest_tier = max(h1, h2)
	
	# Set Y position contextually based on the top tile height (+ tiny offset bleed)
	var py = ((highest_tier + 1) * grid.CELL_SIZE) + 0.01
	start_pos.y = py
	end_pos.y = py
	
	match line_filter:
		LineType.THICK:
			if heights_differ:
				_draw_line_style(mesh, LineType.THICK, start_pos, end_pos)
		LineType.THIN_DASHED:
			if not heights_differ and not is_outer_map_edge:
				_draw_line_style(mesh, LineType.THIN_DASHED, start_pos, end_pos)


# =============================================================================
# 5. GEOMETRY RENDER PATTERNS
# =============================================================================


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


# =============================================================================
# 6. HELPERS
# =============================================================================
func _attach_physics_collision(parent_mesh: MeshInstance3D) -> void:
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	
	box_shape.size = _shared_box_mesh.size
	collision_shape.shape = box_shape
	
	static_body.add_child(collision_shape)
	parent_mesh.add_child(static_body)
