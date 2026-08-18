extends Node3D
class_name UnitManager

const PAWNS_NODE_NAME = "Pawns"

# State
var pawn_container: Node3D
var selected_pawn: BasePawn


func _ready() -> void:
	_initialize_connection()
	_initialize_containers()
	var pawn_scene = load("uid://ex7q0ctfewon")
		
	if pawn_scene:
		var pawn = spawn_pawn(pawn_scene, Vector2i(0, 0))
		pawn.can_be_disrupted = false
		pawn._use_los = false

## Prepares a dedicated scene node for child pawns to prevent hierarchy clutter.
func _initialize_containers() -> void:
	if has_node(PAWNS_NODE_NAME):
		var old_container = get_node(PAWNS_NODE_NAME)
		remove_child(old_container)
		old_container.queue_free()
	
	pawn_container = Node3D.new()
	pawn_container.name = PAWNS_NODE_NAME
	add_child(pawn_container)

func _initialize_connection():
	EventBus.pawn_move_requested.connect(_on_pawn_move_requested)
	EventBus.board_changed.connect(_on_board_changed)
# ===============================================
# SELECTION MANAGEMENT
# ===============================================

## Selects a given pawn and broadcasts the change.
func select_pawn(pawn: BasePawn) -> void:
	if not is_instance_valid(pawn):
		clear_selection()
		return

	# Avoid redundant selection events
	if selected_pawn == pawn:
		return

	selected_pawn = pawn
	
	# --- Mode Switch ---
	# Switch hover raycasting to MOVE mode
	Global.switch_play_mode(GData.PlayMode.MOVE)
	
	EventBus.pawn_selected.emit(selected_pawn)


## Clears the current pawn selection.
func clear_selection() -> void:
	if selected_pawn == null:
		return

	selected_pawn = null
	
	# --- Mode Switch ---
	# Switch hover raycasting to SELECT mode
	Global.switch_play_mode(GData.PlayMode.SELECT)
	
	EventBus.pawn_deselected.emit()


# ===============================================
# PAWN SPANNING & LIFECYCLE
# ===============================================

## Spawns a pawn scene under the managed Pawns container.
func spawn_pawn(pawn_scene: PackedScene, grid_pos: Vector2i) -> BasePawn:
	if not pawn_scene:
		push_error("UnitManager: Cannot spawn pawn from null PackedScene.")
		return null

	var pawn_instance = pawn_scene.instantiate() as BasePawn
	if not pawn_instance:
		push_error("UnitManager: Instantiated scene is not a BasePawn.")
		return null

	pawn_container.add_child(pawn_instance)
	
	# Store tracking info
	pawn_instance.grid_pos = grid_pos
	Global.board.set_unit_at(grid_pos, pawn_instance)
	
	# Set 3D visual position including height
	var height = Global.board.get_height_at(grid_pos)
	pawn_instance.global_position = Global.board.grid_to_world(grid_pos.x, height, grid_pos.y, true)

	EventBus.pawn_registered.emit(pawn_instance)
	return pawn_instance


func _on_pawn_move_requested(pawn: BasePawn, target_coord: Vector2i) -> void:
	if not is_instance_valid(pawn):
		return

	# 1. Re-validate request against board logic
	if not _valid_move(pawn, target_coord):
		return

	# 2. Check and handle captures
	_handle_occupant_interaction(pawn, target_coord)

	# 3. Transfer position tracking on BoardState
	await move_pawn(pawn, target_coord)

	# 5. Complete state broadcast and clear selection
	EventBus.pawn_moved.emit(pawn, target_coord, true)
	clear_selection()

func move_pawn(pawn : BasePawn, target_coord : Vector2i) -> void:
	Global.board.set_unit_at(pawn.grid_pos, null)
	Global.board.set_unit_at(target_coord, pawn)
	pawn.grid_pos = target_coord

	# Animate movement into world space
	var target_height = Global.board.get_height_at(target_coord)
	var world_pos = Global.board.grid_to_world(target_coord.x, target_height, target_coord.y, true)

	var tween = create_tween()
	tween.tween_property(pawn, "global_position", world_pos, 0.25)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)

	await tween.finished
	return

func _valid_move(pawn : BasePawn, target_coord : Vector2i) -> bool:
	var valid_moves = pawn.get_valid_moves(Global.board)
	if not target_coord in valid_moves:
		EventBus.pawn_moved.emit(pawn, target_coord, false)
		return false
	return true

func _handle_occupant_interaction(pawn : BasePawn, occupant_coord : Vector2i):
	var occupant = Global.board.get_unit_at(occupant_coord)
	if occupant != null and occupant != pawn:
		push_error("Tile already occupied, Not yet implemented effects")

func _on_board_changed() -> void:
	for pawn in get_all_pawns():
		pawn = pawn as BasePawn
		var tile_coord = pawn.grid_pos
		_adjust_pawn_to_tile_height(pawn, tile_coord)

func _adjust_pawn_to_tile_height(pawn: BasePawn, coord: Vector2i) -> void:
	# 1. Fetch updated tier height from BoardState (which now includes size.y)
	var current_tier = Global.board.get_height_at(coord)
	
	# 2. Get 3D world position at top face (atop = true)
	var target_world_pos = Global.board.grid_to_world(coord.x, current_tier, coord.y, true)
	
	# 3. Animate or snap pawn to target height
	var tween = create_tween()
	tween.tween_property(pawn, "global_position:y", target_world_pos.y, 0.15)\
		.set_trans(Tween.TRANS_SPRING)\
		.set_ease(Tween.EASE_OUT)

## Removes a pawn from the board and handles cleanup if it was selected.
func despawn_pawn(pawn: BasePawn = selected_pawn) -> void:
	if not is_instance_valid(pawn):
		return

	if selected_pawn == pawn:
		clear_selection()

	EventBus.pawn_unregistered.emit(pawn)
	pawn.queue_free()


# ===============================================
# QUERY HELPERS
# ===============================================

## Returns an Array of all currently active pawns under management.
func get_all_pawns() -> Array[BasePawn]:
	var list: Array[BasePawn] = []
	if not is_instance_valid(pawn_container):
		return list

	for child in pawn_container.get_children():
		if child is BasePawn:
			list.append(child as BasePawn)
			
	return list


## Finds a pawn occupying a specific grid coordinate, if any.
func get_pawn_at_grid_pos(grid_pos: Vector2i) -> BasePawn:
	return Global.board.get_unit_at(grid_pos)
