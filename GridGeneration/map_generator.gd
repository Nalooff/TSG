extends Node
class_name MapGenerator

enum Mode { AUTO, TOPOLOGY, PLAYER }

@export var generation_mode: Mode = Mode.AUTO
@export var topology_map: Texture2D

@onready var grid: Grid = get_parent()

func _ready() -> void:
	# Keep initialization synchronous and wait for root dependencies
	await grid.ready
	
	match generation_mode:
		Mode.AUTO:
			_generate_noise_terrain()
		Mode.TOPOLOGY:
			_generate_from_topology_colors()
		Mode.PLAYER:
			_generate_flat_ground()

func _generate_flat_ground() -> void:
	for x in range(grid.GRID_WIDTH):
		for z in range(grid.GRID_DEPTH):
			grid.grid_matrix.append(Vector3i(x, 0, z))
			_spawn_visual_tile(x, 0, z)

func _generate_noise_terrain() -> void:
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.15 # Higher frequency creates smaller clusters and sharper local changes
	
	for x in range(grid.GRID_WIDTH):
		for z in range(grid.GRID_DEPTH):
			var raw_noise = noise.get_noise_2d(float(x), float(z))
			var normalized_noise = (raw_noise + 1.0) / 2.0
			
			# Map to 4 distinct vertical step intervals (0 to 3) preserving cliff drop-offs
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
			
			# Sample chunk average color
			var c = img.get_pixel(start_x, start_y)
			var height = 0
			
			if c.g > c.r and c.g > 0.4: height = 0
			elif c.g > 0.5 and c.r > 0.5: height = 1
			elif c.r > c.g and c.g > 0.3: height = 2
			else: height = 3
			
			grid.grid_matrix.append(Vector3i(gx, height, gz))
			_spawn_visual_tile(gx, height, gz)

func _spawn_visual_tile(x: int, height: int, z: int) -> void:
	var tile_mesh = MeshInstance3D.new()
	tile_mesh.mesh = BoxMesh.new()
	(tile_mesh.mesh as BoxMesh).size = Vector3(grid.CELL_SIZE, (height + 1) * grid.CELL_SIZE, grid.CELL_SIZE)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = grid.LAYER_COLORS[clampi(height, 0, 3)]
	tile_mesh.material_override = mat
	add_child(tile_mesh)
	
	var offset = grid.CELL_SIZE / 2.0
	var p_x = (x * grid.CELL_SIZE) + offset
	var p_y = ((height + 1) * grid.CELL_SIZE) / 2.0
	var p_z = (z * grid.CELL_SIZE) + offset
	tile_mesh.global_position = Vector3(p_x, p_y, p_z)
