extends Node
class_name MapGenerator

enum Mode { AUTO, TOPOLOGY, PLAYER }

@export var generation_mode: Mode = Mode.AUTO
@export var topology_map: Texture2D

@onready var grid: Grid = get_parent()

# Shared mesh and outline resources initialized once
var _shared_box_mesh: BoxMesh
var _outline_mat: StandardMaterial3D
var _layer_materials: Array[StandardMaterial3D] = []

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


## Generates and caches re-usable meshes and materials to maximize performance
func _precalculate_resources() -> void:
	# 1. Create a single mesh template shared by all blocks
	_shared_box_mesh = BoxMesh.new()
	_shared_box_mesh.size = Vector3(grid.CELL_SIZE, grid.CELL_SIZE, grid.CELL_SIZE)
	
	# 2. Pre-bake the outline pass
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.albedo_color = Color.BLACK
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.grow = true
	_outline_mat.grow_amount = 0.1
	
	# 3. Pre-bake base material states for each distinct height tier
	for color in grid.LAYER_COLORS:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.next_pass = _outline_mat
		_layer_materials.append(mat)


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


## Loops through target height layers to stack structural blocks
func _spawn_visual_tile(x: int, target_height: int, z: int) -> void:
	var offset = grid.CELL_SIZE / 2.0
	var world_x = (x * grid.CELL_SIZE) + offset
	var world_z = (z * grid.CELL_SIZE) + offset
	
	for h in range(target_height + 1):
		var world_y = (h * grid.CELL_SIZE) + offset
		var spawn_position = Vector3(world_x, world_y, world_z)
		
		_instantiate_single_cube_node(spawn_position, h)


## Single-Responsibility factory logic for assembling 3D assets
func _instantiate_single_cube_node(spawn_pos: Vector3, layer_index: int) -> void:
	var tile_mesh = MeshInstance3D.new()
	tile_mesh.mesh = _shared_box_mesh
	
	# Instantly apply pre-calculated cached material configurations
	var mat_idx = clampi(layer_index, 0, _layer_materials.size() - 1)
	tile_mesh.material_override = _layer_materials[mat_idx]
	add_child(tile_mesh)
	tile_mesh.global_position = spawn_pos
	
	# Add physics collision components
	_attach_physics_collision(tile_mesh)


## Injects StaticBody and BoxShapes to facilitate system mouse ray intersections
func _attach_physics_collision(parent_mesh: MeshInstance3D) -> void:
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	
	box_shape.size = _shared_box_mesh.size
	collision_shape.shape = box_shape
	
	static_body.add_child(collision_shape)
	parent_mesh.add_child(static_body)
