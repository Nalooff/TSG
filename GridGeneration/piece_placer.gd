extends Node
class_name PiecePlacer

@onready var grid: Grid = get_parent()
@onready var preview: BlockPreview = get_parent().get_node("BlockPreview")

func _unhandled_input(event: InputEvent) -> void:
	# Check for placement confirmation click
	if event.is_action_pressed("place_piece"):
		_try_place_piece_at_cursor()

func _try_place_piece_at_cursor() -> void:
	if not preview or not preview.preview_instance: return
	
	var target_pos = preview.preview_instance.global_position
	
	# Reverse grid indices back out from physics world space configurations
	var gx = int(floor((target_pos.x - (preview.preview_size.x * grid.CELL_SIZE)/2.0) / grid.CELL_SIZE))
	var gz = int(floor((target_pos.z - (preview.preview_size.z * grid.CELL_SIZE)/2.0) / grid.CELL_SIZE))
	
	# Out-of-bounds containment filter
	if gx + preview.preview_size.x > grid.GRID_WIDTH or gz + preview.preview_size.z > grid.GRID_DEPTH:
		print("Cannot place: Section leaves map boundaries!")
		return
		
	# Update the centralized Vector3i database tracking matrix
	for x in range(gx, gx + preview.preview_size.x):
		for z in range(gz, gz + preview.preview_size.z):
			var original_height = grid.get_height_at(x, z)
			grid.set_height_at(x, z, original_height + preview.preview_size.y)
			
	# Instantiate visual representation block
	var physical_block = MeshInstance3D.new()
	physical_block.mesh = BoxMesh.new()
	(physical_block.mesh as BoxMesh).size = Vector3(preview.preview_size) * grid.CELL_SIZE
	
	# Theme block based on new height profile
	var mat = StandardMaterial3D.new()
	var current_layer = clampi(grid.get_height_at(gx, gz), 0, 3)
	mat.albedo_color = grid.LAYER_COLORS[current_layer]
	physical_block.material_override = mat
	
	add_child(physical_block)
	physical_block.global_position = target_pos
	print("Block structural change logged dynamically at matrix coordinates: (", gx, ", ", gz, ")")
