extends Node3D

@export var highlight_scene: PackedScene # Pass a simple MeshInstance3D quad scene here
var active_highlights: Array[Node3D] = []

func _ready() -> void:
	EventBus.pawn_selected.connect(_on_pawn_selected)
	EventBus.pawn_deselected.connect(_on_pawn_deselected)
	EventBus.pawn_moved.connect(_on_pawn_moved)

func _on_pawn_selected(pawn: BasePawn) -> void:
	clear_previews()
	if not pawn:
		return
		
	var valid_moves = pawn.get_valid_moves(Global.board)
	for coord in valid_moves:
		_spawn_highlight_at(coord)

func _on_pawn_deselected() -> void:
	clear_previews()

func _on_pawn_moved(_pawn: BasePawn, _target_coord: Vector2i, _success: bool) -> void:
	clear_previews()

func _spawn_highlight_at(coord: Vector2i) -> void:
	if not highlight_scene:
		return
		
	var height = Global.board.get_height_at(coord)
	var world_pos = Global.board.grid_to_world(coord.x, height, coord.y)
	
	# Hover slightly above block top face to prevent Z-fighting
	world_pos.y += 0.05 
	
	var instance = highlight_scene.instantiate() as Node3D
	add_child(instance)
	instance.global_position = world_pos
	active_highlights.append(instance)

func clear_previews() -> void:
	for node in active_highlights:
		if is_instance_valid(node):
			node.queue_free()
	active_highlights.clear()
