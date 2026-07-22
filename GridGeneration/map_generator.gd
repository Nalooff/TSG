extends Node
class_name MapGenerator

# ==========================================
# CONFIGURATION & ENUMS
# ==========================================

enum Mode { AUTO, TOPOLOGY, PLAYER }

## Execution mode strategy used to populate initial terrain layout.
@export var generation_mode: Mode = Mode.AUTO
## Source image used when building via TOPOLOGY mode.
@export var topology_map: Texture2D

## Reference to parent Grid instance.
@onready var grid: Grid = get_parent()


# ==========================================
# INITIALIZATION & GENERATION PIPELINE
# ==========================================

func _ready() -> void:
	await grid.ready
	generate_map()

## Executes the generation algorithm matching the configured mode.
func generate_map() -> void:
	match generation_mode:
		Mode.AUTO: _generate_noise_terrain()
		Mode.TOPOLOGY: _generate_from_topology_colors()
		Mode.PLAYER: _generate_flat_ground()
			
	grid.update_grid_line_network()

## Generates flat baseline terrain at level 0.
func _generate_flat_ground() -> void:
	for x in range(GData.GRID_WIDTH):
		for z in range(GData.GRID_DEPTH):
			grid.add_tile_at(x, 0, z)

## Uses Procedural Simplex Noise to construct organic height elevations.
func _generate_noise_terrain() -> void:
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.15 
	
	for x in range(GData.GRID_WIDTH):
		for z in range(GData.GRID_DEPTH):
			var raw_noise = noise.get_noise_2d(float(x), float(z))
			var normalized_noise = (raw_noise + 1.0) / 2.0
			var max_layer = clampi(int(floor(normalized_noise * GData.GRID_HEIGHT)), 0, 3)
			
			for h in range(max_layer + 1):
				grid.add_tile_at(x, h, z)

## Samples topology heightmap textures to evaluate terrain column stacks.
func _generate_from_topology_colors() -> void:
	if not topology_map:
		_generate_flat_ground()
		return
		
	var img: Image = topology_map.get_image()
	var chunk_w = float(img.get_width()) / GData.GRID_WIDTH
	var chunk_h = float(img.get_height()) / GData.GRID_DEPTH
	
	for gx in range(GData.GRID_WIDTH):
		for gz in range(GData.GRID_DEPTH):
			var start_x = int(gx * chunk_w)
			var start_y = int(gz * chunk_h)
			var c = img.get_pixel(start_x, start_y)
			var target_height = 0
			
			if c.g > c.r and c.g > 0.4: target_height = 0
			elif c.g > 0.5 and c.r > 0.5: target_height = 1
			elif c.r > c.g and c.g > 0.3: target_height = 2
			else: target_height = 3
			
			for h in range(target_height + 1):
				grid.add_tile_at(gx, h, gz)
