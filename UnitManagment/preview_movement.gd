extends Node3D

var active_highlights: Array[Node3D] = []

@export_category("Highlight Customization")
@export var highlight_color: Color = Color(0.2, 0.6, 1.0, 0.6) # Default tactical blue
@export var highlight_size: Vector2 = Vector2(GData.CELL_SIZE-0.05, GData.CELL_SIZE-0.05)
@export var custom_highlight_material: Material = null # Optional theme override asset

func _ready() -> void:
	EventBus.pawn_selected.connect(_on_pawn_selected)
	EventBus.pawn_deselected.connect(_on_pawn_deselected)
	EventBus.pawn_moved.connect(_on_pawn_moved)

func _on_pawn_selected(pawn: BasePawn) -> void:
	clear_previews()
	if not pawn:
		return
		
	var valid_moves = pawn.movement.get_valid_moves(Global.board)
	print(valid_moves)
	for coord in valid_moves:
		_spawn_highlight_at(coord)

func _on_pawn_deselected() -> void:
	clear_previews()

func _on_pawn_moved(_pawn: BasePawn, _target_coord: Vector2i, _success: bool) -> void:
	clear_previews()

func _spawn_highlight_at(coord: Vector2i) -> void:
	var height = Global.board.get_height_at(coord)
	var world_pos = Global.board.grid_to_world(coord.x, height, coord.y) + Vector3(0,GData.CELL_SIZE/2, 0) # offset to put it at the top of the tile
	
	# Hover slightly above block top face to prevent Z-fighting
	world_pos.y += 0.1
	
	# Create the tile highlight via the builder utility, passing size, color, and optional material
	var instance = PreviewMeshBuilder.create_tile_highlight(highlight_size, highlight_color, custom_highlight_material)
	add_child(instance)
	instance.global_position = world_pos
	active_highlights.append(instance)

func clear_previews() -> void:
	for node in active_highlights:
		if is_instance_valid(node):
			node.queue_free()
	active_highlights.clear()
