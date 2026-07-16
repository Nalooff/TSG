extends Node
class_name MapGenerator

enum Mode { AUTO, TOPOLOGY, PLAYER }
@export var generation_mode: Mode = Mode.AUTO
@export var topology_map: Texture2D

@onready var grid: Grid = get_parent()

func _ready() -> void:
	await grid.ready
	
	generate_map()

func generate_map() -> void:
	match generation_mode:
		Mode.AUTO: _generate_noise_terrain()
		Mode.TOPOLOGY: _generate_from_topology_colors()
		Mode.PLAYER: _generate_flat_ground()
			
	grid.update_grid_line_network()

## Creates a uniform baseline terrain setting all heights to layer zero
func _generate_flat_ground() -> void:
	for x in range(grid.GRID_WIDTH):
		for z in range(grid.GRID_DEPTH):
			grid.set_height_at(x, z, 0)
			grid.spawn_visual_tile(x, 0, z)

## Uses a math noise module to output dynamic altitude variations across the map
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
			
			grid.set_height_at(x, z, height)
			grid.spawn_visual_tile(x, height, z)

## Evaluates pixel channels from an input texture to derive local elevation layers
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
			
			grid.set_height_at(gx, gz, height)
			grid.spawn_visual_tile(gx, height, gz)
