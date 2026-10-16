extends Node3D

var active_highlights: Array[Node3D] = []

var _path_root: Node3D = null
var _selected_pawn: BasePawn = null
var _reachable: Dictionary = {}
var _hovered_tile: Vector2i = Vector2i(-1, -1)

@export_category("Highlight Customization")
@export var highlight_color: Color = Color(0.2, 0.6, 1.0, 0.1)
@export_custom(PROPERTY_HINT_LINK, "") var highlight_size: Vector2 = Vector2(GData.CELL_SIZE-0.05, GData.CELL_SIZE-0.05)
@export var custom_highlight_material: Material = null

@export_category("Path Preview")
@export var snake_color: Color = Color(1.0, 0.75, 0.15)
@export var tube_radius: float = 0.18
@export var head_radius: float = 0.45
@export var head_length: float = 0.8


func _ready() -> void:
	EventBus.pawn_selected.connect(_on_pawn_selected)
	EventBus.pawn_deselected.connect(_on_pawn_deselected)
	EventBus.pawn_move_requested.connect(_on_pawn_move_requested)
	EventBus.pawn_moved.connect(_on_pawn_moved)
	EventBus.tile_hovered.connect(_on_tile_hovered)


func _on_pawn_selected(pawn: BasePawn) -> void:
	clear_previews()
	_selected_pawn = pawn
	_reachable = {}
	if not pawn:
		return

	_reachable = pawn.movement.get_reachable_paths(Global.board)
	for coord in _reachable.keys():
		_spawn_highlight_at(coord)


func _on_pawn_deselected() -> void:
	_selected_pawn = null
	_reachable.clear()
	clear_previews()


func _on_pawn_move_requested(_pawn: BasePawn, target: Vector2i) -> void:
	# Valid move: hide everything and stop reacting to hovers while the unit walks
	if _reachable.has(target):
		_reachable.clear()
		clear_previews()


func _on_pawn_moved(_pawn: BasePawn, _target: Vector2i, success: bool) -> void:
	# A failed click no longer wipes the preview
	if success:
		clear_previews()


func _on_tile_hovered(data: Dictionary) -> void:
	if _selected_pawn == null:
		return
	var coord: Vector2i = data.grid_pos
	if coord == _hovered_tile:
		return
	_hovered_tile = coord
	_show_path_to(coord)


func _show_path_to(coord: Vector2i) -> void:
	_clear_path()
	if not _reachable.has(coord):
		return

	var tile_points: Array[Vector3] = []
	for c in _reachable[coord]["path"]:
		tile_points.append(_tile_point(c))

	_path_root = PreviewMeshBuilder.create_path_snake(tile_points, snake_color, tube_radius, head_radius, head_length)
	add_child(_path_root)
	_path_root.global_transform = Transform3D.IDENTITY   # points are already in world space


## World position the snake passes through for a tile: top face, lifted above the blue highlight.
func _tile_point(coord: Vector2i) -> Vector3:
	var h := Global.board.get_height_at(coord)
	return Global.board.grid_to_world(coord.x, h, coord.y, true) + Vector3.UP * (tube_radius + 0.12)


func _spawn_highlight_at(coord: Vector2i) -> void:
	var height = Global.board.get_height_at(coord)
	var world_pos = Global.board.grid_to_world(coord.x, height, coord.y) + Vector3(0, GData.CELL_SIZE / 2, 0)
	world_pos.y += 0.1

	var instance = PreviewMeshBuilder.create_tile_highlight(highlight_size, highlight_color, custom_highlight_material)
	add_child(instance)
	instance.global_position = world_pos
	active_highlights.append(instance)


func _clear_path() -> void:
	if is_instance_valid(_path_root):
		_path_root.queue_free()
	_path_root = null


func clear_previews() -> void:
	for node in active_highlights:
		if is_instance_valid(node):
			node.queue_free()
	active_highlights.clear()
	_clear_path()
	_hovered_tile = Vector2i(-1, -1)
